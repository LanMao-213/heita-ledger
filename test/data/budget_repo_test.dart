import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 预算 repo：额度 vs 可用额度的区别 + **I15 改账单日后合并相加**。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  test('没设预算 → null（不是 0）；设了 0 → 删行（仍为 null）', () async {
    final int ledger = await currentLedger();
    final LocalDate period = const LocalDate(2026, 10, 1);

    expect(await Repo.budget.totalBudget(ledger, period), isNull);

    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: period,
      amountCents: 0,
    );
    expect(await Repo.budget.totalBudget(ledger, period), isNull);

    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: period,
      amountCents: 600000,
    );
    expect(await Repo.budget.totalBudget(ledger, period), 600000);

    // 覆盖写
    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: period,
      amountCents: 700000,
    );
    expect(await Repo.budget.totalBudget(ledger, period), 700000);

    // 清空
    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: period,
      amountCents: -1,
    );
    expect(await Repo.budget.totalBudget(ledger, period), isNull);
  });

  test('分类预算：<=0 删行，>0 覆盖', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final int top = await topCategoryId();
    final LocalDate period = const LocalDate(2026, 10, 1);

    await Repo.budget.setCategoryBudget(
      ledgerId: ledger,
      periodStart: period,
      categoryId: top,
      amountCents: 100000,
    );
    await Repo.budget.setCategoryBudget(
      ledgerId: ledger,
      periodStart: period,
      categoryId: top,
      amountCents: 120000,
    );
    List<Budget> rows = await Repo.budget.categoryBudgets(ledger, period);
    expect(rows.length, 1);
    expect(rows.single.amountCents, 120000);

    await Repo.budget.setCategoryBudget(
      ledgerId: ledger,
      periodStart: period,
      categoryId: top,
      amountCents: 0,
    );
    rows = await Repo.budget.categoryBudgets(ledger, period);
    expect(rows, isEmpty);
    expect(acc, greaterThan(0));
  });

  test('stats：可用额度 = 额度 + 本期借入，已用来自当期支出侧', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final Period cycle = Period.cycleRange(const LocalDate(2026, 10, 16), 1);

    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: cycle.from,
      amountCents: 600000,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 100000, accountId: acc),
      cycleStartDay: 1,
    );
    await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.in_,
        counterparty: '李四',
        amountCents: 50000,
        accountId: acc,
        date: const LocalDate(2026, 10, 16),
        countInBudget: true,
        createdAt: DateTime(2026, 10, 16),
      ),
      cycleStartDay: 1,
    );

    final BudgetStats stats = await Repo.budget.stats(
      ledgerId: ledger,
      period: cycle,
    );

    expect(stats.totalBudgetCents, 600000);
    expect(stats.usedCents, 100000, reason: '借入的 500 不算已用');
    expect(stats.borrowedInBudgetCents, 50000);
    expect(stats.availableCents, 650000);
    expect(stats.leftCents, 550000);
    expect(stats.overBudget, isFalse);
  });

  test('spentByCategory：一级分类的「已花」含所有子分类，且不含借贷', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();
    final int child = await childCategoryId(top);
    final Period cycle = Period.cycleRange(const LocalDate(2026, 10, 16), 1);

    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, categoryId: top),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 2000, categoryId: child),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 50000, categoryId: child, debtId: 9),
      cycleStartDay: 1,
    );

    final Map<int, int> spent = await Repo.budget.spentByCategory(
      ledgerId: ledger,
      period: cycle,
      topCategoryIds: <int>[top],
    );
    expect(spent[top], 3000, reason: '子分类的 2000 要算进一级，借贷的 500 不算');
  });

  test('I15：改账单日后两条旧期预算挤进一期 → 金额相加（不是覆盖）', () async {
    final int ledger = await currentLedger();

    // 两次改账单日留下的痕迹：这两行的期首（10-20 / 11-01）在「账单日 15」下
    // 都落进 10-15 那期 —— 正是「两条挤进一期」的真实形态。
    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: const LocalDate(2026, 10, 20),
      amountCents: 60000,
    );
    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: const LocalDate(2026, 11, 1),
      amountCents: 90000,
    );

    final int moved = await Repo.budget.remapBudgetPeriods(
      ledgerId: ledger,
      newCycleStartDay: 15,
    );

    expect(moved, 2);
    expect(
      await Repo.budget.totalBudget(ledger, const LocalDate(2026, 10, 15)),
      150000,
      reason: '600 + 900 = 1500 元，相加而不是覆盖',
    );
    expect(await Repo.budget.totalBudget(ledger, const LocalDate(2026, 10, 20)), isNull);
    expect(await Repo.budget.totalBudget(ledger, const LocalDate(2026, 11, 1)), isNull);
  });

  test('I15 分类预算同样合并相加，且总预算与分类预算不互相干扰', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();

    await Repo.budget.setCategoryBudget(
      ledgerId: ledger,
      periodStart: const LocalDate(2026, 10, 20),
      categoryId: top,
      amountCents: 10000,
    );
    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: const LocalDate(2026, 10, 20),
      amountCents: 50000,
    );
    await Repo.budget.setCategoryBudget(
      ledgerId: ledger,
      periodStart: const LocalDate(2026, 11, 1),
      categoryId: top,
      amountCents: 20000,
    );

    await Repo.budget.remapBudgetPeriods(ledgerId: ledger, newCycleStartDay: 15);

    expect(
      await Repo.budget.totalBudget(ledger, const LocalDate(2026, 10, 15)),
      50000,
    );
    final List<Budget> cats = await Repo.budget.categoryBudgets(
      ledger,
      const LocalDate(2026, 10, 15),
    );
    expect(cats.single.amountCents, 30000);
  });

  test('改账单日时已经在正确期的预算不动', () async {
    final int ledger = await currentLedger();
    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: const LocalDate(2026, 10, 15),
      amountCents: 60000,
    );
    final int moved = await Repo.budget.remapBudgetPeriods(
      ledgerId: ledger,
      newCycleStartDay: 15,
    );
    expect(moved, 0);
  });
}
