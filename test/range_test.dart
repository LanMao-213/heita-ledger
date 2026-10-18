// 周期查询（range*）自检 —— F5 阶段 3。
//
// 阶段 3 把「按月查」换成「按期查」，但**UI 还没切**：旧的 month* 方法变成
// 薄委托，账单日默认 1 时两者结果必须完全一致。所以这里钉三件事：
// 1) 区间是含头含尾的，且只认 `period_start`（不是 `date`）；
// 2) 抬期之后，一笔工资要出现在它被抬进的那一期里，而不是真实日期那一期；
// 3) 列表条数 == 合计里的笔数 —— 这条能一次性抓住所有归属期错位。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_range.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  late int ledgerId;
  late int catFood;
  late int catTraffic;
  late int catSalary;
  late int catParttime;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();

    await Db.open();
    ledgerId = await Repo.currentLedgerId();
    final expenses = await Repo.listCategories(ledgerId, type: TxnType.expense);
    final incomes = await Repo.listCategories(ledgerId, type: TxnType.income);
    catFood = expenses.firstWhere((c) => c.name == '餐饮').id;
    catTraffic = expenses.firstWhere((c) => c.name == '交通').id;
    catSalary = incomes.firstWhere((c) => c.name == '工资').id;
    catParttime = incomes.firstWhere((c) => c.name == '兼职').id;
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  Future<void> add({
    required TxnType type,
    required String date,
    required int categoryId,
    int cents = 1000,
  }) => Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledgerId,
      type: type,
      amountCents: cents,
      date: date,
      categoryId: categoryId,
    ),
  );

  group('账单日 15', () {
    setUp(() async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
    });

    test('区间含头含尾，区间外一天不进合计', () async {
      await add(type: TxnType.expense, date: '2026-10-15', categoryId: catFood);
      await add(type: TxnType.expense, date: '2026-11-14', categoryId: catFood);
      // 下面这三笔都不在 10-15 ~ 11-14 这一期
      await add(type: TxnType.expense, date: '2026-10-14', categoryId: catFood);
      await add(type: TxnType.expense, date: '2026-11-15', categoryId: catFood);
      await add(type: TxnType.expense, date: '2026-12-01', categoryId: catFood);

      final (exp, _, cnt) = await Repo.rangeTotals(
        ledgerId,
        '2026-10-15',
        '2026-11-14',
      );
      expect(cnt, 2, reason: '10-15 与 11-14 各算一笔');
      expect(exp, 2000);
    });

    test('抬期后，工资算进被抬进的那一期', () async {
      await add(
        type: TxnType.income,
        date: '2026-10-10',
        categoryId: catSalary,
      );

      final (_, incomeThis, cntThis) = await Repo.rangeTotals(
        ledgerId,
        '2026-10-15',
        '2026-11-14',
      );
      expect(cntThis, 1, reason: '10-10 的工资应抬进 10-15 这一期');
      expect(incomeThis, 1000);

      final (_, incomePrev, cntPrev) = await Repo.rangeTotals(
        ledgerId,
        '2026-09-15',
        '2026-10-14',
      );
      expect(cntPrev, 0, reason: '不能被两期各算一次');
      expect(incomePrev, 0);
    });

    test('兼职不抬期，留在真实日期那一期', () async {
      await add(
        type: TxnType.income,
        date: '2026-10-10',
        categoryId: catParttime,
      );

      final (_, _, cntPrev) = await Repo.rangeTotals(
        ledgerId,
        '2026-09-15',
        '2026-10-14',
      );
      expect(cntPrev, 1);
    });

    test('列表条数 == 合计笔数（归属期错位的兜底断言）', () async {
      await add(type: TxnType.expense, date: '2026-10-20', categoryId: catFood);
      await add(
        type: TxnType.income,
        date: '2026-10-10',
        categoryId: catSalary,
      );
      await add(
        type: TxnType.expense,
        date: '2026-11-02',
        categoryId: catTraffic,
      );
      await add(
        type: TxnType.income,
        date: '2026-10-09',
        categoryId: catParttime,
      );

      const from = '2026-10-15';
      const to = '2026-11-14';
      final rows = await Repo.rangeListTxns(
        ledgerId: ledgerId,
        from: from,
        to: to,
        limit: 1000,
      );
      final (_, _, cnt) = await Repo.rangeTotals(ledgerId, from, to);

      expect(rows.length, cnt);
      expect(rows.length, 3, reason: '10-20 支出、10-10 工资(抬期)、11-02 支出');
    });

    test('趋势图按真实日期分组，但只统计本期', () async {
      await add(type: TxnType.expense, date: '2026-10-20', categoryId: catFood);
      await add(
        type: TxnType.income,
        date: '2026-10-10',
        categoryId: catSalary,
      );
      // 上一期的支出，不该出现
      await add(type: TxnType.expense, date: '2026-10-01', categoryId: catFood);

      final daily = await Repo.rangeDailyTotals(
        ledgerId,
        '2026-10-15',
        '2026-11-14',
      );
      final dates = daily.map((d) => d.$1).toList();
      expect(dates, [
        '2026-10-10',
        '2026-10-20',
      ], reason: '抬期的工资仍显示在真实日期 10-10 那根柱子上');
      expect(daily.first.$3, 1000, reason: '10-10 的收入');
    });

    test('分类饼图分项之和 == 合计（含负数交叉口径）', () async {
      await add(
        type: TxnType.expense,
        date: '2026-10-20',
        categoryId: catFood,
        cents: 3000,
      );
      await add(
        type: TxnType.expense,
        date: '2026-10-21',
        categoryId: catTraffic,
        cents: 1500,
      );
      // 收入的负数：按交叉口径要进支出侧
      await add(
        type: TxnType.income,
        date: '2026-10-22',
        categoryId: catParttime,
        cents: -500,
      );

      const from = '2026-10-15';
      const to = '2026-11-14';
      final (exp, _, _) = await Repo.rangeTotals(ledgerId, from, to);
      final stats = await Repo.rangeCategoryStats(
        ledgerId: ledgerId,
        from: from,
        to: to,
        type: TxnType.expense,
      );
      final sum = stats.fold<int>(0, (a, s) => a + s.totalCents);

      expect(sum, exp, reason: '饼图分项之和与合计必须同口径');
      expect(exp, 5000, reason: '3000 + 1500 + 500');
    });
  });

  group('账单日默认 1：旧按月方法与新区间方法等价', () {
    test('monthTotals == rangeTotals(月初, 月末)', () async {
      await add(type: TxnType.expense, date: '2026-10-01', categoryId: catFood);
      await add(type: TxnType.expense, date: '2026-10-31', categoryId: catFood);
      await add(
        type: TxnType.income,
        date: '2026-10-10',
        categoryId: catSalary,
      );
      await add(
        type: TxnType.income,
        date: '2026-11-01',
        categoryId: catSalary,
      );

      final legacy = await Repo.monthTotals(ledgerId, '2026-10');
      final ranged = await Repo.rangeTotals(
        ledgerId,
        '2026-10-01',
        '2026-10-31',
      );
      expect(legacy, ranged);
      expect(legacy.$3, 3, reason: '11-01 不在 10 月');
    });

    test('listTxns(month) == rangeListTxns(月初, 月末)', () async {
      await add(type: TxnType.expense, date: '2026-10-05', categoryId: catFood);
      await add(type: TxnType.expense, date: '2026-10-25', categoryId: catFood);

      final legacy = await Repo.listTxns(ledgerId: ledgerId, month: '2026-10');
      final ranged = await Repo.rangeListTxns(
        ledgerId: ledgerId,
        from: '2026-10-01',
        to: '2026-10-31',
      );
      expect(legacy.map((t) => t.id), ranged.map((t) => t.id));
    });

    test('dailyTotals(month) == rangeDailyTotals(月初, 月末)', () async {
      await add(type: TxnType.expense, date: '2026-10-05', categoryId: catFood);
      final legacy = await Repo.dailyTotals(ledgerId, '2026-10');
      final ranged = await Repo.rangeDailyTotals(
        ledgerId,
        '2026-10-01',
        '2026-10-31',
      );
      expect(legacy, ranged);
    });

    test('工资在账单日为 1 时不会被抬期（老用户行为零变化）', () async {
      await add(
        type: TxnType.income,
        date: '2026-10-10',
        categoryId: catSalary,
      );
      final totals = await Repo.monthTotals(ledgerId, '2026-10');
      expect(totals.$2, 1000);
      expect(totals.$3, 1);
    });
  });
}
