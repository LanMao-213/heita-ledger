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

    // 5) 全键盘只有一种键宽
    for (final label in ['C', '7', '4', '1', '2', '0']) {
      if (label == '0') continue; // 两格宽，本就不同
      expect(key(label).width, moreOrLessEquals(plus.width, epsilon: 0.01),
          reason: '「$label」的宽度和「+」不一致');
    }
  });
}
