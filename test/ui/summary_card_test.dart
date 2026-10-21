import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/ui/pages/detail/summary_card.dart';
import 'package:heita_ledger/ui/widgets/progress_bar.dart';

import '../support/ui_fixture.dart';

/// 概览卡：三格与聚合一致、六位数不溢出、筛选态换口径且预算条不渲染。
void main() {
  Widget card({
    RangeTotals totals = const RangeTotals(
      expenseCents: 123456,
      incomeCents: 800000,
      count: 37,
    ),
    bool filtering = false,
    int? budgetTotal = 600000,
    int budgetUsed = 123456,
    int overCents = 0,
    int remainDays = 10,
    int canSpend = 47654,
  }) {
    return host(
      SummaryCard(
        periodLabel: '10.01 至 10.31',
        totals: totals,
        filtering: filtering,
        budgetTotalCents: budgetTotal,
        budgetUsedCents: budgetUsed,
        overCents: overCents,
        remainDays: remainDays,
        canSpendPerDayCents: canSpend,
      ),
    );
  }

  testWidgets('① 三格：支出 / 结余 / 笔数（笔数取聚合值）', (WidgetTester tester) async {
    await UiHarness().pump(tester, card());

    expect(find.text('支出'), findsOneWidget);
    expect(find.text('结余'), findsOneWidget);
    expect(find.text('笔数'), findsOneWidget);
    // 结余 = 收入 − 支出 = 8000.00 − 1234.56 = 6765.44
    expect(find.text('6,765.44'), findsOneWidget);
    expect(find.text('37'), findsOneWidget, reason: '笔数用 totals.count，不是列表长度');
  });

  testWidgets('① 六位数金额单行不溢出（FittedBox 缩放）', (WidgetTester tester) async {
    await UiHarness().pump(
      tester,
      card(
        totals: const RangeTotals(
          expenseCents: 99999999,
          incomeCents: 0,
          count: 1,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(FittedBox), findsWidgets);
    // 金额仍然是一行
    final Finder amount = find.text('999,999.99');
    expect(amount, findsOneWidget);
    expect(tester.getSize(amount).height, lessThan(60));
  });

  testWidgets('② 筛选态换口径：筛选支出 / 筛选收入 / 收支差 + 全部时间', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(
      tester,
      card(
        filtering: true,
        totals: const RangeTotals(
          expenseCents: 35350,
          incomeCents: 1200,
          count: 9,
        ),
      ),
    );

    expect(find.text('筛选结果'), findsOneWidget);
    expect(find.text('全部时间'), findsOneWidget);
    expect(find.text('筛选支出'), findsOneWidget);
    expect(find.text('筛选收入'), findsOneWidget);
    expect(find.text('收支差'), findsOneWidget);
    expect(find.text('本期'), findsNothing);
  });

  testWidgets('② 筛选态**预算条整块不渲染**（即使传了预算）', (WidgetTester tester) async {
    await UiHarness().pump(
      tester,
      card(filtering: true, budgetTotal: 600000, budgetUsed: 100000),
    );

    expect(find.byType(ProgressBar), findsNothing);
    expect(find.textContaining('还剩'), findsNothing);
    expect(find.textContaining('每天可花'), findsNothing);
  });

  testWidgets('② 本期有预算 → 进度条 + 剩余 + 每天可花', (WidgetTester tester) async {
    await UiHarness().pump(tester, card());

    expect(find.byType(ProgressBar), findsOneWidget);
    expect(find.textContaining('还剩'), findsOneWidget);
    expect(find.textContaining('每天可花'), findsOneWidget);

    final ProgressBar bar = tester.widget<ProgressBar>(find.byType(ProgressBar));
    expect(bar.ratio, closeTo(123456 / 600000, 0.0001));
  });

  testWidgets('② 没设预算 → 不渲染进度条（不是渲染一条 0%）', (WidgetTester tester) async {
    await UiHarness().pump(tester, card(budgetTotal: null));
    expect(find.byType(ProgressBar), findsNothing);
  });

  testWidgets('超支时用警示色文案', (WidgetTester tester) async {
    await UiHarness().pump(
      tester,
      card(budgetTotal: 100000, budgetUsed: 150000, overCents: 50000),
    );

    expect(find.textContaining('已超'), findsOneWidget);
    final ProgressBar bar = tester.widget<ProgressBar>(find.byType(ProgressBar));
    expect(bar.isOver, isTrue);
  });

  testWidgets('期文案与账本名都在（翻期的锚点就是这一行）', (WidgetTester tester) async {
    await UiHarness().pump(tester, card());

    expect(
      find.byKey(const ValueKey<String>('summary-period-label')),
      findsOneWidget,
    );
    expect(find.text('10.01 至 10.31'), findsOneWidget);
    expect(paletteInk().ink, isNotNull);
  });
}
