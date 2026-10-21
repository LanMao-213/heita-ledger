import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/stores/plan_store.dart';
import 'package:heita_ledger/ui/pages/plan/plan_page.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 计划页：周期条翻期重算、往来摘要 / 引导行、分类预算、储蓄目标、不跟统计口径。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  const Period october = Period(
    from: LocalDate(2026, 10, 1),
    to: LocalDate(2026, 10, 31),
  );

  Future<UiHarness> pumpPlan(WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await h.plan.bind(
      ledgerId: await currentLedger(),
      period: october,
      cycleStartDay: 1,
    );
    await h.plan.reload();
    // 页面挺长，给个高视口，免得下面的卡片根本没建出来
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.wrap(host(const PlanPage())));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('⑥ 没有借贷时顶部退化成一行引导文案（不占整张卡）', (
    WidgetTester tester,
  ) async {
    await pumpPlan(tester);

    expect(
      find.byKey(const ValueKey<String>('debt-guide')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('debt-receivable')), findsNothing);
    expect(find.byKey(const ValueKey<String>('debt-payable')), findsNothing);
  });

  testWidgets('有借贷 → 摘要卡给出应收 / 应付 / 本期到期', (
    WidgetTester tester,
  ) async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: 50000,
        accountId: acc,
        date: const LocalDate(2026, 10, 5),
        dueDate: const LocalDate(2026, 10, 20),
        createdAt: DateTime(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );
    await pumpPlan(tester);

    expect(find.byKey(const ValueKey<String>('debt-guide')), findsNothing);
    expect(find.byKey(const ValueKey<String>('debt-receivable')), findsOneWidget);
    expect(find.text('1 笔'), findsOneWidget, reason: '10-20 落在本期');
  });

  testWidgets('⑦ 周期条左滑 → 翻到下一期，预算与到期数全部重算', (
    WidgetTester tester,
  ) async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: october.from,
      amountCents: 600000,
    );
    await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.out,
        counterparty: '李四',
        amountCents: 30000,
        accountId: acc,
        date: const LocalDate(2026, 10, 5),
        dueDate: const LocalDate(2026, 10, 25),
        createdAt: DateTime(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );
    final UiHarness h = await pumpPlan(tester);
    expect(find.byKey(const ValueKey<String>('budget-available')), findsOneWidget);
    expect(find.text('1 笔'), findsOneWidget);

    // 左滑 = 下一期（用带时间戳的手势：fling 在 FakeAsync 下速度恒 0）
    final Offset c = tester.getCenter(find.byKey(const ValueKey<String>('plan-period')));
    final TestGesture g = await tester.startGesture(c);
    await g.moveBy(const Offset(-30, 0), timeStamp: const Duration(milliseconds: 8));
    await g.moveBy(const Offset(-30, 0), timeStamp: const Duration(milliseconds: 16));
    await g.up(timeStamp: const Duration(milliseconds: 24));
    await tester.pumpAndSettle();

    expect(h.plan.period.from, const LocalDate(2026, 11, 1));
    expect(find.byKey(const ValueKey<String>('budget-unset')), findsOneWidget);
    expect(find.text('0 笔'), findsOneWidget, reason: '11 月没有到期的往来');
  });

  testWidgets('⑧ 切图表的「本月」口径，计划页的期一动不动', (
    WidgetTester tester,
  ) async {
    final UiHarness h = await pumpPlan(tester);
    final Period before = h.plan.period;

    h.plan.switchStatsScope(StatsScope.month);
    h.plan.flipStats(1);
    await tester.pumpAndSettle();

    expect(h.plan.period.from, before.from);
    expect(h.plan.period.to, before.to);
    expect(
      find.byKey(const ValueKey<String>('plan-period')),
      findsOneWidget,
    );
  });

  testWidgets('分类预算列表：有支出就有一行（哪怕没设限额）', (
    WidgetTester tester,
  ) async {
    await Repo.saveTxn(
      mkTxn(
        ledgerId: await currentLedger(),
        amountCents: 3850,
        date: const LocalDate(2026, 10, 10),
        periodStart: october.from,
        categoryId: await topCategoryId(),
        accountId: await defaultAccountId(),
      ),
      cycleStartDay: 1,
    );
    await pumpPlan(tester);

    // 「未设」在这一页出现两处：预算卡的小字 + 分类预算那一行
    expect(find.text('未设'), findsNWidgets(2));
    expect(find.text('分类预算'), findsOneWidget);
  });

  testWidgets('储蓄目标空态：一句人话 + 新建按钮', (WidgetTester tester) async {
    await pumpPlan(tester);

    expect(find.byKey(const ValueKey<String>('goal-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('goal-new')), findsOneWidget);
  });

  testWidgets('新建储蓄目标：填名字和金额 → 卡片出现', (WidgetTester tester) async {
    final UiHarness h = await pumpPlan(tester);

    await tester.tap(find.byKey(const ValueKey<String>('goal-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal-name')),
      '换手机',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal-target')),
      '5000',
    );
    await tester.tap(find.byKey(const ValueKey<String>('goal-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('goal-empty')), findsNothing);
    expect(find.text('换手机'), findsOneWidget);
    expect(h.catalog.goals.length, 1);
    expect(h.catalog.goals.single.targetCents, 500000);
  });

  testWidgets('设本期总预算：存进归属期，卡上出现可用额度', (
    WidgetTester tester,
  ) async {
    final UiHarness h = await pumpPlan(tester);

    await tester.tap(find.byKey(const ValueKey<String>('budget-unset')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('budget-amount')),
      '6000',
    );
    await tester.tap(find.byKey(const ValueKey<String>('budget-save')));
    await tester.pumpAndSettle();

    expect(h.plan.budget.totalBudgetCents, 600000);
    expect(find.byKey(const ValueKey<String>('budget-available')), findsOneWidget);
    expect(
      await Repo.budget.totalBudget(await currentLedger(), october.from),
      600000,
      reason: '预算按**归属期**存',
    );
  });

  testWidgets('预算填 0 → 删行（不是留一条 0）', (WidgetTester tester) async {
    final UiHarness h = await pumpPlan(tester);
    await Repo.budget.setTotalBudget(
      ledgerId: await currentLedger(),
      periodStart: october.from,
      amountCents: 600000,
    );
    await h.plan.reload();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('budget-available')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('budget-amount')),
      '0',
    );
    await tester.tap(find.byKey(const ValueKey<String>('budget-save')));
    await tester.pumpAndSettle();

    expect(h.plan.budget.totalBudgetCents, isNull);
    expect(
      await Repo.budget.totalBudget(await currentLedger(), october.from),
      isNull,
    );
  });
}
