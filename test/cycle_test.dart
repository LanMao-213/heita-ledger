// 周期与归属期的纯函数自检。
//
// 这些断言看着琐碎，但每一条都对应一个「界面上看不出来、只有跨月才露」的错误：
// - 账单日当天到底归新期还是旧期（差一天，整月数据错位）
// - 起始日 31 号遇 2 月怎么收拢（不收拢会抛异常或算出 0 天）
// - 工资抬期会不会把两个月工资塞进同一期（09-20 那条）
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/cycle.dart';

void main() {
  group('cycleStartOf', () {
    test('常规日就是当月那一天', () {
      expect(cycleStartOf(2026, 10, 15), DateTime(2026, 10, 15));
    });

    test('31 号遇 2 月收拢到月末', () {
      expect(cycleStartOf(2026, 2, 31), DateTime(2026, 2, 28));
      expect(cycleStartOf(2024, 2, 31), DateTime(2024, 2, 29), reason: '闰年');
    });

    test('31 号遇 30 天的月份收拢到 30', () {
      expect(cycleStartOf(2026, 4, 31), DateTime(2026, 4, 30));
    });

    test('越界的起始日夹到 1–31', () {
      expect(cycleStartOf(2026, 10, 0), DateTime(2026, 10, 1));
      expect(cycleStartOf(2026, 10, 99), DateTime(2026, 10, 31));
    });

    test('月份超出 1–12 自动进位', () {
      expect(cycleStartOf(2026, 13, 15), DateTime(2027, 1, 15));
      expect(cycleStartOf(2026, 0, 15), DateTime(2025, 12, 15));
    });
  });

  group('cycleRange', () {
    test('账单日当天算新一期（不是前一天）', () {
      expect(cycleRange(DateTime(2026, 10, 15), 15), (
        '2026-10-15',
        '2026-11-14',
      ));
    });

    test('账单日前一天算上一期', () {
      expect(cycleRange(DateTime(2026, 10, 14), 15), (
        '2026-09-15',
        '2026-10-14',
      ));
    });

    test('账单日为 1 时完全等于自然月（老用户零感知的前提）', () {
      expect(cycleRange(DateTime(2026, 10, 17), 1), (
        '2026-10-01',
        '2026-10-31',
      ));
      expect(cycleRange(DateTime(2026, 2, 1), 1), ('2026-02-01', '2026-02-28'));
    });

    test('12 月的期跨年', () {
      expect(cycleRange(DateTime(2026, 12, 20), 15), (
        '2026-12-15',
        '2027-01-14',
      ));
    });

    test('2 月被收拢后仍能正常成期', () {
      // 2026 年 2 月的账单日 31 → 28 号；下一期从 3-31 起
      expect(cycleRange(DateTime(2026, 2, 28), 31), (
        '2026-02-28',
        '2026-03-30',
      ));
      // 2 月 27 日还留在上一期（1-31 ~ 2-27）
      expect(cycleRange(DateTime(2026, 2, 27), 31), (
        '2026-01-31',
        '2026-02-27',
      ));
    });
  });

  group('shiftCycle', () {
    test('往后翻一期', () {
      expect(shiftCycle(DateTime(2026, 10, 17), 15, 1), DateTime(2026, 11, 15));
    });

    test('往前翻一期', () {
      expect(shiftCycle(DateTime(2026, 10, 17), 15, -1), DateTime(2026, 9, 15));
    });

    test('翻的是「期」不是「月」：从期中翻，落点仍是新期第一天', () {
      // 10-10 属于 09-15 那期，往后翻一期正好是 10-15
      expect(shiftCycle(DateTime(2026, 10, 10), 15, 1), DateTime(2026, 10, 15));
    });

    test('跨年往前翻', () {
      // 1-20 落在 01-15 那期，往前一期跨到去年 12 月
      expect(shiftCycle(DateTime(2026, 1, 20), 15, -1), DateTime(2025, 12, 15));
    });

    test('从期中间往前翻，落点仍是整期边界', () {
      // 1-10 还属于 2025-12-15 那期，再往前就是 2025-11-15
      expect(shiftCycle(DateTime(2026, 1, 10), 15, -1), DateTime(2025, 11, 15));
    });

    test('连续翻三期仍对齐账单日', () {
      expect(shiftCycle(DateTime(2026, 10, 17), 15, 3), DateTime(2027, 1, 15));
    });
  });

  group('periodStartOf —— 工资抬期（R1）', () {
    test('账单日 15：10-10 的工资抬到 10-15 那期', () {
      expect(periodStartOf('2026-10-10', 15, liftToNext: true), '2026-10-15');
    });

    test('账单日前一天（10-14）同样抬', () {
      expect(periodStartOf('2026-10-14', 15, liftToNext: true), '2026-10-15');
    });

    test('账单日之后到账（10-17）不抬，本来就属于这一期', () {
      expect(periodStartOf('2026-10-17', 15, liftToNext: true), '2026-10-15');
    });

    test('09-20 不会被抬两期（否则两个月工资挤进一期）', () {
      expect(periodStartOf('2026-09-20', 15, liftToNext: true), '2026-09-15');
    });

    test('不抬时就是所在期的第一天', () {
      expect(periodStartOf('2026-10-10', 15), '2026-09-15');
      expect(periodStartOf('2026-10-17', 15), '2026-10-15');
    });

    test('账单日为 1 时抬期永不生效（老用户行为一点不变）', () {
      expect(periodStartOf('2026-10-10', 1, liftToNext: true), '2026-10-01');
      expect(periodStartOf('2026-10-01', 1, liftToNext: true), '2026-10-01');
    });

    test('跨年：1-10 的工资抬到 1-15 那期', () {
      expect(periodStartOf('2027-01-10', 15, liftToNext: true), '2027-01-15');
    });

    test('短月收拢后仍然自洽：2-25 的工资抬到 2-28 那期', () {
      expect(periodStartOf('2026-02-25', 31, liftToNext: true), '2026-02-28');
    });
  });

  group('liftable —— 开关该不该出现', () {
    test('账单日 15：10 号可抬，17 号不可', () {
      expect(liftable('2026-10-10', 15), isTrue);
      expect(liftable('2026-10-17', 15), isFalse);
    });

    test('账单日 1：永远不可抬', () {
      expect(liftable('2026-10-10', 1), isFalse);
    });

    test('账单日当天不可抬（已经在期内）', () {
      expect(liftable('2026-10-15', 15), isFalse);
    });
  });

  group('展示与判定', () {
    test('周期条文案', () {
      expect(cycleLabel('2026-10-15', '2026-11-14'), '10-15 → 11-14');
    });

    test('概览卡文案用点分 + en dash，不用箭头', () {
      expect(periodLabel('2026-10-01', '2026-10-31'), '10.01 – 10.31');
      expect(dotYmd('2026-09-05'), '09.05');
    });

    test('判断是否本期', () {
      const from = '2026-10-15';
      const to = '2026-11-14';
      expect(isCurrentCycle(from, to, now: DateTime(2026, 10, 17)), isTrue);
      expect(isCurrentCycle(from, to, now: DateTime(2026, 10, 14)), isFalse);
      expect(isCurrentCycle(from, to, now: DateTime(2026, 11, 14)), isTrue);
      expect(isCurrentCycle(from, to, now: DateTime(2026, 11, 15)), isFalse);
    });
  });

  group('日历范围', () {
    test('范围以今天为基准，不是写死的上下限', () {
      // 2026-10 打开：往前 23 个月、往后 3 个月
      final a = calendarRange('2026-10', now: DateTime(2026, 10, 18));
      expect(a.$1, '2024-11');
      expect(a.$2, '2027-01');

      // 到了 2027-02 再打开，上界自己推到 2027-05 —— 不会停在「只到 1 月」
      final b = calendarRange('2027-02', now: DateTime(2027, 2, 5));
      expect(b.$1, '2025-03');
      expect(b.$2, '2027-05');
    });

    test('翻到很早的账时，下界跟着 anchor 一起往前挪', () {
      final r = calendarRange('2023-01', now: DateTime(2026, 10, 18));
      expect(r.$1, '2021-02');
      expect(r.$2, '2027-01');
    });
  });
}
