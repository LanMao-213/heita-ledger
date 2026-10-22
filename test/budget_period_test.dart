// 预算按周期（v5）自检 —— F5 阶段 4 / D13 改口径。
//
// 这次改动动了「钱怎么归属」这件事，三种坑最难靠手点发现：
// 1) 老库升级时预算丢了或串期（一条 UPDATE 写错，用户月底才发现预算不对）；
// 2) 预算按自然月读、支出按周期算，两边错开半个月 → 进度条永远差一截；
// 3) 期长 28–31 天不固定，节奏却按 31 天摊 → 2 月那期必然算错「每天能花多少」。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/pacing.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_budget_period.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 造一个 v4 老库：`budget` 还是按 `month` 存。
Future<void> _makeV4Db() async {
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();

  final db = await databaseFactory.openDatabase(
    await _dbPath(),
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE budget (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id    INTEGER NOT NULL,
            month        TEXT    NOT NULL,
            category_id  INTEGER,
            amount_cents INTEGER NOT NULL DEFAULT 0,
            UNIQUE (ledger_id, month, category_id)
          )''');
        await db.insert('budget', {
          'ledger_id': 1,
          'month': '2026-10',
          'category_id': null,
          'amount_cents': 500000,
        });
        await db.insert('budget', {
          'ledger_id': 1,
          'month': '2026-10',
          'category_id': 7,
          'amount_cents': 120000,
        });
        await db.insert('budget', {
          'ledger_id': 1,
          'month': '2026-11',
          'category_id': null,
          'amount_cents': 480000,
        });
      },
    ),
  );
  await db.close();
}

void main() {
  late int ledgerId;
  late int catFood;

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
    catFood = expenses.firstWhere((c) => c.name == '餐饮').id;
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  group('v4 → v5 迁移', () {
    test('月份无损换算成归属期，金额与分类都保留', () async {
      await Db.close();
      await _makeV4Db();

      final db = await Db.open(); // 触发 onUpgrade
      final cols = await db.rawQuery('PRAGMA table_info(budget)');
      expect(
        cols.any((c) => c['name'] == 'period_start'),
        isTrue,
        reason: '没加 period_start 列',
      );
      expect(
        cols.any((c) => c['name'] == 'month'),
        isFalse,
        reason: '旧的 month 列应当已被重建表替换掉',
      );

      final rows = await db.query('budget', orderBy: 'id');
      expect(rows.length, 3, reason: '一条预算都不能丢');
      expect(rows[0]['period_start'], '2026-10-01');
      expect(rows[0]['amount_cents'], 500000);
      expect(rows[1]['period_start'], '2026-10-01');
      expect(rows[1]['category_id'], 7, reason: '分类预算要跟着走');
      expect(rows[2]['period_start'], '2026-11-01');
    });

    test('迁移可重复执行', () async {
      await Db.close();
      await _makeV4Db();
      await Db.open();
      await Db.close();
      await Db.open();
      final db = await Db.open();
      final rows = await db.query('budget');
      expect(rows.length, 3);
    });
  });

  group('按期读写预算', () {
    test('不同期互不影响', () async {
      await Repo.setBudget(
        ledgerId: ledgerId,
        periodStart: '2026-10-15',
        amountCents: 300000,
      );
      await Repo.setBudget(
        ledgerId: ledgerId,
        periodStart: '2026-09-15',
        amountCents: 250000,
      );

      expect(await Repo.totalBudgetCents(ledgerId, '2026-10-15'), 300000);
      expect(await Repo.totalBudgetCents(ledgerId, '2026-09-15'), 250000);
      expect(await Repo.totalBudgetCents(ledgerId, '2026-11-15'), isNull);
    });

    test('金额为 0 等于清除', () async {
      await Repo.setBudget(
        ledgerId: ledgerId,
        periodStart: '2026-10-15',
        amountCents: 100000,
      );
      await Repo.setBudget(
        ledgerId: ledgerId,
        periodStart: '2026-10-15',
        amountCents: 0,
      );
      expect(await Repo.totalBudgetCents(ledgerId, '2026-10-15'), isNull);
    });

    test('分类预算按归属期统计支出', () async {
      // 账单日 15：10-10 的支出属于 09-15 那一期
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.expense,
          amountCents: 40000,
          date: '2026-10-10',
          categoryId: catFood,
        ),
      );
      await Repo.setBudget(
        ledgerId: ledgerId,
        periodStart: '2026-10-15',
        categoryId: catFood,
        amountCents: 100000,
      );

      final inThisPeriod = await Repo.budgetStats(
        ledgerId: ledgerId,
        periodStart: '2026-10-15',
        from: '2026-10-15',
        to: '2026-11-14',
      );
      expect(
        inThisPeriod.single.spentCents,
        0,
        reason: '10-10 那笔不算在 10-15 起的这一期',
      );

      final inPrevPeriod = await Repo.budgetStats(
        ledgerId: ledgerId,
        periodStart: '2026-09-15',
        from: '2026-09-15',
        to: '2026-10-14',
      );
      expect(inPrevPeriod.single.spentCents, 40000);
    });
  });

  group('预算节奏按区间', () {
    test('2 月那期 28 天，不能按 31 天摊', () {
      final p = Pacing.ofRange(
        from: '2026-02-01',
        to: '2026-02-28',
        totalCents: 280000,
        usedCents: 0,
        today: '2026-02-01',
      );
      expect(p.totalDays, 28);
      expect(p.passedDays, 1);
      expect(p.remainDays, 28);
      expect(p.perDayBudgetCents, 10000);
    });

    test('跨月的期也能算（10-15 → 11-14 共 31 天）', () {
      final p = Pacing.ofRange(
        from: '2026-10-15',
        to: '2026-11-14',
        totalCents: 310000,
        usedCents: 100000,
        today: '2026-10-25', // 第 11 天
      );
      expect(p.totalDays, 31);
      expect(p.passedDays, 11);
      expect(p.remainDays, 21);
      expect(p.leftCents, 210000);
    });

    test('已经过完的期：finished，剩余天数为 0', () {
      final p = Pacing.ofRange(
        from: '2026-09-15',
        to: '2026-10-14',
        totalCents: 300000,
        usedCents: 120000,
        today: '2026-10-18',
      );
      expect(p.finished, isTrue);
      expect(p.remainDays, 0);
      expect(p.sentence, contains('已结束'));
    });
  });

  group('备份恢复兼容', () {
    test('v4 备份里的 month 行能恢复进新的 budget 表', () async {
      final counts = await Repo.replaceTables({
        'budget': [
          {
            'id': 1,
            'ledger_id': ledgerId,
            'month': '2026-10',
            'category_id': null,
            'amount_cents': 666000,
          },
        ],
      });
      expect(counts['budget'], 1);
      expect(await Repo.totalBudgetCents(ledgerId, '2026-10-01'), 666000);
    });
  });
}
