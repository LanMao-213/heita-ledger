import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';

/// 周期口径（最容易算错的一节）。
///
/// 三件事：① 账单日当天算新期（`>=`）；② 短月收拢；③ 抬期 R1 的五个边界。
void main() {
  LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

  group('cycleStartOf / cycleRange：账单日当天算新一期（>=）', () {
    test('账单日 15：10-15 当天 → 新期从 10-15 开始', () {
      expect(Period.cycleStartOf(d(2026, 10, 15), 15), d(2026, 10, 15));
    });

    test('账单日 15：10-14 → 上一期（09-15 起）', () {
      expect(Period.cycleStartOf(d(2026, 10, 14), 15), d(2026, 9, 15));
    });

    test('账单日 15：区间是 [10-15, 11-14]', () {
      final Period p = Period.cycleRange(d(2026, 10, 20), 15);
      expect(p.from, d(2026, 10, 15));
      expect(p.to, d(2026, 11, 14));
      expect(p.dayCount, 31);
    });

    test('账单日 1：等同于自然月', () {
      final Period p = Period.cycleRange(d(2026, 10, 31), 1);
      expect(p.from, d(2026, 10, 1));
      expect(p.to, d(2026, 10, 31));
    });
  });

  group('短月收拢（账单日 31 遇 2 月）', () {
    test('2026-02 的账单日落在 02-28', () {
      expect(Period.cycleStartIn(2026, 2, 31), d(2026, 2, 28));
      expect(Period.cycleStartIn(2028, 2, 31), d(2028, 2, 29));
    });

    test('02-27 属于 01-31 那一期，02-28 属于新一期', () {
      expect(Period.cycleStartOf(d(2026, 2, 27), 31), d(2026, 1, 31));
      expect(Period.cycleStartOf(d(2026, 2, 28), 31), d(2026, 2, 28));
    });

    test('01-31 那期的终点是 02-27（不丢天也不重叠）', () {
      final Period p = Period.cycleRange(d(2026, 1, 31), 31);
      expect(p.from, d(2026, 1, 31));
      expect(p.to, d(2026, 2, 27));
      expect(p.dayCount, 28);
    });

    test('账单日超过 31 被夹到 31', () {
      expect(Period.cycleStartIn(2026, 10, 99), d(2026, 10, 31));
      expect(Period.cycleStartIn(2026, 10, 0), d(2026, 10, 1));
    });
  });

  group('shiftCycle：按「期首 ± N 月」重算', () {
    test('+1 / -1', () {
      final Period p = Period.cycleRange(d(2026, 10, 20), 15);
      expect(Period.shiftCycle(p, 1, 15).from, d(2026, 11, 15));
      expect(Period.shiftCycle(p, 1, 15).to, d(2026, 12, 14));
      expect(Period.shiftCycle(p, -1, 15).from, d(2026, 9, 15));
      expect(Period.shiftCycle(p, -1, 15).to, d(2026, 10, 14));
    });

    test('2 月附近不会跑到隔壁期（账单日 31）', () {
      // 01-31 期 +1 → 02-28 期（而不是 03-03 或 02-31）
      final Period jan = Period.cycleRange(d(2026, 1, 31), 31);
      final Period feb = Period.shiftCycle(jan, 1, 31);
      expect(feb.from, d(2026, 2, 28));
      expect(feb.to, d(2026, 3, 30));

      // 再 +1 要回到 03-31，不能停在 03-28
      final Period mar = Period.shiftCycle(feb, 1, 31);
      expect(mar.from, d(2026, 3, 31));
      expect(mar.to, d(2026, 4, 29));

      // -1 回到 01-31
      expect(Period.shiftCycle(feb, -1, 31).from, d(2026, 1, 31));
    });

    test('跨年 +1（12 月期 → 次年 1 月期）', () {
      final Period p = Period.cycleRange(d(2026, 12, 20), 15);
      final Period next = Period.shiftCycle(p, 1, 15);
      expect(next.from, d(2027, 1, 15));
      expect(next.to, d(2027, 2, 14));
    });
  });

  group('抬期 R1 的五个边界', () {
    // ① 10-10 到账（账单日 15）→ 抬到 10-15 那期
    test('① 10-10 的工资抬到 10-15 那期', () {
      expect(
        Period.periodStartOf(d(2026, 10, 10), 15, liftToNext: true),
        d(2026, 10, 15),
      );
      expect(
        Period.periodStartOf(d(2026, 10, 10), 15),
        d(2026, 9, 15),
        reason: '不抬时仍落在 09-15 那期',
      );
    });

    // ② 10-17 到账 → 已经在期内，不动
    test('② 10-17 不动（一律抬期的实现会错推到 11-15）', () {
      expect(
        Period.periodStartOf(d(2026, 10, 17), 15, liftToNext: true),
        d(2026, 10, 15),
      );
    });

    // ③ 09-20 到账 → 不连抬两期
    test('③ 09-20 不抬两期（否则两个月工资挤一期）', () {
      expect(
        Period.periodStartOf(d(2026, 9, 20), 15, liftToNext: true),
        d(2026, 9, 15),
      );
    });

    // ④ 账单日 1 → 抬期恒不生效
    test('④ 账单日 1 恒不抬（老用户行为零变化）', () {
      for (int day = 1; day <= 28; day++) {
        expect(
          Period.periodStartOf(d(2026, 10, day), 1, liftToNext: true),
          d(2026, 10, 1),
        );
      }
      expect(Period.liftable(d(2026, 10, 5), 1), isFalse);
    });

    // ⑤ 非白名单分类不抬
    test('⑤ 白名单只认收入 + 工资/奖金/提成', () {
      expect(
        Period.shouldLift(
          isIncome: true,
          categoryName: '工资',
          date: d(2026, 10, 10),
          startDay: 15,
        ),
        isTrue,
      );
      expect(
        Period.shouldLift(
          isIncome: true,
          categoryName: '提成',
          date: d(2026, 10, 10),
          startDay: 15,
        ),
        isTrue,
      );
      expect(
        Period.shouldLift(
          isIncome: true,
          categoryName: '餐饮',
          date: d(2026, 10, 10),
          startDay: 15,
        ),
        isFalse,
      );
      expect(
        Period.shouldLift(
          isIncome: false,
          categoryName: '工资',
          date: d(2026, 10, 10),
          startDay: 15,
        ),
        isFalse,
        reason: '支出永远不抬',
      );
      expect(
        Period.shouldLift(
          isIncome: true,
          categoryName: '工资',
          date: d(2026, 10, 17),
          startDay: 15,
        ),
        isFalse,
        reason: '已在期内不抬',
      );
      expect(
        Period.shouldLift(
          isIncome: true,
          categoryName: null,
          date: d(2026, 10, 10),
          startDay: 15,
        ),
        isFalse,
      );
    });

    test('liftable 与 periodStartOf 的判定一致', () {
      expect(Period.liftable(d(2026, 10, 10), 15), isTrue);
      expect(Period.liftable(d(2026, 10, 15), 15), isFalse);
      expect(Period.liftable(d(2026, 10, 20), 15), isFalse);
    });
  });

  group('文案与判定', () {
    test('三种文案', () {
      final Period p = Period.cycleRange(d(2026, 10, 20), 15);
      expect(p.shortLabel, '10-15 至 11-14');
      expect(p.dotLabel, '10.15 至 11.14');
      expect(p.label, '2026-10-15 至 2026-11-14');
      expect(cycleLabel(p), p.shortLabel);
      expect(periodLabel(p), p.dotLabel);
    });

    test('isCurrentCycle 含两端', () {
      final Period p = Period(from: d(2026, 10, 15), to: d(2026, 11, 14));
      expect(Period.isCurrentCycle(p, today: d(2026, 10, 15)), isTrue);
      expect(Period.isCurrentCycle(p, today: d(2026, 11, 14)), isTrue);
      expect(Period.isCurrentCycle(p, today: d(2026, 11, 15)), isFalse);
      expect(p.contains(d(2026, 10, 20)), isTrue);
    });

    test('dayCount 现算（28/30/31 都对）', () {
      expect(Period(from: d(2026, 2, 1), to: d(2026, 2, 28)).dayCount, 28);
      expect(Period(from: d(2026, 4, 1), to: d(2026, 4, 30)).dayCount, 30);
      expect(Period(from: d(2026, 1, 1), to: d(2026, 1, 31)).dayCount, 31);
    });

    test('friendlyDate / monthLabel', () {
      expect(friendlyDate(d(2026, 10, 16)), '2026年10月16日 周五');
      expect(monthLabel('2026-10'), '2026年10月');
      expect(shortYmd(d(2026, 1, 5)), '01-05');
      expect(dotYmd(d(2026, 1, 5)), '01.05');
    });

    test('Period 相等性（值语义，可作 Map 键）', () {
      final Period a = Period(from: d(2026, 10, 15), to: d(2026, 11, 14));
      final Period b = Period(from: d(2026, 10, 15), to: d(2026, 11, 14));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(<Period, int>{a: 1}[b], 1);
    });
  });
}
