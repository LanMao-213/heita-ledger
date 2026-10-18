// 预算节奏的纯函数测试。
//
// 这段最怕两类错：
// 1) 天数算错（含不含今天、跨月、未来月份、已过完的月份）——界面上的
//    「每天可花」会以一个很具体的金额骗人；
// 2) 取整方向错 —— 用四舍五入，每天多算 1 分，月底就会超。
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/pacing.dart';

void main() {
  // 2026 年 10 月有 31 天
  Pacing at(String today, {int? total, required int used}) => Pacing.of(
    month: '2026-10',
    totalCents: total,
    usedCents: used,
    today: today,
  );

  group('天数口径', () {
    test('月中：含今天，剩余天数把今天算进去', () {
      final p = at('2026-10-11', total: 300000, used: 124000);
      expect(p.totalDays, 31);
      expect(p.passedDays, 11);
      expect(p.remainDays, 21); // 11 号当天 + 之后 20 天
    });

    test('月初第一天：已过 1 天，剩 31 天', () {
      final p = at('2026-10-01', total: 310000, used: 0);
      expect(p.passedDays, 1);
      expect(p.remainDays, 31);
    });

    test('最后一天：还剩 1 天（就是今天）', () {
      final p = at('2026-10-31', total: 310000, used: 300000);
      expect(p.remainDays, 1);
      expect(p.canSpendPerDayCents, 10000);
    });

    test('未来月份：一天没过，整月可用', () {
      final p = Pacing.of(
        month: '2026-11',
        totalCents: 300000,
        usedCents: 0,
        today: '2026-10-18',
      );
      expect(p.passedDays, 0);
      expect(p.remainDays, p.totalDays);
      expect(p.finished, isFalse);
    });

    test('已经过完的月份：剩余 0 天，不除以 0', () {
      final p = Pacing.of(
        month: '2026-09',
        totalCents: 300000,
        usedCents: 320000,
        today: '2026-10-18',
      );
      expect(p.finished, isTrue);
      expect(p.remainDays, 0);
      expect(p.canSpendPerDayCents, 0);
      expect(p.sentence, contains('已结束'));
      expect(p.sentence, contains('超支'));
    });
  });

  group('金额口径', () {
    test('计划日均向下取整', () {
      // 100 元 / 31 天 = 3.22 元，向下取整到 3 元
      final p = at('2026-10-01', total: 10000, used: 0);
      expect(p.perDayBudgetCents, 322);
    });

    test('每天可花也是向下取整', () {
      final p = at('2026-10-11', total: 300000, used: 124000);
      // 剩 1760 元 / 21 天 = 83.8 元
      expect(p.leftCents, 176000);
      expect(p.canSpendPerDayCents, 8380);
    });

    test('超支时 每天可花 = 0，不出现负数', () {
      final p = at('2026-10-11', total: 100000, used: 120000);
      expect(p.overCents, 20000);
      expect(p.canSpendPerDayCents, 0);
    });

    test('没设预算：不算比例也不崩', () {
      final p = at('2026-10-11', total: null, used: 50000);
      expect(p.hasBudget, isFalse);
      expect(p.usedRatio, 0);
      expect(p.perDayBudgetCents, 0);
      expect(p.canSpendPerDayCents, 0);
      expect(p.sentence, contains('还没设预算'));
    });
  });

  group('一句人话', () {
    test('花得比计划快：给预测超支和每天上限', () {
      final p = at('2026-10-11', total: 300000, used: 124000);
      expect(p.perDayRealCents, greaterThan(p.perDayBudgetCents));
      expect(p.projectedOverCents, greaterThan(0));
      expect(p.sentence, contains('大概会超支'));
      expect(p.sentence, contains('以内就没事'));
    });

    test('花得比计划慢：说节奏正常', () {
      final p = at('2026-10-11', total: 300000, used: 30000);
      expect(p.projectedOverCents, 0);
      expect(p.sentence, startsWith('节奏正常'));
    });

    test('已经超支：先报数字再提醒', () {
      final p = at('2026-10-11', total: 100000, used: 120000);
      expect(p.sentence, contains('已经超支'));
      expect(p.sentence, contains('21 天'));
    });
  });
}
