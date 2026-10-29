// 「预计达成时间」纯函数的自检。
//
// 这条逻辑的价值全在**边界**上：已达成 / 一笔没存 / 取比存多 / 速率极慢。
// 四种情况给错任何一种，用户看到的都是一个像 bug 的日期，而不是一句解释。
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/goal_projection.dart';
import 'package:ledger/data/models.dart';

GoalFlow flow(String date, int cents) =>
    GoalFlow(id: 1, goalId: 1, date: date, cents: cents);

void main() {
  group('projectGoal 的四种结局', () {
    test('已存够 → done，不给日期', () {
      final r = projectGoal(
        targetCents: 100000,
        savedCents: 100000,
        flows: [flow('2026-10-01', 100000)],
        today: '2026-10-29',
      );
      expect(r.state, GoalEtaState.done);
      expect(r.etaMonth, isNull);
    });

    test('一条流水都没有 → noFlow（不是「永远达不成」）', () {
      final r = projectGoal(
        targetCents: 100000,
        savedCents: 30000, // 老数据：有已存额但没有流水
        flows: const [],
        today: '2026-10-29',
      );
      expect(r.state, GoalEtaState.noFlow);
      expect(r.hasEta, isFalse);
    });

    test('取出的比存进的多 → noRate，且速率原样带出来（负数）', () {
      final r = projectGoal(
        targetCents: 100000,
        savedCents: 5000,
        flows: [flow('2026-09-01', 20000), flow('2026-10-05', -30000)],
        today: '2026-10-29',
      );
      expect(r.state, GoalEtaState.noRate);
      expect(r.monthlyRateCents, lessThan(0));
    });

    test('按这个速率要 50 年以上 → unreachable，不说「预计 2150 年」', () {
      final r = projectGoal(
        targetCents: 1200000000, // 1200 万元
        savedCents: 0,
        flows: [flow('2026-10-01', 1000)], // 每月 10 元
        today: '2026-10-29',
      );
      expect(r.state, GoalEtaState.unreachable);
      expect(r.hasEta, isFalse);
    });
  });

  group('速率与月份外推', () {
    test('单月一笔：窗口按 1 个月算，向上取整', () {
      // 月存 200 元、还差 1000 元 → 5 个月 → 2026-10 + 5 = 2027-03
      final r = projectGoal(
        targetCents: 120000,
        savedCents: 20000,
        flows: [flow('2026-10-01', 20000)],
        today: '2026-10-29',
      );
      expect(r.state, GoalEtaState.estimated);
      expect(r.monthlyRateCents, 20000);
      expect(r.monthsNeeded, 5);
      expect(r.etaMonth, '2027-03');
    });

    test('跨 3 个月：净额 ÷ 3，不是 ÷ 流水笔数', () {
      // 2026-08 / 09 / 10 三个月，共存 300 元 → 月均 100 元
      final r = projectGoal(
        targetCents: 100000,
        savedCents: 0,
        flows: [
          flow('2026-08-15', 30000),
          flow('2026-09-20', 0), // 0 元流水不该改变窗口，也不该当一笔
        ],
        today: '2026-10-29',
      );
      expect(r.monthlyRateCents, 10000); // 30000 / 3
      expect(r.monthsNeeded, 10); // 100000 / 10000
      expect(r.etaMonth, '2027-08');
    });

    test('除不尽时向上取整（宁可晚一个月，不要早一个月）', () {
      // 还差 100000，月存 30000 → 3.33 个月 → 4 个月
      final r = projectGoal(
        targetCents: 100000,
        savedCents: 0,
        flows: [flow('2026-10-01', 30000)],
        today: '2026-10-29',
      );
      expect(r.monthsNeeded, 4);
      expect(r.etaMonth, '2027-02');
    });

    test('同月内跨日不影响窗口（按月份算，不按天）', () {
      final r = projectGoal(
        targetCents: 100000,
        savedCents: 0,
        flows: [flow('2026-10-01', 50000)],
        today: '2026-10-31',
      );
      expect(r.monthlyRateCents, 50000); // 窗口 = 1，不是 0
    });
  });
}
