import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/money.dart';

/// 金额格式化与解析。口径 3.8：全程 int 分，只在最后取整一次。
void main() {
  group('Fmt.money（千分位）', () {
    test('123456 分 → 1,234.56', () {
      expect(Fmt.money(123456), '1,234.56');
    });

    test('整数不带小数位分隔符时也补 .00', () {
      expect(Fmt.money(100000), '1,000.00');
      expect(Fmt.money(0), '0.00');
    });

    test('负数带前导减号、正数按需加 +', () {
      expect(Fmt.money(-3850), '-38.50');
      expect(Fmt.money(3850, sign: true), '+38.50');
      expect(Fmt.money(0, sign: true), '0.00', reason: '0 不加正号');
    });

    test('trimZero：整数不带 .00', () {
      expect(Fmt.money(100000, trimZero: true), '1,000');
      expect(Fmt.money(100050, trimZero: true), '1,000.50');
    });

    test('大额千分位分组正确', () {
      expect(Fmt.money(999999999999), '9,999,999,999.99');
      expect(Fmt.money(100), '1.00');
    });
  });

  group('Fmt 其它', () {
    test('yuan 带 ¥', () {
      expect(Fmt.yuan(123456), '¥1,234.56');
      expect(Fmt.yuan(-100, sign: false), '¥-1.00');
    });

    test('compact：≥1 万元显示「万」', () {
      expect(Fmt.compact(1200000), '1.2万');
      expect(Fmt.compact(12000000), '12万');
      expect(Fmt.compact(345600), '+3,456');
    });

    test('count：笔数千分位', () {
      expect(Fmt.count(1234), '1,234');
      expect(Fmt.count(0), '0');
    });

    test('parseCents：合法输入、¥ 与逗号、非法返回 0', () {
      expect(Fmt.parseCents('12.34'), 1234);
      expect(Fmt.parseCents('¥1,234.56'), 123456);
      expect(Fmt.parseCents('-38.5'), -3850);
      expect(Fmt.parseCents(''), 0);
      expect(Fmt.parseCents('abc'), 0, reason: '非法返回 0，不抛');
    });
  });

  group('Money 值类', () {
    test('tryParseYuan：¥ / 逗号 / 负数 / 非法 null', () {
      expect(Money.tryParseYuan('¥1,234.56')?.cents, 123456);
      expect(Money.tryParseYuan('-38.5')?.cents, -3850);
      expect(Money.tryParseYuan('12')?.cents, 1200);
      expect(Money.tryParseYuan(''), isNull);
      expect(Money.tryParseYuan('12.3.4'), isNull);
    });

    test('parseYuanOrZero：非法 → 0（导入路径）', () {
      expect(Money.parseYuanOrZero('abc'), Money.zero);
      expect(Money.parseYuanOrZero('1,000').cents, 100000);
    });

    test('四则运算与比较', () {
      expect((const Money(100) + const Money(23)).cents, 123);
      expect((const Money(100) - const Money(23)).cents, 77);
      expect((const Money(-5)).abs().cents, 5);
      expect((-const Money(5)).cents, -5, reason: '一元负号翻转符号');
      expect((const Money(100) * 3).cents, 300);
      expect(const Money(100) > const Money(99), isTrue);
      expect(const Money(100) == const Money(100), isTrue);
    });

    test('上限判定与键盘一致（999999999999）', () {
      expect(const Money(Money.maxAbsCents).isWithinLimit, isTrue);
      expect(const Money(Money.maxAbsCents + 1).isWithinLimit, isFalse);
    });

    test('format 走同一套千分位', () {
      expect(const Money(123456).format(), '1,234.56');
      expect(const Money(123456).format(sign: true), '+1,234.56');
      expect(const Money(1200000).format(compact: true), '1.2万');
    });
  });
}
