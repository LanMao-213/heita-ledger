import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';

/// 周期账单的频率推进：**monthly 必须月末对齐**。
///
/// 这条错了不会崩，但房租会从「每月 31 号」漂成「每月 28 号」，再漂成 3 月 3 号。
void main() {
  LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

  group('monthly：月末对齐（1-31 + 1 月 → 2-28/29，不溢出到 3 月）', () {
    test('平年 1-31 + 1 月 → 2-28', () {
      expect(
        Recurring.advanceDate(d(2026, 1, 31), RecurFreq.monthly, 1),
        d(2026, 2, 28),
      );
    });

    test('闰年 1-31 + 1 月 → 2-29', () {
      expect(
        Recurring.advanceDate(d(2028, 1, 31), RecurFreq.monthly, 1),
        d(2028, 2, 29),
      );
    });

    test('3-31 + 1 月 → 4-30（短月收拢）', () {
      expect(
        Recurring.advanceDate(d(2026, 3, 31), RecurFreq.monthly, 1),
        d(2026, 4, 30),
      );
    });

    test('5-15 + 1 月 → 6-15（普通日期不动）', () {
      expect(
        Recurring.advanceDate(d(2026, 5, 15), RecurFreq.monthly, 1),
        d(2026, 6, 15),
      );
    });

    test('跨年 12-31 + 1 月 → 次年 1-31', () {
      expect(
        Recurring.advanceDate(d(2026, 12, 31), RecurFreq.monthly, 1),
        d(2027, 1, 31),
      );
    });

    test('interval = 2：1-31 + 2 月 → 3-31', () {
      expect(
        Recurring.advanceDate(d(2026, 1, 31), RecurFreq.monthly, 2),
        d(2026, 3, 31),
      );
    });
  });

  group('daily / weekly / yearly', () {
    test('daily + N 天', () {
      expect(
        Recurring.advanceDate(d(2026, 10, 30), RecurFreq.daily, 1),
        d(2026, 10, 31),
      );
      expect(
        Recurring.advanceDate(d(2026, 10, 30), RecurFreq.daily, 3),
        d(2026, 11, 2),
      );
    });

    test('weekly + 7N 天（跨月）', () {
      expect(
        Recurring.advanceDate(d(2026, 10, 28), RecurFreq.weekly, 1),
        d(2026, 11, 4),
      );
      expect(
        Recurring.advanceDate(d(2026, 10, 28), RecurFreq.weekly, 2),
        d(2026, 11, 11),
      );
    });

    test('yearly 同月同日 + 跨年', () {
      expect(
        Recurring.advanceDate(d(2026, 10, 16), RecurFreq.yearly, 1),
        d(2027, 10, 16),
      );
    });

    test('yearly：2-29 遇平年收拢到 2-28', () {
      expect(
        Recurring.advanceDate(d(2028, 2, 29), RecurFreq.yearly, 1),
        d(2029, 2, 28),
      );
    });

    test('interval < 1 按 1 处理（脏数据兜底）', () {
      expect(
        Recurring.advanceDate(d(2026, 10, 1), RecurFreq.daily, 0),
        d(2026, 10, 2),
      );
    });
  });

  group('isDue（补记的判断条件）', () {
    Recurring rule({
      required LocalDate next,
      bool enabled = true,
      LocalDate? end,
    }) => Recurring(
      type: TxnType.expense,
      amountCents: 300000,
      nextRunDate: next,
      enabled: enabled,
      endDate: end,
    );

    test('到期当天算到期', () {
      expect(rule(next: d(2026, 10, 1)).isDue(d(2026, 10, 1)), isTrue);
    });

    test('没到期不算（未来期只会有 0.00）', () {
      expect(rule(next: d(2026, 11, 1)).isDue(d(2026, 10, 31)), isFalse);
    });

    test('停用的规则永远不算到期', () {
      expect(
        rule(next: d(2026, 10, 1), enabled: false).isDue(d(2026, 10, 20)),
        isFalse,
      );
    });

    test('超过截止日不算到期', () {
      expect(
        rule(next: d(2026, 10, 1), end: d(2026, 9, 30)).isDue(d(2026, 10, 20)),
        isFalse,
      );
    });

    test('连续欠多期：逐期推进每次都前进一个月', () {
      LocalDate run = d(2026, 1, 31);
      final List<LocalDate> dates = <LocalDate>[];
      for (int i = 0; i < 4; i++) {
        run = Recurring.advanceDate(run, RecurFreq.monthly, 1);
        dates.add(run);
      }
      expect(dates, <LocalDate>[
        d(2026, 2, 28),
        d(2026, 3, 28),
        d(2026, 4, 28),
        d(2026, 5, 28),
      ]);
    });
  });

  test('TxnTemplate.recentSort：用过次数优先 → 最后使用时间 → sort_order', () {
    final DateTime base = DateTime(2026, 10, 1);
    final List<TxnTemplate> list = <TxnTemplate>[
      const TxnTemplate(name: 'A', type: TxnType.expense, sortOrder: 0),
      TxnTemplate(
        name: 'B',
        type: TxnType.expense,
        useCount: 5,
        lastUsedAt: base,
        sortOrder: 1,
      ),
      TxnTemplate(
        name: 'C',
        type: TxnType.expense,
        useCount: 1,
        lastUsedAt: base.add(const Duration(days: 1)),
        sortOrder: 2,
      ),
    ]..sort(TxnTemplate.recentSort);

    expect(list.map((TxnTemplate t) => t.name), <String>['B', 'C', 'A']);
  });
}
