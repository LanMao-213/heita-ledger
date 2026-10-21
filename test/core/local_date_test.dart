import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';

/// `LocalDate`：只表示「哪一天」，日历运算走日期而不是 `Duration`。
void main() {
  group('解析', () {
    test('YYYY-MM-DD / YYYY/MM/DD / YYYYMMDD 三种都认', () {
      expect(LocalDate.tryParse('2026-10-16'), const LocalDate(2026, 10, 16));
      expect(LocalDate.tryParse('2026/10/16'), const LocalDate(2026, 10, 16));
      expect(LocalDate.tryParse('20261016'), const LocalDate(2026, 10, 16));
    });

    test('去空白', () {
      expect(LocalDate.tryParse('  2026-10-16 '), const LocalDate(2026, 10, 16));
    });

    test('非法日期返回 null（不会自动进位成 3 月 2 日）', () {
      expect(LocalDate.tryParse('2026-02-30'), isNull);
      expect(LocalDate.tryParse('2026-13-01'), isNull);
      expect(LocalDate.tryParse('2026-00-10'), isNull);
      expect(LocalDate.tryParse(''), isNull);
      expect(LocalDate.tryParse('abc'), isNull);
      expect(LocalDate.tryParse('2026-10'), isNull);
    });

    test('parse 非法抛 FormatException', () {
      expect(() => LocalDate.parse('x'), throwsFormatException);
    });

    test('闰年 2-29 合法、平年非法', () {
      expect(LocalDate.tryParse('2028-02-29'), const LocalDate(2028, 2, 29));
      expect(LocalDate.tryParse('2026-02-29'), isNull);
    });
  });

  group('格式化', () {
    test('iso 补零', () {
      expect(const LocalDate(2026, 1, 5).iso, '2026-01-05');
      expect(const LocalDate(2026, 10, 16).ym, '2026-10');
    });

    test('weekday：1=周一', () {
      expect(const LocalDate(2026, 10, 16).weekday, 5);
    });
  });

  group('日历运算', () {
    test('addDays 跨月/跨年', () {
      expect(const LocalDate(2026, 10, 31).addDays(1), const LocalDate(2026, 11, 1));
      expect(const LocalDate(2026, 12, 31).addDays(1), const LocalDate(2027, 1, 1));
      expect(const LocalDate(2026, 1, 1).addDays(-1), const LocalDate(2025, 12, 31));
    });

    test('addMonths 默认把日号收拢到月末', () {
      expect(const LocalDate(2026, 1, 31).addMonths(1), const LocalDate(2026, 2, 28));
      expect(const LocalDate(2028, 1, 31).addMonths(1), const LocalDate(2028, 2, 29));
      expect(const LocalDate(2026, 3, 31).addMonths(1), const LocalDate(2026, 4, 30));
      expect(const LocalDate(2026, 12, 15).addMonths(1), const LocalDate(2027, 1, 15));
      expect(const LocalDate(2026, 1, 15).addMonths(-1), const LocalDate(2025, 12, 15));
    });

    test('addMonths(clampToMonthEnd: false) 允许溢出', () {
      expect(
        const LocalDate(2026, 1, 31).addMonths(1, clampToMonthEnd: false),
        const LocalDate(2026, 3, 3),
      );
    });

    test('daysInMonth', () {
      expect(LocalDate.daysInMonth(2026, 2), 28);
      expect(LocalDate.daysInMonth(2028, 2), 29);
      expect(LocalDate.daysInMonth(2026, 4), 30);
      expect(LocalDate.daysInMonth(2026, 12), 31);
    });

    test('diffDays 双向', () {
      expect(const LocalDate(2026, 10, 31).diffDays(const LocalDate(2026, 10, 1)), 30);
      expect(const LocalDate(2026, 10, 1).diffDays(const LocalDate(2026, 10, 31)), -30);
    });

    test('firstOfMonth / lastOfMonth', () {
      expect(const LocalDate(2026, 2, 17).firstOfMonth, const LocalDate(2026, 2, 1));
      expect(const LocalDate(2026, 2, 17).lastOfMonth, const LocalDate(2026, 2, 28));
    });
  });

  group('比较', () {
    test('同一天相等、可作 Map 键', () {
      final Map<LocalDate, String> m = <LocalDate, String>{
        const LocalDate(2026, 10, 16): 'a',
      };
      expect(m[const LocalDate(2026, 10, 16)], 'a');
      expect(
        const LocalDate(2026, 10, 16).hashCode,
        const LocalDate(2026, 10, 16).hashCode,
      );
    });

    test('大小与区间', () {
      const LocalDate a = LocalDate(2026, 10, 1);
      const LocalDate b = LocalDate(2026, 10, 31);
      expect(a < b, isTrue);
      expect(a <= a, isTrue);
      expect(b > a, isTrue);
      expect(b >= b, isTrue);
      expect(const LocalDate(2026, 10, 15).isBetween(a, b), isTrue);
      expect(a.isBetween(a, b), isTrue, reason: '含两端');
      expect(b.isBetween(a, b), isTrue, reason: '含两端');
      expect(const LocalDate(2026, 11, 1).isBetween(a, b), isFalse);
    });

    test('跨年比较不看字符串（10 月 < 次年 1 月）', () {
      expect(const LocalDate(2026, 10, 1) < const LocalDate(2027, 1, 1), isTrue);
    });
  });

  test('firstDayOfMonth', () {
    expect(firstDayOfMonth('2026-10'), const LocalDate(2026, 10, 1));
    expect(firstDayOfMonth('2026-13'), isNull);
    expect(firstDayOfMonth('2026'), isNull);
  });
}
