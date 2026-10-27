// v9 的两条**部分唯一索引**：把两类重复从「代码里挡」改成「物理上不可能」。
//
// 为什么要单独一份测试：索引是 SQL，写错了**不会报错**，只会安静地不生效 ——
// 漏掉 `WHERE recurring_id IS NOT NULL`、或者手滑写成普通索引，重复数据照样能
// 插进去，而且没有任何迹象。所以从两个方向钉死：
//
//   1. 新库：重复插入必须抛 `DatabaseException`
//      （证明约束真的在，而不是"我以为它会在"）；
//   2. 老库：带存量重复的 v8 库升上来，重复被清理、**金额一分不动**
//      （证明迁移不会为了建索引而删用户的钱）。
//
// 第 2 条尤其重要：直接 `CREATE UNIQUE INDEX` 在脏库上会让整条迁移抛异常，
// 用户看到的是「升级后打不开」。清理口径见 `Db._addUniqueIndexes`。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_unique_v9.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<void> _removeDbFile() async {
  final f = File(await _dbPath());
  if (f.existsSync()) f.deleteSync();
}

/// 插一条周期生成的流水。`recurring_id` 非空才参与唯一性判断。
Future<int> _insertRecurringTxn(
  Database db, {
  required int ledgerId,
  required int recurringId,
  required String date,
  required int cents,
}) {
  return db.insert('txn', {
    'ledger_id': ledgerId,
    'type': 'expense',
    'amount_cents': cents,
    'date': date,
    'recurring_id': recurringId,
  });
}

/// 插一条「总预算」：`category_id` 为 NULL，正是表级 UNIQUE 管不到的那半边。
Future<int> _insertTotalBudget(
  Database db, {
  required int ledgerId,
  required String periodStart,
  required int cents,
}) {
  return db.insert('budget', {
    'ledger_id': ledgerId,
    'period_start': periodStart,
    'category_id': null,
    'amount_cents': cents,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await Db.close();
    Db.fileName = _dbName;
    await _removeDbFile();
  });

  tearDown(() async {
    await Db.close();
    await _removeDbFile();
  });

  test('新库：同一周期同一天插不进第二条流水', () async {
    await Db.open();
    final db = Db.cached!;
    final ledgerId = (await db.query('ledger')).first['id']! as int;

    await _insertRecurringTxn(
      db,
      ledgerId: ledgerId,
      recurringId: 7,
      date: '2026-10-01',
      cents: 100,
    );

    await expectLater(
      _insertRecurringTxn(
        db,
        ledgerId: ledgerId,
        recurringId: 7,
        date: '2026-10-01',
        cents: 200,
      ),
      throwsA(isA<DatabaseException>()),
      reason: '同一 recurring_id + date 只允许一条',
    );
  });

  test('新库：不同周期或不同日期仍可各插一条', () async {
    await Db.open();
    final db = Db.cached!;
    final ledgerId = (await db.query('ledger')).first['id']! as int;

    await _insertRecurringTxn(
      db,
      ledgerId: ledgerId,
      recurringId: 7,
      date: '2026-10-01',
      cents: 100,
    );
    // 同周期换一天：允许
    await _insertRecurringTxn(
      db,
      ledgerId: ledgerId,
      recurringId: 7,
      date: '2026-11-01',
      cents: 100,
    );
    // 同一天换周期：允许
    await _insertRecurringTxn(
      db,
      ledgerId: ledgerId,
      recurringId: 8,
      date: '2026-10-01',
      cents: 100,
    );

    expect((await db.query('txn')).length, 3);
  });

  test('新库：手工记账 recurring_id 为 NULL，同一天可以有很多条', () async {
    await Db.open();
    final db = Db.cached!;
    final ledgerId = (await db.query('ledger')).first['id']! as int;

    for (var i = 0; i < 5; i++) {
      await db.insert('txn', {
        'ledger_id': ledgerId,
        'type': 'expense',
        'amount_cents': 100,
        'date': '2026-10-01',
      });
    }

    expect(
      (await db.query('txn')).length,
      5,
      reason: 'SQLite 的唯一索引不比较 NULL，所以手工流水不受影响',
    );
  });

  test('新库：同一账本同一期插不进第二条总预算', () async {
    await Db.open();
    final db = Db.cached!;
    final ledgerId = (await db.query('ledger')).first['id']! as int;

    await _insertTotalBudget(
      db,
      ledgerId: ledgerId,
      periodStart: '2026-10-01',
      cents: 100000,
    );

    await expectLater(
      _insertTotalBudget(
        db,
        ledgerId: ledgerId,
        periodStart: '2026-10-01',
        cents: 200000,
      ),
      throwsA(isA<DatabaseException>()),
      reason: '表级 UNIQUE 对 NULL 不生效，靠 ux_budget_total 兜住',
    );
  });

  test('新库：分类预算不受总预算索引影响，可各插一条', () async {
    await Db.open();
    final db = Db.cached!;
    final ledgerId = (await db.query('ledger')).first['id']! as int;
    final categoryId = (await db.query('category')).first['id']! as int;

    await _insertTotalBudget(
      db,
      ledgerId: ledgerId,
      periodStart: '2026-10-01',
      cents: 100000,
    );
    await db.insert('budget', {
      'ledger_id': ledgerId,
      'period_start': '2026-10-01',
      'category_id': categoryId,
      'amount_cents': 50000,
    });

    expect((await db.query('budget')).length, 2);
  });

  test('v8 老库带重复：升到 v9 后清理重复、金额一分不动', () async {
    // 先建出 v9 的新库，再"退回 v8"——比手抄整份 v8 表结构可靠得多：
    // 表结构永远跟着源码走，不会因为漏改这份测试而失真。
    await Db.open();
    final before = Db.cached!;
    await before.execute('DROP INDEX IF EXISTS ux_txn_recurring_date');
    await before.execute('DROP INDEX IF EXISTS ux_budget_total');
    await before.execute('PRAGMA user_version = 8');

    final ledgerId = (await before.query('ledger')).first['id']! as int;

    // 两组周期流水：第一组 2 条重复（100 + 200），第二组 1 条（50）
    await _insertRecurringTxn(
      before,
      ledgerId: ledgerId,
      recurringId: 7,
      date: '2026-10-01',
      cents: 100,
    );
    await _insertRecurringTxn(
      before,
      ledgerId: ledgerId,
      recurringId: 7,
      date: '2026-10-01',
      cents: 200,
    );
    await _insertRecurringTxn(
      before,
      ledgerId: ledgerId,
      recurringId: 8,
      date: '2026-10-02',
      cents: 50,
    );

    // 同一期两条总预算：旧 500 元、新 800 元
    await _insertTotalBudget(
      before,
      ledgerId: ledgerId,
      periodStart: '2026-10-01',
      cents: 50000,
    );
    await _insertTotalBudget(
      before,
      ledgerId: ledgerId,
      periodStart: '2026-10-01',
      cents: 80000,
    );

    await Db.close();
    await Db.open(); // 这一步触发 v8 → v9

    final after = Db.cached!;

    final txns = await after.query('txn');
    expect(txns.length, 3, reason: '流水一条都不能少');
    final cents = txns.fold<int>(
      0,
      (sum, row) => sum + (row['amount_cents']! as int),
    );
    expect(cents, 350, reason: '金额一分不能动（100 + 200 + 50）');

    final claimed = txns.where((r) => r['recurring_id'] != null).length;
    expect(claimed, 2, reason: '两组各留一条周期归属，重复那条降级为普通流水');

    final budgets = await after.query('budget', where: 'category_id IS NULL');
    expect(budgets.length, 1, reason: '总预算只留一条');
    expect(
      budgets.first['amount_cents'],
      80000,
      reason: '保留最近一次设置（id 最大那条）',
    );

    final idx = await after.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name IN ('ux_txn_recurring_date', 'ux_budget_total')",
    );
    expect(idx.length, 2, reason: '两条索引必须真的建起来');
  });

  test('迁移幂等：索引已存在时再跑一次 v9 迁移不报错', () async {
    await Db.open();
    final db = Db.cached!;
    final ledgerId = (await db.query('ledger')).first['id']! as int;

    await _insertRecurringTxn(
      db,
      ledgerId: ledgerId,
      recurringId: 7,
      date: '2026-10-01',
      cents: 100,
    );
    await _insertTotalBudget(
      db,
      ledgerId: ledgerId,
      periodStart: '2026-10-01',
      cents: 50000,
    );

    // 把版本退回 8，让下一次 open 真的**再跑一遍** v9 迁移。
    // 此时两条索引已经存在，`IF NOT EXISTS` 必须把它们吞掉而不是抛错；
    // 清理语句在无重复的数据上也应该是空操作。
    await db.execute('PRAGMA user_version = 8');
    await Db.close();
    await Db.open();

    expect((await Db.cached!.query('txn')).length, 1);
    expect((await Db.cached!.query('budget')).length, 1);
  });

  test('v7/v8 装机后未再升级的设备：升到 v9 时补回 idx_txn_debt', () async {
    // 这一批设备的状态很特殊：建表脚本当年没有这条索引，`_addDebtTable`（v6→v7）
    // 又只对更老的库跑 —— 两边的补偿都轮不到它们。所以升 v9 时必须顺手补一次，
    // 否则 `txn.debt_id` 永远没索引，借还款攒多之后往来页越用越慢。
    await Db.open();
    final db = Db.cached!;

    await db.execute('DROP INDEX IF EXISTS idx_txn_debt');
    await db.execute('PRAGMA user_version = 8');

    final before = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_txn_debt'",
    );
    expect(before, isEmpty, reason: '前置条件：模拟的设备上确实没有该索引');

    await Db.close();
    await Db.open(); // 这一步触发 v8 → v9

    final after = await Db.cached!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_txn_debt'",
    );
    expect(after, hasLength(1), reason: 'v9 迁移要把这条历史遗留索引补上');
  });
}
