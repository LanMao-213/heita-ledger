import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/widgets/record_sheet.dart';

/// 记账面板大字金额的显示规则。
///
/// 核心诉求（2026-10-28 用户反馈）：**输入 `4.3` 不该被显示成 `4.30`**。
/// 这一屏是「正在输入」，不是「计算结果是」，补零会让人误以为已经输完了。
void main() {
  group('纯字面量：原样显示用户敲的位数', () {
    test('一位小数不被补零', () {
      expect(amountDraftText('4.3'), '4.3');
      expect(amountDraftText('0.5'), '0.5');
      expect(amountDraftText('12.34'), '12.34');
    });

    test('两位小数保持两位', () {
      expect(amountDraftText('4.30'), '4.30');
      expect(amountDraftText('4.00'), '4.00');
    });

    test('刚按完小数点时保留那个点', () {
      expect(amountDraftText('4.'), '4.');
      expect(amountDraftText('0.'), '0.');
    });

    test('整数原样，带千分位分组', () {
      expect(amountDraftText('4'), '4');
      expect(amountDraftText('1234'), '1,234');
      expect(amountDraftText('1234567'), '1,234,567');
      expect(amountDraftText('1234.5'), '1,234.5');
    });

    test('前导零去掉，但 0.x 的那个 0 留着', () {
      expect(amountDraftText('007'), '7');
      expect(amountDraftText('0'), '0');
      expect(amountDraftText('00.5'), '0.5');
    });

    test('行首负号是净额，不能在显示时吞掉', () {
      expect(amountDraftText('-20'), '-20');
      expect(amountDraftText('-4.3'), '-4.3');
    });
  });

  group('含运算符：按计算结果，去掉无意义的零', () {
    test('整数结果不带小数位', () {
      expect(amountDraftText('4.3+2'), '6.3');
      expect(amountDraftText('1+2'), '3');
      expect(amountDraftText('10/4'), '2.5');
    });

    test('有余数时保留两位', () {
      expect(amountDraftText('1.5+0.05'), '1.55');
    });

    test('末尾没敲完的运算符不显示', () {
      expect(amountDraftText('12+'), '12');
      expect(amountDraftText('4.3+'), '4.3');
    });
  });

  group('空与非法输入', () {
    test('什么都没敲 → 0', () {
      expect(amountDraftText(''), '0');
      expect(amountDraftText('-'), '0');
      expect(amountDraftText('+'), '0');
    });

    test('除以零之类的非法表达式 → 0，不崩', () {
      expect(amountDraftText('1/0'), '0');
    });
  });
}
