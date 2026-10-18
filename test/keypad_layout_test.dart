// 金额键盘的列对齐自检。
//
// 真机上发现的毛病：确认键比上面的「+」宽一截，「3 / .」也没和「9 / 6」对齐。
// 原因是两套算法：
//   - 上面三行 = 4 个 Expanded + 3 个缝 → 键宽 (W - 3g) / 4
//   - 底排左边 = flex 3 / 1 分出来 → 内层再 (W - g) * 3/4 三分 → 键宽 86
//   - 确认键 = flex 1 → 90
// 366 的可用宽度下分别是 87 / 86 / 90，差几像素，肉眼就是「没对齐」。
//
// 这里直接量每个键的矩形，钉死「所有键同宽、同列左右边一致」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/widgets/calc_keypad.dart';

void main() {
  testWidgets('四列等宽：确认与「+」同宽，3 / . 与 9 / 6 左右边对齐', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 366,
              child: CalcKeypad(
                onKey: (_) {},
                onConfirm: () {},
                canConfirm: true,
              ),
            ),
          ),
        ),
      ),
    );

    // 量按键本身（GestureDetector = 整个键位格子），不是字形
    Rect key(String label) => tester.getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(GestureDetector),
          ).first,
        );

    final plus = key('+');
    final confirm = key('确认');
    final nine = key('9');
    final six = key('6');
    final three = key('3');
    final dot = key('.');
    final one = key('1');
    final two = key('2');
    final zero = key('0');

    // 1) 确认键和「+」同宽、左右边严格一致（之前宽 3px、右移 0）
    expect(confirm.width, moreOrLessEquals(plus.width, epsilon: 0.01),
        reason: '确认键比上面的键宽：${confirm.width} vs ${plus.width}');
    expect(confirm.left, moreOrLessEquals(plus.left, epsilon: 0.01));
    expect(confirm.right, moreOrLessEquals(plus.right, epsilon: 0.01));

    // 2) 底排 1 / 2 / 3 与上排 7 / 8 / 9、4 / 5 / 6 同列
    for (final pair in [
      (key('7'), one),
      (key('8'), two),
      (nine, three),
    ]) {
      expect(pair.$2.left, moreOrLessEquals(pair.$1.left, epsilon: 0.01),
          reason: '底排与上排左边没对齐');
      expect(pair.$2.right, moreOrLessEquals(pair.$1.right, epsilon: 0.01),
          reason: '底排与上排右边没对齐');
    }
    expect(six.left, moreOrLessEquals(three.left, epsilon: 0.01));

    // 3) 「.」和「3 / 6 / 9」同列
    expect(dot.left, moreOrLessEquals(three.left, epsilon: 0.01),
        reason: '「.」没和「3」对齐');
    expect(dot.right, moreOrLessEquals(three.right, epsilon: 0.01));

    // 4) 「0」占两列：左边接「1」，右边接「2」
    expect(zero.left, moreOrLessEquals(one.left, epsilon: 0.01));
    expect(zero.right, moreOrLessEquals(two.right, epsilon: 0.01));

    // 5) 文字必须落在格子的正中（「0」跨两格时居中于两格之间）
    for (final (label, cell) in [
      ('7', key('7')),
      ('0', zero),
      ('+', plus),
      ('确认', confirm),
    ]) {
      final glyph = tester.getRect(find.text(label));
      expect(glyph.center.dx, moreOrLessEquals(cell.center.dx, epsilon: 1),
          reason: '「$label」没在格子里水平居中：字形 ${glyph.center.dx}，格子 ${cell.center.dx}');
    }

    // 6) 键高：普通键 = keyHeight，确认 = 两键 + 一个缝；确认块与左边两行齐平
    for (final label in ['C', '7', '4', '1', '0', '+']) {
      expect(key(label).height, moreOrLessEquals(46, epsilon: 0.01),
          reason: '「$label」高度不等于 keyHeight（多半是没给显式高度，被文字撑成了 33）');
    }
    expect(confirm.height, moreOrLessEquals(46 * 2 + 6, epsilon: 0.01));
    expect(confirm.top, moreOrLessEquals(key('1').top, epsilon: 0.01));
    expect(confirm.bottom, moreOrLessEquals(zero.bottom, epsilon: 0.01));

    // 7) 全键盘只有一种键宽
    for (final label in ['C', '7', '4', '1', '2', '0']) {
      if (label == '0') continue; // 两格宽，本就不同
      expect(key(label).width, moreOrLessEquals(plus.width, epsilon: 0.01),
          reason: '「$label」的宽度和「+」不一致');
    }
  });

  testWidgets('按下变深、抬手恢复；所有键常态都有底色，不许半有半无', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 366,
              child: CalcKeypad(
                onKey: (_) {},
                onConfirm: () {},
                canConfirm: true,
              ),
            ),
          ),
        ),
      ),
    );

    Color? cap(String label) {
      final c = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (c.decoration as BoxDecoration?)?.color;
    }

    // 数字 / 运算符 / C / 确认 —— 四类键都必须有底，且普通键是同一块色。
    // 之前一半透明一半 bg2，键盘看起来像两套东西拼的。
    for (final label in ['7', '0', '.', '+', '×', '÷', 'C', '确认']) {
      expect(cap(label), isNot(Colors.transparent),
          reason: '「$label」没有底色：不能有的有、有的没有');
    }
    for (final label in ['7', '0', '.', '+', '×', '÷', 'C']) {
      expect(cap(label), C.bg2, reason: '「$label」的底色和别的普通键不一致');
    }
    expect(cap('确认'), C.ink, reason: '确认键是唯一的重色块');

    final g = await tester.startGesture(tester.getCenter(find.text('7')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(cap('7'), C.line2, reason: '按下没有可见的变深');

    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(cap('7'), C.bg2, reason: '抬手后底色没退回去');
  });
}
