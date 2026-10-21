import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/services/pacing_service.dart';
import 'package:heita_ledger/ui/pages/plan/budget_card.dart';
import 'package:heita_ledger/ui/widgets/amount_text.dart';

import '../support/ui_fixture.dart';

/// 预算卡：可用额度（含借入）、额度本身不变、节奏四态、整除、边界期。
void main() {
  const Period october = Period(
    from: LocalDate(2026, 10, 1),
    to: LocalDate(2026, 10, 31),
  );

  Widget card({
    int? total,
    int used = 0,
    int borrowed = 0,
    Period period = october,
    LocalDate? today,
  }) {
    return host(
      BudgetCard(
        stats: BudgetStats(
          totalBudgetCents: total,
          usedCents: used,
          borrowedInBudgetCents: borrowed,
        ),
        period: period,
        today: today ?? const LocalDate(2026, 10, 16),
        onEdit: () {},
      ),
    );
  }

  test('① 没有预算 → 「未设预算」（不是「额度 0」）', () {
    expect(budgetCaptionOf(totalCents: null, borrowedCents: 0), '未设');
    expect(budgetCaptionOf(totalCents: null, borrowedCents: 3000), '未设');
  });

  test('② 小字：额度 6,000.00（含借入 3,000.00）', () {
    expect(
      budgetCaptionOf(totalCents: 600000, borrowedCents: 300000),
      '额度 6,000.00（含借入 3,000.00）',
    );
    expect(
      budgetCaptionOf(totalCents: 600000, borrowedCents: 0),
      '额度 6,000.00',
      reason: '没有借入时不必写「含借入 0.00」',
    );
  });

  test('② 可用额度 = 额度 + 借入', () {
    expect(
      budgetAvailableOf(
        const BudgetStats(
          totalBudgetCents: 600000,
          usedCents: 0,
          borrowedInBudgetCents: 300000,
        ),
      ),
      900000,
    );
  });

  testWidgets('① 没预算时卡片显示「未设预算」且不画假的 0% 进度', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(tester, card());
    expect(
      find.byKey(const ValueKey<String>('budget-unset')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('budget-available')), findsNothing);
    expect(find.text('未设预算'), findsOneWidget);
  });

  testWidgets('② 大数字是可用额度（额度 + 借入），额度本身不变', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(
      tester,
      card(total: 600000, used: 200000, borrowed: 300000),
    );

    final AmountText big = tester.widget<AmountText>(
      find.byKey(const ValueKey<String>('budget-available')),
    );
    expect(big.cents, 900000, reason: '6,000 + 借入 3,000');
    expect(
      find.text('额度 6,000.00（含借入 3,000.00）'),
      findsOneWidget,
      reason: '额度本身还是 6,000，借入只是抬可用',
    );
  });

  testWidgets('② 进度 / 剩余 / 每天可花全走可用额度', (WidgetTester tester) async {
    await UiHarness().pump(
      tester,
      card(total: 600000, used: 200000, borrowed: 300000),
    );

    final AmountText left = tester.widget<AmountText>(
      find.byKey(const ValueKey<String>('budget-left')),
    );
    // 可用 9000 − 已花 2000 = 7000
    expect(left.cents, 700000);
    expect(
      left.cents,
      isNot(400000),
      reason: '拿额度算会得到 4000 —— 那正是「借入一开就全错」的那个错',
    );

    final Pacing pacing = Pacing.ofRange(
      period: october,
      totalCents: 900000,
      usedCents: 200000,
      today: const LocalDate(2026, 10, 16),
    );
    final AmountText perDay = tester.widget<AmountText>(
      find.byKey(const ValueKey<String>('budget-per-day')),
    );
    expect(perDay.cents, pacing.canSpendPerDayCents);
  });

  test('③ 每天可花是**整除**（不四舍五入，否则月底必超）', () {
    // 剩 16 天（10-16..10-31），剩 10000 分 → 625 分/天
    final Pacing p = Pacing.ofRange(
      period: october,
      totalCents: 10000,
      usedCents: 0,
      today: const LocalDate(2026, 10, 16),
    );
    expect(p.remainDays, 16);
    expect(p.canSpendPerDayCents, 625);
    expect(10000 / 16, closeTo(625.0, 1e-9));

    // 除不尽时向下取整：剩 3 天、剩 100 分 → 33 不是 34
    final Pacing p2 = Pacing.ofRange(
      period: october,
      totalCents: 100,
      usedCents: 0,
      today: const LocalDate(2026, 10, 29),
    );
    expect(p2.remainDays, 3);
    expect(p2.canSpendPerDayCents, 33);
  });

  test('③ 期已结束 → remainDays = 0（剩的钱按 1 天算，不除零）', () {
    final Pacing p = Pacing.ofRange(
      period: october,
      totalCents: 100000,
      usedCents: 40000,
      today: const LocalDate(2026, 11, 3),
    );
    expect(p.finished, isTrue);
    expect(p.remainDays, 0);
    expect(p.passedDays, p.totalDays);
    // 口径（阶段 1 定的）：remainDays == 0 时按 1 天算 —— 剩多少就是多少，
    // 不是除以 0 得到 Infinity，也不是抹成 0
    expect(p.canSpendPerDayCents, 60000);
    expect(p.sentence, contains('已结束'));
  });

  test('③ 期还没开始 → passedDays = 0、整期都还可用', () {
    final Pacing p = Pacing.ofRange(
      period: october,
      totalCents: 310000,
      usedCents: 0,
      today: const LocalDate(2026, 9, 20),
    );
    expect(p.passedDays, 0);
    expect(p.remainDays, p.totalDays);
    expect(p.perDayRealCents, 0, reason: '还没开始，不除以 0');
    expect(p.canSpendPerDayCents, 10000);
  });

  test('③ 四种状态文案各说各的话', () {
    final String noBudget = Pacing.ofRange(
      period: october,
      totalCents: null,
      usedCents: 0,
      today: const LocalDate(2026, 10, 16),
    ).sentence;
    expect(noBudget, contains('还没设预算'));

    final String over = Pacing.ofRange(
      period: october,
      totalCents: 10000,
      usedCents: 20000,
      today: const LocalDate(2026, 10, 16),
    ).sentence;
    expect(over, contains('已经超支'));

    final String normal = Pacing.ofRange(
      period: october,
      totalCents: 100000,
      usedCents: 1000,
      today: const LocalDate(2026, 10, 16),
    ).sentence;
    expect(normal, contains('节奏正常'));

    final String finished = Pacing.ofRange(
      period: october,
      totalCents: 100000,
      usedCents: 1000,
      today: const LocalDate(2026, 11, 20),
    ).sentence;
    expect(finished, contains('已结束'));
  });

  testWidgets('超支时「剩余」用警示色', (WidgetTester tester) async {
    await UiHarness().pump(tester, card(total: 100000, used: 150000));

    final AmountText left = tester.widget<AmountText>(
      find.byKey(const ValueKey<String>('budget-left')),
    );
    expect(left.cents, -50000);
    expect(left.color, isNotNull);
    expect(find.byKey(const ValueKey<String>('budget-sentence')), findsOneWidget);
  });
}
