import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/stores/plan_store.dart';
import 'package:heita_ledger/stores/shell_store.dart';
import 'package:heita_ledger/ui/pages/stats/pie_chart.dart';
import 'package:heita_ledger/ui/pages/stats/stats_page.dart';
import 'package:heita_ledger/ui/widgets/amount_text.dart';
import 'package:heita_ledger/ui/widgets/swipe_flip.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 图表页：骨架态（I20）、下钻带区间、口径切换不动明细游标、账户资产。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  const LocalDate day = LocalDate(2026, 10, 10);

  Future<int> seedExpense(int cents, {int? categoryId, LocalDate? date}) async {
    final Txn t = await Repo.saveTxn(
      mkTxn(
        ledgerId: await currentLedger(),
        amountCents: cents,
        date: date ?? day,
        periodStart: const LocalDate(2026, 10, 1),
        categoryId: categoryId ?? await topCategoryId(),
        accountId: await defaultAccountId(),
      ),
      cycleStartDay: 1,
    );
    return t.id!;
  }

  /// 取支出一侧的前 N 个一级分类 id（不同分类才可能多出一个扇区）。
  Future<List<int>> topCategoryIds() async {
    final List<Category> all = await Repo.category.all(await currentLedger());
    return <int>[
      for (final Category c in all)
        if (c.isTop && c.type == TxnType.expense && c.id != null) c.id!,
    ];
  }

  Future<UiHarness> pumpStats(
    WidgetTester tester, {
    bool autoRefresh = true,
  }) async {
    final UiHarness h = UiHarness();
    await h.load();
    // 固定到 10 月这一期，否则「今天是几月」会让断言随日期漂
    await h.plan.bind(
      ledgerId: await currentLedger(),
      period: const Period(
        from: LocalDate(2026, 10, 1),
        to: LocalDate(2026, 10, 31),
      ),
      cycleStartDay: 1,
    );
    await h.plan.reload();
    await tester.pumpWidget(
      h.wrap(host(StatsPage(autoRefresh: autoRefresh))),
    );
    return h;
  }

  testWidgets('⑥ 没算过时是骨架：有 PieSkeleton、**没有**「本期还没有数据」', (
    WidgetTester tester,
  ) async {
    await seedExpense(3850);
    await pumpStats(tester, autoRefresh: false);
    await tester.pumpAndSettle();

    expect(find.byType(PieSkeleton), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
    expect(
      find.text('本期还没有数据'),
      findsNothing,
      reason: 'I20：首帧显示空态文案，用户会以为数据丢了',
    );
  });

  testWidgets('⑥ 算完之后出饼图（扇区数 = 有数据的一级分类数）', (
    WidgetTester tester,
  ) async {
    await seedExpense(3850);
    await seedExpense(1000, categoryId: await topCategoryId(type: TxnType.expense));
    await pumpStats(tester);
    await tester.pumpAndSettle();

    expect(find.byType(PieSkeleton), findsNothing);
    expect(find.byType(PieChart), findsOneWidget);
    final PieChart chart = tester.widget<PieChart>(find.byType(PieChart));
    expect(chart.slices.length, 1, reason: '同一一级分类下的两笔合成一个扇区');
  });

  testWidgets('⑥ 记账后只 pump 一帧：仍无空态、饼图还在；settle 后扇区 +1', (
    WidgetTester tester,
  ) async {
    await seedExpense(3850);
    final UiHarness h = await pumpStats(tester);
    await tester.pumpAndSettle();
    final int before = tester
        .widget<PieChart>(find.byType(PieChart))
        .slices
        .length;

    // 记一笔（换一个一级分类）→ 打脏标记 → 立刻回图表页
    final List<int> tops = await topCategoryIds();
    expect(tops.length, greaterThan(1), reason: '种子里有 9 个支出一级分类');
    await seedExpense(5000, categoryId: tops[1]);
    h.plan.markStatsStale();

    await tester.pump(); // 只一帧

    expect(
      find.text('本期还没有数据'),
      findsNothing,
      reason: '脏了但旧快照还有效 → 不许闪空态',
    );
    expect(find.byType(PieChart), findsOneWidget);
    expect(
      tester.widget<PieChart>(find.byType(PieChart)).slices.length,
      before,
      reason: '这一帧画的还是上一次的快照',
    );

    await tester.pumpAndSettle();
    expect(
      tester.widget<PieChart>(find.byType(PieChart)).slices.length,
      before + 1,
      reason: '重算完多了一个分类',
    );
  });

  testWidgets('空态文案只在算完并确认为空时出现', (WidgetTester tester) async {
    await pumpStats(tester);
    await tester.pumpAndSettle();

    expect(find.text('本期还没有数据'), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
  });

  testWidgets('② 支出 / 收入两档切换', (WidgetTester tester) async {
    await seedExpense(3850);
    await Repo.saveTxn(
      mkTxn(
        ledgerId: await currentLedger(),
        type: TxnType.income,
        amountCents: 900000,
        date: day,
        periodStart: const LocalDate(2026, 10, 1),
        categoryId: await topCategoryId(type: TxnType.income),
        accountId: await defaultAccountId(),
      ),
      cycleStartDay: 1,
    );
    await pumpStats(tester);
    await tester.pumpAndSettle();

    expect(find.text('38.50'), findsOneWidget, reason: '支出合计');

    await tester.tap(find.byKey(const ValueKey<String>('chip-收入')));
    await tester.pumpAndSettle();

    expect(find.text('9,000.00'), findsOneWidget, reason: '收入合计');
  });

  testWidgets('③ 点排行一行 → 切明细，带上分类 + **当前统计区间**', (
    WidgetTester tester,
  ) async {
    final int top = await topCategoryId();
    await seedExpense(3850, categoryId: top);
    final UiHarness h = await pumpStats(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey<String>('rank-$top')));
    await tester.pumpAndSettle();

    expect(h.shell.tabIndex, ShellStore.tabDetail);
    expect(h.book.query.categoryId, top);
    expect(
      h.book.query.from,
      const LocalDate(2026, 10, 1),
      reason: '不带区间 → 明细按「全部历史」算，数字对不上图表',
    );
    expect(h.book.query.to, const LocalDate(2026, 10, 31));
  });

  testWidgets('② 点某一天 → 切明细，dateFrom == dateTo == 那天', (
    WidgetTester tester,
  ) async {
    await seedExpense(3850);
    final UiHarness h = await pumpStats(tester);
    await tester.pumpAndSettle();

    final Rect box = tester.getRect(
      find.byKey(const ValueKey<String>('daily-bars')),
    );
    // 10 月 31 格里点第 10 天（(10-0.5)/31）
    await tester.tapAt(Offset(box.left + box.width * (9.5 / 31), box.center.dy));
    await tester.pumpAndSettle();

    expect(h.shell.tabIndex, ShellStore.tabDetail);
    expect(h.book.query.from, day);
    expect(h.book.query.to, day);
    expect(h.book.query.categoryId, isNull);
  });

  testWidgets('⑤ 口径切换 → 统计游标变，明细页的期一动不动', (
    WidgetTester tester,
  ) async {
    await seedExpense(3850);
    final UiHarness h = await pumpStats(tester);
    await tester.pumpAndSettle();
    final Period detailCycle = h.book.cycle;

    await tester.tap(find.byKey(const ValueKey<String>('chip-本月')));
    await tester.pumpAndSettle();

    expect(h.plan.statsScope, StatsScope.month);
    expect(h.book.cycle.from, detailCycle.from);
    expect(h.book.cycle.to, detailCycle.to);
  });

  testWidgets('区间条横滑 → 统计期变（明细页不变）', (WidgetTester tester) async {
    await seedExpense(3850);
    final UiHarness h = await pumpStats(tester);
    await tester.pumpAndSettle();

    // 用带时间戳的手势合成：tester.fling 在 FakeAsync 下速度恒 0
    final Offset c = tester.getCenter(find.byType(SwipeFlip));
    final TestGesture g = await tester.startGesture(c);
    await g.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(milliseconds: 8),
    );
    await g.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(milliseconds: 16),
    );
    await g.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(milliseconds: 24),
    );
    await g.up(timeStamp: const Duration(milliseconds: 32));
    await tester.pumpAndSettle();

    expect(h.plan.statsPeriod.from, const LocalDate(2026, 11, 1));
    expect(h.book.cycle.from, const LocalDate(2026, 10, 1));
  });

  testWidgets('⑦ 账户资产卡显示 Σ 计入净资产的余额', (WidgetTester tester) async {
    // 资产卡在页面最下面，默认 800×600 视口里还没被建出来
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seedExpense(3850);
    await pumpStats(tester);
    await tester.pumpAndSettle();

    final int expected = await Repo.stats.accountAssets();
    final AmountText card = tester.widget<AmountText>(
      find.byKey(const ValueKey<String>('net-assets')),
    );
    expect(card.cents, expected);
    expect(card.yuan, isTrue);
    expect(find.text('账户资产'), findsOneWidget);
  });

  testWidgets('读不到数据时不崩（空库整页仍可渲染）', (WidgetTester tester) async {
    await pumpStats(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
