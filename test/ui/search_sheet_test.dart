import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/ui/pages/detail/search_sheet.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 搜索面板：提示文案、金额规则、结果标题、取消语义。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<String? Function()> open(WidgetTester tester, UiHarness h) async {
    final _Holder holder = _Holder();
    await h.pump(
      tester,
      host(
        Builder(
          builder: (BuildContext ctx) => TextButton(
            onPressed: () async => holder.keyword = await showSearchSheet(
              ctx,
              ledgerId: h.book.ledgerId,
              categoryOf: h.catalog.displayName,
              accountOf: h.catalog.accountName,
            ),
            child: const Text('open-search'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-search'));
    await tester.pumpAndSettle();
    return () => holder.keyword;
  }

  testWidgets('⑥ 提示文案「备注、分类、账户、金额」', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await open(tester, h);

    expect(find.text('备注、分类、账户、金额'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('search-input')), findsOneWidget);
  });

  testWidgets('⑥ 一条记录都搜不到时标题是 0 条', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await open(tester, h);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '不存在的词',
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索「不存在的词」 · 0 条'), findsOneWidget);
  });

  testWidgets('⑥ 一位数不参与金额匹配（搜「5」不该命中全部）', (
    WidgetTester tester,
  ) async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 500, note: '早饭'),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 12345, note: '晚饭'),
      cycleStartDay: 1,
    );

    final UiHarness h = UiHarness();
    await h.load();
    await open(tester, h);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '5',
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索「5」 · 0 条'), findsOneWidget);
  });

  testWidgets('⑥ 「38.5」命中 38.50 / 138.50 / 3.85 三笔', (
    WidgetTester tester,
  ) async {
    final int ledger = await currentLedger();
    for (final int cents in <int>[3850, 13850, 385, 9999]) {
      await Repo.saveTxn(
        mkTxn(ledgerId: ledger, amountCents: cents, note: 'n$cents'),
        cycleStartDay: 1,
      );
    }

    final UiHarness h = UiHarness();
    await h.load();
    await open(tester, h);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '38.5',
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索「38.5」 · 3 条'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
  });

  testWidgets('⑥ 搜分类名与账户名都能命中', (WidgetTester tester) async {
    final int ledger = await currentLedger();
    final int acc = await Repo.account.insert(const Account(name: '招商银行'));
    final int cat = await topCategoryId();
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 100,
        accountId: acc,
        categoryId: cat,
      ),
      cycleStartDay: 1,
    );

    final UiHarness h = UiHarness();
    await h.load();
    await open(tester, h);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '招商',
    );
    await tester.pumpAndSettle();
    expect(find.text('搜索「招商」 · 1 条'), findsOneWidget);
  });

  testWidgets('⑥ 点结果 / 查看 都把关键词交回外层', (WidgetTester tester) async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 3850, note: '午饭'),
      cycleStartDay: 1,
    );

    final UiHarness h = UiHarness();
    await h.load();
    final String? Function() result = await open(tester, h);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '午饭',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('search-apply')));
    await tester.pumpAndSettle();

    expect(result(), '午饭');
  });

  testWidgets('⑦ 取消（关闭面板）不改条件，返回 null', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    final String? Function() result = await open(tester, h);

    await tester.tap(find.byKey(const ValueKey<String>('sheet-close')));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });

  test('⑥ 结果标题：带「+」表示被截断', () {
    expect(searchResultTitle('38.5', 3), '搜索「38.5」 · 3 条');
    expect(
      searchResultTitle(' 午饭 ', 500, truncated: true),
      '搜索「午饭」 · 500+ 条',
    );
    expect(searchDateLabel(const LocalDate(2026, 10, 6)), '10-06');
  });
}

class _Holder {
  String? keyword;
}
