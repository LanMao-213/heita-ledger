import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/data/repo/stats_repo.dart';
import 'package:heita_ledger/stores/plan_store.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 统计刷新：脏标记、两个口径各自一份快照、翻期后旧值不冒充新值。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  const Period october = Period(
    from: LocalDate(2026, 10, 1),
    to: LocalDate(2026, 10, 31),
  );

  Future<PlanStore> bound() async {
    final PlanStore plan = PlanStore();
    await plan.bind(
      ledgerId: await currentLedger(),
      period: october,
      cycleStartDay: 1,
    );
    await plan.reload();
    return plan;
  }

  Future<void> addExpense(int cents, {LocalDate? date}) async {
    await Repo.saveTxn(
      mkTxn(
        ledgerId: await currentLedger(),
        amountCents: cents,
        date: date ?? const LocalDate(2026, 10, 10),
        periodStart: const LocalDate(2026, 10, 1),
        categoryId: await topCategoryId(),
        accountId: await defaultAccountId(),
      ),
      cycleStartDay: 1,
    );
  }

  test('⑥ 首次算完 loaded == true（之前是骨架）', () async {
    await addExpense(3850);
    final PlanStore plan = await bound();

    expect(plan.stats.loaded, isFalse, reason: '没算过就是骨架');
    expect(plan.statsStale, isTrue);

    await plan.refreshStats();

    expect(plan.stats.loaded, isTrue);
    expect(plan.statsStale, isFalse);
    expect(plan.stats.expenseCents, 3850);
    expect(plan.stats.expenseCats.length, 1);
  });

  test('⑥ 不脏就不重算（页面每次 build 都调也不会打库）', () async {
    await addExpense(1000);
    final PlanStore plan = await bound();
    await plan.refreshStats();
    final DateTime? first = plan.stats.computedAt;

    await addExpense(500); // 直接插库，**没有** markStatsStale
    await plan.refreshStats();

    expect(plan.stats.computedAt, first, reason: '没脏标记 → 这次不该动');
    expect(plan.stats.expenseCents, 1000);
  });

  test('⑥ 记账打脏标记 → 旧值还在（不显示空态），重算后数据变新', () async {
    await addExpense(1000);
    final PlanStore plan = await bound();
    await plan.refreshStats();

    await addExpense(2000);
    plan.markStatsStale();

    // 脏了但**快照还有效**：页面这时候要画上一次的图，而不是「本期还没有数据」
    expect(plan.statsStale, isTrue);
    expect(plan.stats.loaded, isTrue);
    expect(plan.stats.expenseCents, 1000);

    await plan.refreshStats();
    expect(plan.stats.expenseCents, 3000);
    expect(plan.stats.expenseCats.length, 1, reason: '还是同一个分类，扇区数不变');
  });

  test('⑤ 两个口径各存一份快照，切过去不会互相覆盖', () async {
    await addExpense(1000);
    final PlanStore plan = await bound();
    await plan.refreshStats();

    expect(plan.statsOf(StatsScope.cycle).loaded, isTrue);
    expect(plan.statsOf(StatsScope.month).loaded, isFalse);

    plan.switchStatsScope(StatsScope.month);
    expect(plan.stats.loaded, isFalse, reason: '「本月」这份还没算过');
    await plan.refreshStats();
    expect(plan.statsOf(StatsScope.month).loaded, isTrue);

    // 切回「本期」，那份快照原样还在
    plan.switchStatsScope(StatsScope.cycle);
    expect(plan.statsOf(StatsScope.cycle).loaded, isTrue);
    expect(plan.statsOf(StatsScope.cycle).expenseCents, 1000);
  });

  test('⑤ 口径切换不动计划页 / 明细页的期', () async {
    final PlanStore plan = await bound();
    final Period before = plan.period;

    plan.switchStatsScope(StatsScope.month);
    plan.flipStats(1);

    expect(plan.period.from, before.from);
    expect(plan.period.to, before.to);
    expect(plan.statsPeriod.from, isNot(before.from), reason: '统计自己的游标动了');
  });

  test('翻期后旧快照不冒充新区间（先骨架，别给错数字）', () async {
    await addExpense(1000);
    final PlanStore plan = await bound();
    await plan.refreshStats();
    expect(plan.stats.loaded, isTrue);

    plan.flipStats(-1); // 上一期

    expect(plan.stats.loaded, isFalse, reason: '区间变了 → 那份快照不算数');
    expect(plan.statsStale, isTrue);
    expect(plan.stats.period.from, const LocalDate(2026, 9, 1));
  });

  test('「本月」口径的区间是自然月（账单日 15 也一样）', () async {
    final PlanStore plan = PlanStore();
    await plan.bind(
      ledgerId: await currentLedger(),
      period: const Period(
        from: LocalDate(2026, 10, 15),
        to: LocalDate(2026, 11, 14),
      ),
      cycleStartDay: 15,
    );
    plan.switchStatsScope(StatsScope.month);

    final Period month = plan.statsPeriod;
    final LocalDate today = LocalDate.today();
    expect(month.from, LocalDate(today.year, today.month, 1));
    expect(month.dayCount, greaterThanOrEqualTo(28));
  });

  test('⑥ 快照自带 6 段趋势与逐日补齐', () async {
    await addExpense(1000);
    final PlanStore plan = await bound();
    await plan.refreshStats();

    expect(plan.stats.trend.length, 6);
    expect(plan.stats.trend.last.period.from, october.from);
    expect(plan.stats.daily.length, october.dayCount);
    expect(
      plan.stats.daily
          .where((DailyTotal d) => d.expenseCents > 0)
          .length,
      1,
    );
  });

  test('⑦ 账户资产 = Σ balance(include_in_total = 1)', () async {
    final int acc = await defaultAccountId();
    await addExpense(1000);
    final PlanStore plan = await bound();
    await plan.refreshStats();

    final int fromSql = await Repo.stats.accountAssets();
    expect(plan.stats.accountAssetsCents, fromSql);
    expect(fromSql, await balanceOf(acc), reason: '只有现金一个账户计入');
  });

  test('markStatsStale 只打标记，不查库也不算', () async {
    final PlanStore plan = await bound();
    plan.markStatsStale();
    expect(plan.stats.loaded, isFalse, reason: '打标记不等于算过');
    expect(plan.stats.computedAt, isNull);
    // 关掉数据库也不会炸：说明它真的没碰 IO
    await Db.close();
    plan.markStatsStale();
  });
}
