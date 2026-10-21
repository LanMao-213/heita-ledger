import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/txn_query.dart';
import 'package:heita_ledger/ui/pages/detail/filter_sheet.dart';

import '../support/db_fixture.dart';
import '../support/ui_fixture.dart';

/// 筛选面板：六维度、金额交换、转账无分类、切类型清分类、时间档按真实日期。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<TxnQuery? Function()> open(
    WidgetTester tester,
    UiHarness h, {
    TxnQuery initial = const TxnQuery(),
  }) async {
    final _Holder holder = _Holder();
    await h.pump(
      tester,
      host(
        Builder(
          builder: (BuildContext ctx) => TextButton(
            onPressed: () async => holder.query = await showFilterSheet(
              ctx,
              initial: initial,
              cycleStartDay: 1,
            ),
            child: const Text('open-filter'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-filter'));
    await tester.pumpAndSettle();
    return () => holder.query;
  }

  testWidgets('① 六个维度都在（类型 / 分类 / 账户 / 金额区间 / 时间段）', (
    WidgetTester tester,
  ) async {
    final UiHarness h = UiHarness();
    await h.load();
    await open(tester, h);

    expect(find.text('类型'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('账户'), findsOneWidget);
    expect(find.text('金额区间（元）'), findsOneWidget);
    expect(find.text('时间段'), findsOneWidget);

    for (final String label in <String>['全部', '支出', '收入', '转账']) {
      expect(find.byKey(ValueKey<String>('chip-$label')), findsOneWidget);
    }
    for (final TimePreset p in TimePreset.values) {
      expect(find.byKey(ValueKey<String>('chip-${p.label}')), findsOneWidget);
    }
  });

  testWidgets('① 金额填反自动交换（最低 > 最高）', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    final TxnQuery? Function() result = await open(tester, h);

    await tester.enterText(find.byKey(const ValueKey<String>('filter-min')), '200');
    await tester.enterText(find.byKey(const ValueKey<String>('filter-max')), '50');
    await tester.tap(find.byKey(const ValueKey<String>('filter-apply')));
    await tester.pumpAndSettle();

    final TxnQuery q = result()!;
    expect(q.minCents, 5000);
    expect(q.maxCents, 20000);
  });

  testWidgets('① 转账时分类整块不渲染', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await open(tester, h);
    expect(find.text('分类'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('chip-转账')));
    await tester.pumpAndSettle();

    expect(find.text('分类'), findsNothing);
  });

  testWidgets('② 类型切到「不是支出」就清分类', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    final TxnQuery? Function() result = await open(
      tester,
      h,
      initial: const TxnQuery(categoryId: 1),
    );

    await tester.tap(find.byKey(const ValueKey<String>('chip-收入')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('filter-apply')));
    await tester.pumpAndSettle();

    expect(result()!.categoryId, isNull);
    expect(result()!.type, TxnType.income);
  });

  testWidgets('⑤ 时间快捷档按真实日期：本期 / 上期 / 近 3 期 / 今年', (
    WidgetTester tester,
  ) async {
    final UiHarness h = UiHarness();
    await h.load();
    final TxnQuery? Function() result = await open(tester, h);

    await tester.tap(find.byKey(const ValueKey<String>('chip-本期')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('filter-apply')));
    await tester.pumpAndSettle();

    final TxnQuery q = result()!;
    final ({LocalDate from, LocalDate to})? expected = rangeOfPreset(
      TimePreset.current,
      cycleStartDay: 1,
    );
    expect(q.from, expected!.from);
    expect(q.to, expected.to);
    expect(q.from!.day, 1, reason: '账单日 1 → 期首就是月初');
  });

  test('⑤ rangeOfPreset：不限为 null、近 3 期覆盖本期往前两期、今年是自然年', () {
    const LocalDate today = LocalDate(2026, 10, 16);

    expect(rangeOfPreset(TimePreset.any, cycleStartDay: 1), isNull);

    final r3 = rangeOfPreset(
      TimePreset.last3,
      cycleStartDay: 1,
      today: today,
    )!;
    expect(r3.from, const LocalDate(2026, 8, 1));
    expect(r3.to, const LocalDate(2026, 10, 31));

    final year = rangeOfPreset(
      TimePreset.thisYear,
      cycleStartDay: 1,
      today: today,
    )!;
    expect(year.from, const LocalDate(2026, 1, 1));
    expect(year.to, const LocalDate(2026, 12, 31));

    // 账单日 15：本期是 10-15..11-14，上期是 09-15..10-14
    final cur = rangeOfPreset(
      TimePreset.current,
      cycleStartDay: 15,
      today: today,
    )!;
    expect(cur.from, const LocalDate(2026, 10, 15));
    expect(cur.to, const LocalDate(2026, 11, 14));

    final last = rangeOfPreset(
      TimePreset.last,
      cycleStartDay: 15,
      today: today,
    )!;
    expect(last.from, const LocalDate(2026, 9, 15));
  });

  testWidgets('重置清空全部条件', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    final TxnQuery? Function() result = await open(
      tester,
      h,
      initial: const TxnQuery(type: TxnType.expense, minCents: 100),
    );

    await tester.tap(find.byKey(const ValueKey<String>('filter-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('filter-apply')));
    await tester.pumpAndSettle();

    final TxnQuery q = result()!;
    expect(q.isEmpty, isTrue);
  });

  testWidgets('⑦ 关闭面板 = 取消（返回 null，不改条件）', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    final TxnQuery? Function() result = await open(tester, h);

    await tester.tap(find.byKey(const ValueKey<String>('sheet-close')));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });
}

class _Holder {
  TxnQuery? query;
}
