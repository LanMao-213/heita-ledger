// 加密备份的**端到端**自检：真库 → 加密 → 清空 → 恢复。
//
// `backup_sealed_test.dart` 只测容器（封/解/拒）。那份测试再全，也证明不了
// 一件事：**解出来的东西能不能回到库里**。所以这里把两件事放在一起跑：
//
//   1. 加密往返之后，账本每一类数据都逐项对得上（不只是笔数）；
//   2. 口令错的时候**一行都没写进库** —— 覆盖式写入没有第二次机会，
//      而「解不开」和「解出一堆空表灌进去」在界面上长得一模一样。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// backup_service 会 re-export payload / sealed_file / snapshot，所以只 import 它
import 'package:ledger/data/backup_service.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_backup_roundtrip.db';

/// 测试迭代数：1000。理由见 `backup_sealed_test.dart` 的同一个常量。
const _fastIter = 1000;
const _password = '把数据带走 · 2026';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 数据库指纹：数量 + 金额，光对笔数不够。
Future<({int txns, int sumCents, int accounts, int categories, int netWorth})>
_fingerprint() async {
  final db = await Db.open();
  final t = await db.rawQuery(
    'SELECT COUNT(*) AS c, COALESCE(SUM(amount_cents), 0) AS s FROM txn',
  );
  final a = await db.rawQuery('SELECT COUNT(*) AS c FROM account');
  final c = await db.rawQuery('SELECT COUNT(*) AS c FROM category');
  return (
    txns: (t.first['c'] as int?) ?? 0,
    sumCents: (t.first['s'] as int?) ?? 0,
    accounts: (a.first['c'] as int?) ?? 0,
    categories: (c.first['c'] as int?) ?? 0,
    netWorth: await Repo.totalBalanceCents(),
  );
}

/// 造一本有内容的账：几笔支出/收入 + 一笔转账 + 预算 + 目标 + 模板。
Future<void> _seed() async {
  await Store.i.boot();
  final s = Store.i;
  final cat = s.expenseCats.first.id;
  final income = s.incomeCats.first.id;
  final accounts = s.accounts;
  final acc = accounts.first.id;

  await Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.expense,
      amountCents: 2350,
      date: '2026-10-20',
      categoryId: cat,
      accountId: acc,
      note: '午饭 · 楼下那家面馆',
      placeTo: '面馆',
    ),
  );
  await Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.income,
      amountCents: 880000,
      date: '2026-10-10',
      categoryId: income,
      accountId: acc,
      note: '工资',
    ),
  );
  if (accounts.length >= 2) {
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.transfer,
        amountCents: 50000,
        date: '2026-10-12',
        accountId: acc,
        toAccountId: accounts[1].id,
        note: '转到现金',
      ),
    );
  }
  await Repo.setBudget(
    ledgerId: s.ledgerId,
    periodStart: s.cycleFrom,
    categoryId: null,
    amountCents: 300000,
  );
  await Repo.insertGoal(
    const SavingGoal(id: 0, name: '相机', targetCents: 500000),
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
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  group('加密往返', () {
    test('真库 → seal → 清空 → unseal → restore：每一类数据都对得上', () async {
      await _seed();
      final before = await _fingerprint();
      expect(before.txns, greaterThanOrEqualTo(2));

      // 1. 导出并加密（走 facade，和界面同一条路）
      final payload = await BackupService.dump();
      final text = await SealedBackupFile.seal(
        payload,
        password: _password,
        iterations: _fastIter,
      );

      // 2. 清空
      await Db.wipeAllData();
      await Store.i.reboot();
      final emptied = await _fingerprint();
      expect(emptied.txns, 0);

      // 3. 解密 + 恢复
      final decoded = await SealedBackupFile.unseal(text, password: _password);
      await BackupService.restore(decoded);
      await Store.i.reboot();

      final after = await _fingerprint();
      expect(after.txns, before.txns, reason: '笔数对不上');
      expect(after.sumCents, before.sumCents, reason: '金额合计对不上');
      expect(after.accounts, before.accounts);
      expect(after.categories, before.categories);
      expect(after.netWorth, before.netWorth, reason: '净资产对不上 —— 账户余额没回来');

      // 备注、地点这些「不参与统计但用户看得见」的字段也要回来
      final db = await Db.open();
      final rows = await db.query('txn', where: "note = ?", whereArgs: ['午饭 · 楼下那家面馆']);
      expect(rows, hasLength(1), reason: '中文备注没恢复（编码在这一层最容易坏）');
      expect(rows.single['place_to'], '面馆');
    });
  });

  group('拒绝时一行都不写', () {
    test('口令错：抛 wrongPasswordOrCorrupt，且库里的数据一条没少', () async {
      await _seed();
      final before = await _fingerprint();

      final text = await SealedBackupFile.seal(
        await BackupService.dump(),
        password: _password,
        iterations: _fastIter,
      );

      await expectLater(
        () => SealedBackupFile.unseal(text, password: '不对的口令'),
        throwsA(
          isA<BackupSealedException>().having(
            (e) => e.kind,
            'kind',
            SealedFailureKind.wrongPasswordOrCorrupt,
          ),
        ),
      );

      // 解不开就没走到 restore —— 库应当**原封不动**
      final after = await _fingerprint();
      expect(after, before, reason: '解不开的备份不该动到现有数据');
    });

    test('文件被截断：同样一行都不写', () async {
      await _seed();
      final before = await _fingerprint();
      final text = await SealedBackupFile.seal(
        await BackupService.dump(),
        password: _password,
        iterations: _fastIter,
      );
      // 砍掉尾部 = 丢 tag
      final truncated = text.substring(0, text.length - 200);

      // 截在 JSON 尾部时，连「这是不是加密文件」都判断不出来（信封本身残了），
      // 于是抛的是更基础的 BackupException。两条路都是「拒绝」，用户在界面上
      // 看到的都是一句「这个文件不对」—— 这里钉的是**拒绝**这件事。
      await expectLater(
        () => SealedBackupFile.decodeAny(truncated, password: _password),
        throwsA(isA<BackupException>()),
      );
      expect(await _fingerprint(), before);
    });
  });

  group('空库与明文老文件', () {
    test('空库（没有流水）也能导出 —— 那是「我现在什么都没有」的记录', () async {
      await Store.i.boot();
      final db = await Db.open();
      await db.delete('txn');
      await db.delete('budget');
      await db.delete('saving_goal');

      final payload = await BackupService.dump();
      final text = await SealedBackupFile.seal(
        payload,
        password: _password,
        iterations: _fastIter,
      );
      expect(text, isNotEmpty);

      final decoded = await SealedBackupFile.unseal(text, password: _password);
      // 注意：真正的「空库」并不是零行 —— 账本/账户/分类是种子数据，
      // 没有它们 App 打不开。所以这份备份里仍然有几百行，恢复它是合法的。
      final tables = (decoded['tables']! as Map).cast<String, Object?>();
      expect((tables['txn']! as List), isEmpty);
      expect((tables['account']! as List), isNotEmpty, reason: '种子账户应当还在');
    });

    test('一份**没有任何行**的备份：恢复必须被拒（否则会清空现有数据）', () async {
      await _seed();
      final before = await _fingerprint();

      // 「空备份」= 所有已知表都是空的。它多半意味着选错了文件或文件没写完，
      // 拿它去覆盖用户现有的账本是最坏的结果。
      final hollow = await BackupService.dump();
      hollow['tables'] = {
        for (final t in Repo.backupTables) t: <Object?>[],
      };
      await expectLater(
        () => BackupService.restore(hollow),
        throwsA(isA<BackupException>()),
      );
      expect(await _fingerprint(), before, reason: '被拒的恢复不该动到数据');
    });

    test('v1 明文备份（顶层没有 container 字段）仍然能恢复', () async {
      await _seed();
      final before = await _fingerprint();

      // 1.5.x / 1.6.0 导出的就是这一种：payload 平铺，没有 container 信封
      final legacy = await BackupService.dump();
      expect(legacy.containsKey('container'), isFalse);
      final json = PlainBackupFile.encode(legacy);
      expect(PlainBackupFile.decode(json), equals(legacy));

      await Db.wipeAllData();
      await Store.i.reboot();
      await BackupService.restore(PlainBackupFile.decode(json));
      await Store.i.reboot();
      expect(await _fingerprint(), before);
    });
  });

  group('大库性能', () {
    /// 2 万笔的 payload。直接造数据而不灌库：这里量的是**加解密**这一段，
    /// 数据库往返的耗时是另一件事（`txn_keyset_paging_test` 那类测试管）。
    Map<String, Object?> bigPayload(int rows) => {
      'format': BackupPayload.format,
      'formatVersion': BackupPayload.formatVersion,
      'schemaVersion': Db.schemaVersion,
      'exportedAt': '2026-10-20T10:00:00.000',
      'tables': {
        'ledger': [
          {'id': 1, 'name': '日常'},
        ],
        'txn': [
          for (var i = 0; i < rows; i++)
            {
              'id': i,
              'amount_cents': 12345,
              'type': 'expense',
              'category_id': 3,
              'account_id': 1,
              'date': '2026-10-01',
              'note': '午饭 · 楼下那家面馆 · 加了两个卤蛋',
              'period_start': '2026-10-01',
            },
        ],
      },
    };

    test('20k 笔：单次 seal / unseal 不出现数量级回归（< 6s）', () async {
      final payload = bigPayload(20000);
      final sw = Stopwatch()..start();
      final text = await SealedBackupFile.seal(
        payload,
        password: _password,
      );
      final sealMs = sw.elapsedMilliseconds;
      sw.reset();
      final out = await SealedBackupFile.unseal(text, password: _password);
      final unsealMs = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print(
        'BENCH 20k: seal=${sealMs}ms unseal=${unsealMs}ms '
        'file=${(text.length / 1048576).toStringAsFixed(2)}MB',
      );

      expect(
        (out['tables']! as Map)['txn'],
        hasLength(20000),
        reason: '解出来的行数少了',
      );
      // 单次操作才是用户能感觉到的那一段（导出等一次、恢复等一次）。
      // 独立运行时的实测值：seal ≈ 1.85s、unseal ≈ 1.78s
      //（其中 ~1.25s 是 KDF 210000 迭代、~0.5s 是 3MB 的纯 Dart GCM）。
      //
      // 门限放到 6s 是**故意的**：`flutter test` 默认并行跑 4~8 个测试文件，
      // 争 CPU 时这些数会翻两三倍。这条用例要抓的是数量级回归（比如有人把
      // 迭代数写成 600 万、或者把整库 dump 塞进 AAD），不是基准测试；
      // 真实耗时的绝对值记在 docs/decisions/加密备份选型.md。
      expect(
        sealMs,
        lessThan(6000),
        reason: '加密导出等了 ${sealMs}ms（独立运行时约 1.85s）',
      );
      expect(
        unsealMs,
        lessThan(6000),
        reason: '解密等了 ${unsealMs}ms（独立运行时约 1.78s）',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
