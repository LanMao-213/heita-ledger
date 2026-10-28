// 金额表达式引擎的自检。
//
// 这段是记账 App 最不能出错的一段：算错一分钱比界面崩了更糟。
// 分两类测：press（按键变换）与 cents（求值）。
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/calc.dart';

void main() {
  group('求值', () {
    test('纯数字与小数', () {
      expect(Calc.cents('12'), 1200);
      expect(Calc.cents('12.5'), 1250);
      expect(Calc.cents('0'), 0);
      expect(Calc.cents('0.05'), 5);
    });

    test('乘除优先于加减', () {
      expect(Calc.cents('12+3.5*2'), 1900);
      expect(Calc.cents('2*3+4'), 1000);
      expect(Calc.cents('10-4/2'), 800);
    });

    test('同级左结合', () {
      expect(Calc.cents('100-30-20'), 5000);
      expect(Calc.cents('100/2/5'), 1000);
      expect(Calc.cents('1+2+3'), 600);
    });

    test('负数（净额）：行首负号与运算符后的负号', () {
      expect(Calc.cents('-20'), -2000);
      expect(Calc.cents('-20+5'), -1500);
      expect(Calc.cents('12*-3'), -3600);
      expect(Calc.cents('-0.5'), -50);
    });

    test('不完整或非法表达式返回 null', () {
      expect(Calc.cents(''), isNull);
      expect(Calc.cents('12+'), isNull);
      expect(Calc.cents('-'), isNull);
      expect(Calc.cents('15.'), isNull); // 结尾带点不算输完
      expect(Calc.cents('1.2.3'), isNull);
      expect(Calc.cents('5/0'), isNull);
      expect(Calc.cents('abc'), isNull);
    });

    test('精度只在最后取整一次', () {
      expect(Calc.cents('0.1+0.2'), 30);
      expect(Calc.cents('0.07*3'), 21);
      expect(Calc.cents('100/3'), 3333);
    });
  });

  group('按键变换', () {
    test('行首打负号就是负数', () {
      var e = Calc.press('', '-');
      expect(e, '-');
      e = Calc.press(e, '2');
      e = Calc.press(e, '0');
      expect(e, '-20');
      expect(Calc.cents(e), -2000);
    });

    test('行首打其它运算符无效', () {
      expect(Calc.press('', '+'), '');
      expect(Calc.press('', '*'), '');
      expect(Calc.press('', '/'), '');
    });

    test('连按运算符只替换不叠加', () {
      expect(Calc.press('12+', '-'), '12-');
      expect(Calc.press('12*', '/'), '12/');
      expect(Calc.press('12.', '+'), '12+');
    });

    test('小数点自动补零，一个数只允许一个点', () {
      expect(Calc.press('', '.'), '0.');
      expect(Calc.press('12', '.'), '12.');
      expect(Calc.press('12.5', '.'), '12.5');
      expect(Calc.press('12+', '.'), '12+0.');
    });

    test('前导零被替换、两位小数封顶', () {
      expect(Calc.press('0', '5'), '5');
      expect(Calc.press('1.23', '4'), '1.23');
      expect(Calc.press('1.2', '3'), '1.23');
    });

    test('C 清空、del 退一格', () {
      expect(Calc.press('12+3', 'C'), '');
      expect(Calc.press('12+3', 'del'), '12+');
      expect(Calc.press('', 'del'), '');
    });

    test('显示：pretty 换符号，hasOperator 不把行首负号当运算', () {
      expect(Calc.pretty('12*3-1'), '12×3-1');
      expect(Calc.hasOperator('-20'), isFalse);
      expect(Calc.hasOperator('12-3'), isTrue);
      expect(Calc.hasOperator('12*3'), isTrue);
    });
  });

  // 展示口径与求值口径的分工。1.5.0 的「按小数点 1 变 0」就是两条口径
  // 混用造成的：金额区拿了「能不能存」的答案当「已经敲了什么」。
  group('展示（display）', () {
    test('没输完的表达式：数字留着，小数点要标记出来', () {
      expect(Calc.display('1.')?.cents, 100);
      expect(Calc.display('1.')?.trailingDot, isTrue);
      expect(Calc.display('0.')?.cents, 0);
      expect(Calc.display('1234.')?.cents, 123400);
    });

    test('末尾是运算符：显示的是它左边那个数', () {
      expect(Calc.display('12+')?.cents, 1200);
      expect(Calc.display('12+')?.trailingDot, isFalse);
      expect(Calc.display('12*')?.cents, 1200);
      expect(Calc.display('12.')?.trailingDot, isTrue);
      // 小数参与运算后再按运算符：值会保留下来
      expect(Calc.display('1.5+')?.cents, 150);
    });

    test('一个数字都没有时返回 null（金额区据此显示 0）', () {
      expect(Calc.display(''), isNull);
      expect(Calc.display('-'), isNull);
      expect(Calc.display('+'), isNull);
    });

    test('完整表达式照常求值', () {
      expect(Calc.display('12')?.cents, 1200);
      expect(Calc.display('12+8')?.cents, 2000);
      expect(Calc.display('-20')?.cents, -2000);
      expect(Calc.display('0.05')?.cents, 5);
      expect(Calc.display('0.05')?.trailingDot, isFalse);
    });

    test('cents 的结论不受影响：能不能存仍按原规则', () {
      // 这两条是确认键置灰的依据，不能因为展示变宽松而放松
      expect(Calc.cents('1.'), isNull);
      expect(Calc.cents('12+'), isNull);
    });
  });
}
