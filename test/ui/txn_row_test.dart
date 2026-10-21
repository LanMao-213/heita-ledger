import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/ui/pages/detail/txn_row.dart';

import '../support/ui_fixture.dart';

/// 明细行：标题/副行规则、借贷行中性灰与路由、周期标签、删除确认文案。
void main() {
  Txn tx({
    TxnType type = TxnType.expense,
    int cents = 3850,
    int? debtId,
    int? recurringId,
    String note = '',
    String? person,
    String? placeFrom,
    String? placeTo,
    String? subject,
  }) => Txn(
    id: 1,
    type: type,
    amountCents: cents,
    date: const LocalDate(2026, 10, 16),
    periodStart: const LocalDate(2026, 10, 1),
    note: note,
    person: person,
    placeFrom: placeFrom,
    placeTo: placeTo,
    subject: subject,
    debtId: debtId,
    recurringId: recurringId,
    createdAt: DateTime(2026, 10, 16, 9),
  );

  Widget row(Txn t, {String category = '餐饮 · 正餐', VoidCallback? onTap}) {
    return host(
      TxnRow(
        txn: t,
        categoryLabel: category,
        accountLabel: '现金',
        debtLabel: t.debtId == null ? null : '借出 · 张三',
        dueLabel: t.debtId == null ? null : '应还 11-30',
        onTap: onTap,
      ),
    );
  }

  testWidgets('⑤ 普通行标题恒为分类名', (WidgetTester tester) async {
    await UiHarness().pump(tester, row(tx()));
    expect(find.text('餐饮 · 正餐'), findsOneWidget);
  });

  testWidgets('⑤ 副行按序拼接：账户 · 详情 · 备注，单行 ellipsis', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(
      tester,
      row(
        tx(
          person: '张三',
          placeFrom: '家',
          placeTo: '公司',
          subject: '会计',
          note: '报销',
        ),
      ),
    );

    final String expected = '现金 · 张三 · 家 → 公司 · 会计 · 报销';
    expect(find.text(expected), findsOneWidget);
    final Text subtitle = tester.widget<Text>(find.text(expected));
    expect(subtitle.maxLines, 1);
    expect(subtitle.overflow, TextOverflow.ellipsis);
  });

  testWidgets('⑤ recurringId 非空 → 挂「周期」小标签', (WidgetTester tester) async {
    await UiHarness().pump(tester, row(tx(recurringId: 7)));

    expect(
      find.byKey(const ValueKey<String>('txn-badge-recurring')),
      findsOneWidget,
    );
    expect(find.text('周期'), findsOneWidget);
  });

  testWidgets('⑤ 非周期流水没有标签', (WidgetTester tester) async {
    await UiHarness().pump(tester, row(tx()));
    expect(find.byKey(const ValueKey<String>('txn-badge-recurring')), findsNothing);
  });

  testWidgets('④ 借贷行标题「借出 · 张三」，副行首位是应还日', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(tester, row(tx(debtId: 3, cents: 50000)));

    expect(find.text('借出 · 张三'), findsOneWidget);
    final String subtitle = '应还 11-30';
    expect(find.text(subtitle), findsOneWidget);
  });

  testWidgets('④ 借贷金额用中性灰 ink3（不是 over 也不是 ink）', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(tester, row(tx(debtId: 3, cents: 50000)));

    final Text amount = tester.widget<Text>(find.text('-500.00'));
    expect(amount.style?.color, paletteInk().ink3);
    expect(amount.style?.color, isNot(paletteInk().ink));
    expect(amount.style?.color, isNot(paletteInk().over));
  });

  testWidgets('④ 普通支出金额是 ink（黑色）', (WidgetTester tester) async {
    await UiHarness().pump(tester, row(tx()));
    final Text amount = tester.widget<Text>(find.text('-38.50'));
    expect(amount.style?.color, paletteInk().ink);
  });

  testWidgets('④ 点击回调由调用方决定（借贷行会被路由到往来详情）', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await UiHarness().pump(
      tester,
      row(tx(debtId: 3, cents: 50000), onTap: () => taps++),
    );
    await tester.tap(find.byType(TxnRow));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('行高按 60 的下限铺开（触控目标够大）', (WidgetTester tester) async {
    await UiHarness().pump(tester, row(tx()));
    final Size size = tester.getSize(find.byType(TxnRow));
    expect(size.height, greaterThanOrEqualTo(60));
  });

  test('⑩ 删除确认文案：「分类名 · ±金额」+ 备注换行', () {
    final Txn t = tx(cents: 3850, note: '和同事');
    expect(
      deleteConfirmBody(t, categoryLabel: '餐饮 · 正餐'),
      '餐饮 · 正餐 · -¥38.50\n和同事',
    );
    // 收入是 +
    expect(
      deleteConfirmBody(
        tx(type: TxnType.income, cents: 800000),
        categoryLabel: '工资 · 月薪',
      ),
      '工资 · 月薪 · +¥8000.00',
    );
    // 未分类
    expect(
      deleteConfirmBody(tx(), categoryLabel: ''),
      '未分类 · -¥38.50',
    );
  });

  test('⑧ 末尾状态行：已显示 N / 共 M', () {
    const ListStatusRow a = ListStatusRow(loaded: 50, total: 120, loading: false);
    const ListStatusRow b = ListStatusRow(loaded: 120, total: 120, loading: false);
    const ListStatusRow c = ListStatusRow(loaded: 50, total: 120, loading: true);
    expect(a.loaded, 50);
    expect(b.total, 120);
    expect(c.loading, isTrue);
  });

  testWidgets('⑧ 状态行文案随「到底 / 还有」变化', (WidgetTester tester) async {
    await UiHarness().pump(
      tester,
      host(const ListStatusRow(loaded: 50, total: 120, loading: false)),
    );
    expect(find.text('已显示 50 / 共 120'), findsOneWidget);

    await UiHarness().pump(
      tester,
      host(const ListStatusRow(loaded: 120, total: 120, loading: false)),
    );
    expect(find.text('已显示全部 120 笔'), findsOneWidget);
  });
}
