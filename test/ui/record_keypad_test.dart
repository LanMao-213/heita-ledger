import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/ui/pages/record/record_keypad.dart';

import '../support/ui_fixture.dart';

/// 键盘：4 列 × 5 行、0 跨两格、确认键竖跨两行、**没有 ± 键**、键高 clamp。
void main() {
  String typed = '';
  bool confirmed = false;

  Widget keypad({bool canConfirm = true, bool expanded = false}) {
    return host(
      RecordKeypad(
        expanded: expanded,
        canConfirm: canConfirm,
        onKey: (String k) => typed += k,
        onConfirm: () => confirmed = true,
      ),
    );
  }

  setUp(() {
    typed = '';
    confirmed = false;
  });

  testWidgets('① 没有 ± 键（负号靠行首的 - 表达）', (WidgetTester tester) async {
    await UiHarness().pump(tester, keypad());

    expect(find.text('±'), findsNothing);
    expect(find.text('+/-'), findsNothing);
    // `-` 键在（它是运算符，也可能是行首负号）
    expect(find.byKey(const ValueKey<String>('key--')), findsOneWidget);
  });

  testWidgets('① 4 列 × 5 行：17 个可点键 + 1 个竖跨两行的确认键', (WidgetTester tester) async {
    await UiHarness().pump(tester, keypad());

    for (final String k in KeypadKeys.all) {
      expect(
        find.byKey(ValueKey<String>('key-$k')),
        findsOneWidget,
        reason: '缺键 $k',
      );
    }
    expect(find.byKey(const ValueKey<String>('key-confirm')), findsOneWidget);
    expect(KeypadKeys.all.length, 17);
  });

  testWidgets('① 「0」跨两格：宽度约为普通键的两倍', (WidgetTester tester) async {
    await UiHarness().pump(tester, keypad());

    final double zeroWidth =
        tester.getSize(find.byKey(const ValueKey<String>('key-0'))).width;
    final double oneWidth =
        tester.getSize(find.byKey(const ValueKey<String>('key-1'))).width;

    expect(zeroWidth / oneWidth, greaterThan(1.7));
    expect(zeroWidth / oneWidth, lessThan(2.3));
  });

  testWidgets('① 确认键竖跨两行：高度 ≈ 两个键高', (WidgetTester tester) async {
    await UiHarness().pump(tester, keypad());

    final double confirmHeight = tester
        .getSize(find.byKey(const ValueKey<String>('key-confirm')))
        .height;
    final double keyHeight =
        tester.getSize(find.byKey(const ValueKey<String>('key-1'))).height;

    expect(confirmHeight / keyHeight, greaterThan(1.8));
  });

  testWidgets('① 键高 clamp：常态 56、详情展开 38', (WidgetTester tester) async {
    expect(RecordKeypad.keyHeight(expanded: false), 56);
    expect(RecordKeypad.keyHeight(expanded: true), 38);

    await UiHarness().pump(tester, keypad(expanded: true));
    final double h =
        tester.getSize(find.byKey(const ValueKey<String>('key-1'))).height;
    expect(h, closeTo(RecordKeypad.minKeyHeight, 0.5));
  });

  testWidgets('② 表达式非法时确认键置灰且点不动', (WidgetTester tester) async {
    await UiHarness().pump(tester, keypad(canConfirm: false));

    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pump();

    expect(confirmed, isFalse);
    final Text label = tester.widget<Text>(find.text('确认'));
    // 置灰：文字色是 ink4（不是 onAccent）
    expect(label.style?.color, paletteInk().ink4);
  });

  testWidgets('② 合法时可点确认，按键回调逐个触发', (WidgetTester tester) async {
    await UiHarness().pump(tester, keypad());

    for (final String k in <String>['1', '2', '+', '3', '.', '5', 'C', 'del']) {
      await tester.tap(find.byKey(ValueKey<String>('key-$k')));
      await tester.pump();
    }
    expect(typed, '12+3.5Cdel');

    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pump();
    expect(confirmed, isTrue);
  });

  testWidgets('操作符键用数学符号显示（÷ × −）', (WidgetTester tester) async {
    await UiHarness().pump(tester, keypad());

    expect(find.text('÷'), findsOneWidget);
    expect(find.text('×'), findsOneWidget);
    expect(find.text('−'), findsOneWidget);
    // 底栏 tab 里也有「明细」等文案，这里只确认键盘符号
    expect(find.byType(RecordKeypad), findsOneWidget);
  });
}
