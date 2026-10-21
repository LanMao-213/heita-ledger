import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/data/repo/stats_repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 只读聚合：交叉归集一致、分类归到一级并取绝对值、执行计划不出现全表扫。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  final Period october = Period.cycleRange(const LocalDate(2026, 10, 16), 1);

  test('rangeTotals 与 TxnSum.bySide 同口径（六处一致的第一处）', () async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(mkTxn(ledgerId: ledger, amountCents: 3000), cycleStartDay: 1);
    await Repo.saveTxn(mkTxn(ledgerId: ledger, amountCents: -2000), cycleStartDay: 1);
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 8000, type: TxnType.income),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: -500, type: TxnType.income),
      cycleStartDay: 1,
    );

    final RangeTotals sql = await Repo.stats.rangeTotals(
      ledgerId: ledger,
      from: '2026-10-01',
      to: '2026-10-31',
    );
    final RangeTotals memory = TxnSum.totals(await Repo.txn.allOfLedger(ledger));

    expect(sql.expenseCents, 3500);
    expect(sql.incomeCents, 10000);
    expect(sql, memory, reason: 'SQL 侧与内存侧必须逐项相等');
  });

  test('periodTotals 按归属期筛（不是按 date）', () async {
    final int ledger = await currentLedger();
    // 10-16 的账，账单日 15 → 归属期是 10-15 那期
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, date: const LocalDate(2026, 10, 16)),
      cycleStartDay: 15,
    );
    // 10-10 的账 → 归属期是 09-15 那期
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 700, date: const LocalDate(2026, 10, 10)),
      cycleStartDay: 15,
    );

    final RangeTotals oct = await Repo.stats.periodTotals(
      ledgerId: ledger,
      period: Period.cycleRange(const LocalDate(2026, 10, 16), 15),
    );
    final RangeTotals sep = await Repo.stats.periodTotals(
      ledgerId: ledger,
      period: Period.cycleRange(const LocalDate(2026, 9, 20), 15),
    );
    final RangeTotals dec = await Repo.stats.periodTotals(
      ledgerId: ledger,
      period: Period.cycleRange(const LocalDate(2026, 12, 1), 15),
    );

    expect(oct.expenseCents, 1000);
    expect(sep.expenseCents, 700, reason: '10-10 落在 09-15 那期');
    expect(dec.expenseCents, 0);
  });

  test('categoryStats：归到一级、支出取绝对值、排除借贷、排除停用', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();
    final int child = await childCategoryId(top);

    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, categoryId: top),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 2000, categoryId: child),
      cycleStartDay: 1,
    );
    // 负数净额 → 取绝对值进饼图（否则会出现负扇区或消失）
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: -500, categoryId: top),
      cycleStartDay: 1,
    );
    // 借贷 → 不进分类统计
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 99999, categoryId: top, debtId: 1),
      cycleStartDay: 1,
    );

    final List<CategoryStat> stats = await Repo.stats.categoryStats(
      ledgerId: ledger,
      from: october.fromIso,
      to: october.toIso,
    );

    final CategoryStat row = stats.firstWhere((CategoryStat s) => s.categoryId == top);
    expect(row.cents, 3500, reason: '1000 + 2000 + |−500|，且不含借贷的 99999');
  });

  test('dailyTotals 按真实日期分组', () async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, date: const LocalDate(2026, 10, 16)),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 2000, date: const LocalDate(2026, 10, 16)),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 500, date: const LocalDate(2026, 10, 17)),
      cycleStartDay: 1,
    );

    final List<DailyTotal> daily = await Repo.stats.dailyTotals(
      ledgerId: ledger,
      from: '2026-10-01',
      to: '2026-10-31',
    );
    expect(daily.length, 2);
    expect(daily.first.date, '2026-10-16');
    expect(daily.first.expenseCents, 3000);
    expect(daily.last.expenseCents, 500);
  });

  test('accountAssets 只算 include_in_total', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, accountId: acc),
      cycleStartDay: 1,
    );
    final int hidden = await Repo.account.insert(
      const Account(name: '信用卡', openingCents: 99999, includeInTotal: false),
    );
    expect(hidden, greaterThan(0));

    expect(await Repo.stats.accountAssets(), -1000);
  });

  test('borrowedInBudget 只算「借入 + 计入预算 + 落在本期 + 未结清」', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();

    await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.in_,
        counterparty: '张三',
        amountCents: 100000,
        accountId: acc,
        date: const LocalDate(2026, 10, 5),
        countInBudget: true,
        createdAt: DateTime(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );

    expect(
      await Repo.stats.borrowedInBudget(ledgerId: ledger, period: october),
      100000,
    );
    // 换个期（9 月）就没了
    expect(
      await Repo.stats.borrowedInBudget(
        ledgerId: ledger,
        period: Period.cycleRange(const LocalDate(2026, 9, 16), 1),
      ),
      0,
    );
  });

  test('monthsWithData 给出有数据的月份', () async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 100, date: const LocalDate(2026, 8, 3)),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 100, date: const LocalDate(2026, 10, 3)),
      cycleStartDay: 1,
    );
    expect(await Repo.stats.monthsWithData(ledger), <String>['2026-08', '2026-10']);
  });

  test('执行计划：明细 keyset 查询不出现全表扫描', () async {
    final int ledger = await currentLedger();
    final List<String> plan = await Repo.stats.explain(
      'SELECT t.* FROM txn t '
      'WHERE t.ledger_id = ? AND t.period_start >= ? AND t.period_start <= ? '
      'ORDER BY t.date DESC, t.id DESC LIMIT 50',
      <Object?>[ledger, october.fromIso, october.toIso],
    );

    expect(plan, isNotEmpty);
    for (final String detail in plan) {
      expect(
        detail.trimLeft().startsWith('SCAN'),
        isFalse,
        reason: '高频查询走了全表扫：$detail',
      );
    }
  });

  test('执行计划：分类聚合走索引', () async {
    final List<String> plan = await Repo.stats.explain(
      'SELECT t.category_id, SUM(t.amount_cents) FROM txn t '
      'WHERE t.ledger_id = ? AND t.date >= ? AND t.date <= ? '
      'GROUP BY t.category_id',
      <Object?>[1, '2026-10-01', '2026-10-31'],
    );
    expect(plan.any((String d) => d.contains('idx_txn_ledger_date')), isTrue);
  });
}
