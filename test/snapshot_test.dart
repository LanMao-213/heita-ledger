// 自动快照的自检（1.4.3 的「数据安全」）。
//
// 这一层要钉的不是「文件写得出来」，而是三件要命的事：
// 1) 清空 / 恢复之前留的那份是真的能**恢复回去**的（不是只写了个空壳文件）；
// 2) 轮转只删 auto-*，超量 / 过期才删，用户手动导出的备份绝不碰；
// 3) 坏文件要能被列出来（`readable == false`），而不是让整页崩掉。
//
// 目录用 `BackupService.snapshotDirOverride` 指到临时目录 —— 单测里没有
// path_provider 的平台通道（和 `Db.fileName` 同一个思路）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/backup_service.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/safety_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_snapshot.db';

late Directory _snapDir;

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<void> _addExpense(int cents, {String? note}) async {
  final s = Store.i;
  await Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.expense,
      amountCents: cents,
      date: Fmt.today(),
      categoryId: s.expenseCats.first.id,
      accountId: s.accounts.first.id,
      note: note ?? '午饭',
    ),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();

    _snapDir = Directory.systemTemp.createTempSync('heita_snap_');
    BackupService.snapshotDirOverride = () async => _snapDir;

    await Store.i.boot();
  });

  tearDownAll(() async {
    BackupService.snapshotDirOverride = null;
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
    if (_snapDir.existsSync()) _snapDir.deleteSync(recursive: true);
  });

  test('快照能原样恢复：记 2 笔 → 快照 → 清空 → 用快照还原', () async {
    await _addExpense(12800);
    await _addExpense(3300, note: '打车');

    final path = await BackupService.writeSnapshot(reason: 'wipe');
    expect(File(path).existsSync(), isTrue);
    expect(p.basename(path), startsWith('auto-wipe-'));
    expect(p.dirname(path), _snapDir.path);

    // 快照里确实有这两笔
    final payload = await BackupService.readFile(path);
    expect(BackupService.summarize(payload).txns, 2);

    // 清空（1.4.2 起是单事务，这里顺带兜住「别把快照也删了」）
    await Db.wipeAllData();
    await Store.i.reboot();
    expect(Store.i.txns, isEmpty);

    await BackupService.restore(payload);
    await Store.i.reloadAfterRestore();
    expect(Store.i.txns, hasLength(2), reason: '快照必须能把这 2 笔还原回来');
    expect(Store.i.txns.map((t) => t.amountCents).toSet(), {12800, 3300});
  });

  test('列表按时间倒序，并说明快照是哪个动作留下的', () async {
    await _addExpense(1000);
    await BackupService.writeSnapshot();
    // 文件名里的时间戳精确到秒，隔一秒才排得开
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await BackupService.writeSnapshot(reason: 'wipe');

    final items = await BackupService.listSnapshots();
    expect(items, hasLength(2));
    expect(items.first.reason, 'wipe');
    expect(items.first.reasonLabel, '清空前');
    expect(items.last.reasonLabel, '自动快照');
    expect(items.first.readable, isTrue);
    expect(items.first.contentLabel, contains('1 笔记录'));
    expect(items.first.sizeLabel, isNotEmpty);
    expect(items.first.timeLabel.length, 16); // 2026-10-20 17:21
  });

  test('坏文件会被列出来但标成不可恢复，不会让整页炸掉', () async {
    await _addExpense(1000);
    await BackupService.writeSnapshot(reason: 'wipe');

    File(p.join(_snapDir.path, 'auto-manual-20260101-101010.json'))
        .writeAsStringSync('{ 这不是 json');

    final items = await BackupService.listSnapshots();
    expect(items, hasLength(2));
    final broken = items.firstWhere((i) => !i.readable);
    expect(broken.reasonLabel, '手动备份');
    expect(broken.contentLabel, '文件损坏，无法恢复');
  });

  test('轮转只留最近 3 份，且不碰用户自己的备份文件', () async {
    // 5 份快照，时间都落在最近几分钟内（只考「超量」，不掺「过期」）
    final now = DateTime.now();
    String stamp(DateTime t) {
      String two(int v) => v.toString().padLeft(2, '0');
      return '${t.year}${two(t.month)}${two(t.day)}-'
          '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    }

    for (var i = 0; i < 5; i++) {
      final t = now.subtract(Duration(minutes: i));
      File(p.join(_snapDir.path, 'auto-wipe-${stamp(t)}.json'))
          .writeAsStringSync('{}');
    }
    // 用户手动导出的备份：不该被轮转删掉
    final userFile = File(p.join(_snapDir.path, '黑塔消费日记-备份-20260101.json'));
    userFile.writeAsStringSync('{}');

    final removed = await BackupService.pruneSnapshots();
    expect(removed, 2, reason: '5 份留 3 份，删 2 份');
    expect(await BackupService.listSnapshots(), hasLength(3));
    expect(userFile.existsSync(), isTrue, reason: '用户导出的备份不能被当成快照删掉');
  });

  test('过期（超过 7 天）的快照即使没超量也会被清掉', () async {
    final old = File(p.join(_snapDir.path, 'auto-20200101-101010.json'))
      ..writeAsStringSync('{}');
    // 用文件时间「做旧」：内容里的时间戳才是判据
    expect(old.existsSync(), isTrue);

    await BackupService.pruneSnapshots(keep: 3);
    // 2020 年的文件名解析出来就是 7 天以前，必删
    expect(old.existsSync(), isFalse);
  });

  test('手删单份快照；删不存在的文件不报错', () async {
    await _addExpense(1000);
    final path = await BackupService.writeSnapshot(reason: 'manual');
    await BackupService.deleteSnapshot(path);
    expect(File(path).existsSync(), isFalse);

    await BackupService.deleteSnapshot(path); // 幂等
  });
  testWidgets('数据安全页：没有快照时给出空态与说明', (tester) async {
    // 页面长高了（1.6.0 加了「导出到手机」一块），默认 800×600 会把空态挤到
    // 折叠线以下 —— 给足高度，让这条断言继续测「空态在不在」而不是「滚没滚到」
    tester.view.physicalSize = const Size(390 * 2, 1600 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());
    await tester.pumpWidget(const MaterialApp(home: SafetyPage()));
    await tester.pumpAndSettle();

    expect(find.text('数据安全'), findsOneWidget);
    expect(find.text('还没有快照'), findsOneWidget);
    // 右上角的「现在备份」必须在，不能只能在清空时被动留快照
    expect(find.text('现在备份'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
