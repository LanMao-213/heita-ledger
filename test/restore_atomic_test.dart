// 恢复的**原子性**自检：挂在 `afterLoad` 上的迁移必须和「灌行」同生共死。
//
// 背景（1.5.0 修正的 P2 遗留）：从旧备份恢复时，分类由扁平升两级这一步
// 原本在 `Repo.replaceTables` 返回**之后**单独执行（`Db.upgradeRestoredData()`）。
// 那时灌行已经提交，迁移一旦中途失败，就是「账目进来了、分类只升了一半」，
// 而调用方拿到异常后会对用户说「恢复失败，数据未改动」—— 那句话是假的。
//
// 这条用例专门钉这个性质：让 afterLoad 抛异常，然后看账目条数。
//   · 若它跑在事务里 → 整次覆盖回滚，条数不变（现在）
//   · 若它跑在事务外 → 灌行已提交、条数变成 0（1.4.x 的行为）
// 所以「条数不变」本身就是「钩子在事务内」的证据，不需要读实现。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_restore_atomic.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<int> _countTxns() async {
  final db = await Db.open();
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM txn');
  return (rows.first['c'] as int?) ?? 0;
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
    await Store.i.boot();
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  /// 造一条账目。演示数据只铺分类与账户、不铺流水，所以要自己写一条 ——
  /// 没有账目的话，下面那条用例就分不清「回滚了」和「本来就没有」。
  Future<void> seedOneTxn() async {
    final s = Store.i;
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.expense,
        amountCents: 1250,
        date: '2026-10-28',
        accountId: s.accounts.first.id,
      ),
    );
  }

  test('afterLoad 抛异常 → 整次覆盖回滚，账目一条不少', () async {
    await seedOneTxn();
    final before = await _countTxns();
    expect(before, greaterThan(0), reason: '前置：库里得有账目，否则这条用例证明不了什么');

    // 拿一份「账目标记为 0 条」的载荷：如果它被提交了，条数就会从 before 掉到 0，
    // 一眼能看出来「灌行先提交、迁移后失败」。
    final tables = await Repo.dumpTables();
    tables['txn'] = <Map<String, Object?>>[];

    await expectLater(
      Repo.replaceTables(
        tables,
        afterLoad: (txn) async => throw StateError('迁移中途失败'),
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      await _countTxns(),
      before,
      reason: 'afterLoad 抛异常后账目条数变了 → 说明它跑在事务外，'
          '恢复失败时用户会看到「数据已回滚」，实际却已经改了一半',
    );
  });

  test('afterLoad 正常返回 → 整次覆盖与迁移一起提交', () async {
    await seedOneTxn();
    final tables = await Repo.dumpTables();
    tables['txn'] = <Map<String, Object?>>[];

    var ran = false;
    await Repo.replaceTables(
      tables,
      afterLoad: (txn) async {
        ran = true;
        // 拿到的必须是真事务：能读到本次刚灌进去的行（这里是 0 条 txn）
        final rows = await txn.query('txn');
        expect(rows, isEmpty, reason: '钩子拿到的读者看不到本次灌入的数据 → 不是同一个事务');
      },
    );

    expect(ran, isTrue);
    expect(await _countTxns(), 0, reason: '成功路径下覆盖必须真的落库');
  });
}
