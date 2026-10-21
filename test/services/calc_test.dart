import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/services/calc_service.dart';

/// 键盘表达式：13 条按键规则 + 求值边界。
///
/// 这一组钉的是「写错了不会崩、但金额会错」的那部分 —— `0.1+0.2` 差 1 分，
/// 一个月记 60 笔就能差出半块钱。
void main() {
  String type(String keys) {
    String expr = '';
    for (final String k in keys.split('')) {
      expr = CalcService.press(expr, k);
    }
    return expr;
  }

  group('按键变换', () {
    test('① 小数点唯一', () {
      expect(type('5.'), '5.');
      expect(CalcService.press('5.', '.'), '5.');
      expect(CalcService.press('1.5', '.'), '1.5');
    });

    test('② 行首只允许负号（+ * / 无左操作数，直接忽略）', () {
      expect(CalcService.press('', '-'), '-');
      expect(CalcService.press('', '+'), '');
      expect(CalcService.press('', '*'), '');
      expect(CalcService.press('', '/'), '');
    });

    test('③ 只有一个负号时后面只能接数字', () {
      expect(CalcService.press('-', '+'), '-');
      expect(CalcService.press('-', '5'), '-5');
      expect(CalcService.press('-', '.'), '-0.');
    });

    test('④ 连按运算符替换上一个（不堆成 12+-）', () {
      expect(CalcService.press('12+', '+'), '12+');
      expect(CalcService.press('12+', '-'), '12-');
      expect(CalcService.press('12*', '/'), '12/');
      expect(type('12+*'), '12*');
    });

    test('⑤ `12.` 后接运算符丢掉无意义的小数点', () {
      expect(CalcService.press('12.', '+'), '12+');
      expect(CalcService.press('12.', '*'), '12*');
    });

    test('⑥ 整数 9 位上限', () {
      expect(type('123456789'), '123456789');
      expect(CalcService.press('123456789', '0'), '123456789');
      expect(CalcService.press('12345678', '9'), '123456789');
    });

    test('⑦ 小数 2 位上限', () {
      expect(type('1.23'), '1.23');
      expect(CalcService.press('1.23', '4'), '1.23');
      expect(CalcService.press('1.2', '3'), '1.23');
    });

    test('⑧ `0` 后打数字替换前导零（不留 012）', () {
      expect(CalcService.press('0', '5'), '5');
      expect(CalcService.press('12+0', '7'), '12+7');
      expect(CalcService.press('0.', '5'), '0.5', reason: '小数里的 0 要保留');
    });

    test('⑨ 行首小数点自动补 0', () {
      expect(CalcService.press('', '.'), '0.');
      expect(CalcService.press('12+', '.'), '12+0.');
    });

    test('⑩ C 清空、del 退格（空串上退格不抛）', () {
      expect(CalcService.press('123', 'C'), '');
      expect(CalcService.press('123', 'del'), '12');
      expect(CalcService.press('', 'del'), '');
    });
  });

  group('求值', () {
    test('⑪ 0.1 + 0.2 == 30 分（只在最后取整一次）', () {
      expect(CalcService.evaluate('0.1+0.2'), 30);
    });

    test('⑫ 未输完 → null（`12.` / `12+` / `-`）', () {
      expect(CalcService.evaluate('12.'), isNull);
      expect(CalcService.evaluate('12+'), isNull);
      expect(CalcService.evaluate('-'), isNull);
      expect(CalcService.evaluate('12+.'), isNull);
    });

    test('⑬ 空串 → null', () {
      expect(CalcService.evaluate(''), isNull);
    });

    test('⑭ 除零 → null', () {
      expect(CalcService.evaluate('5/0'), isNull);
      expect(CalcService.evaluate('5/0.0'), isNull);
    });

    test('⑮ 优先级：乘除先于加减', () {
      expect(CalcService.evaluate('1+2*3'), 700);
      expect(CalcService.evaluate('10-2*3'), 400);
      expect(CalcService.evaluate('(1+2)'), isNull, reason: '不支持括号');
    });

    test('⑯ 行首负号是一元负号（-20 表示净流出）', () {
      expect(CalcService.evaluate('-20'), -2000);
      expect(CalcService.evaluate('10-2.5'), 750);
      expect(CalcService.evaluate('-2*3'), -600);
    });

    test('⑰ 上限 abs > 999999999999 → null', () {
      // 100 亿元 = 1000000000000 分 > 上限
      expect(CalcService.evaluate('10000000000'), isNull);
      expect(CalcService.evaluate('999999999.99'), 99999999999);
    });

    test('⑱ 小数结果四舍五入到分（10/3 → 333 分）', () {
      expect(CalcService.evaluate('10/3'), 333);
      expect(CalcService.evaluate('1/3'), 33);
    });
  });

  group('展示与状态机', () {
    test('⑲ pretty 换符号、hasOperator 认行首负号不算运算', () {
      expect(CalcService.pretty('12*3/4'), '12×3÷4');
      expect(CalcService.hasOperator('-20'), isFalse);
      expect(CalcService.hasOperator('10-2'), isTrue);
      expect(CalcService.hasOperator('12+'), isTrue);
    });

    test('⑳ 实例状态机：连续按键 → expr / cents / display', () {
      final CalcService calc = CalcService();
      for (final String k in <String>['1', '2', '+', '3']) {
        calc.tap(k);
      }
      expect(calc.expr, '12+3');
      expect(calc.cents, 1500);
      expect(calc.display, '12+3');
      expect(calc.isCompound, isTrue);

      calc.backspace();
      expect(calc.expr, '12+');
      expect(calc.cents, isNull);

      calc.clear();
      expect(calc.isEmpty, isTrue);
    });

    test('预填模板金额后继续按运算符', () {
      final CalcService calc = CalcService('38.5');
      expect(calc.cents, 3850);
      calc.tap('+');
      calc.tap('1');
      expect(calc.cents, 3950);
    });
  });
}
