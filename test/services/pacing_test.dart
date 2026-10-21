import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/services/pacing_service.dart';

/// 预算节奏：剩几天 / 每天能花多少 / 会不会超。
///
/// 四条硬边界：`remainDays == 0` 按 1 天、`left <= 0 → 0`、
/// 计划日均**整除**、四种文案状态。
void main() {
  LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

  /// 2026-10 整月（31 天）。
  final Period october = Period(from: d(2026, 10, 1), to: d(2026, 10, 31));

  Pacing of({
    int? total = 310000,
    int used = 0,
    LocalDate? today,
    Period? period,
  }) => Pacing.ofRange(
    period: period ?? october,
    totalCents: total,
    usedCents: used,
    today: today ?? d(2026, 10, 1),
  );

  test('① totalDays 现算（28/30/31 都对，不写死 31）', () {
    expect(of().totalDays, 31);
    expect(
      of(period: Period(from: d(2026, 2, 1), to: d(2026, 2, 28))).totalDays,
      28,
    );
    expect(
      of(period: Period(from: d(2026, 4, 1), to: d(2026, 4, 30))).totalDays,
      30,
    );
  });

  test('② passedDays 含今天', () {
    expect(of(today: d(2026, 10, 1)).passedDays, 1);
    expect(of(today: d(2026, 10, 15)).passedDays, 15);
    expect(of(today: d(2026, 10, 31)).passedDays, 31);
  });

  test('③ remainDays 含今天；最后一天是 1', () {
    expect(of(today: d(2026, 10, 1)).remainDays, 31);
    expect(of(today: d(2026, 10, 31)).remainDays, 1);
  });

  test('④ 期已过完：remainDays = 0、finished = true', () {
    final Pacing p = of(today: d(2026, 11, 5));
    expect(p.finished, isTrue);
    expect(p.remainDays, 0);
    expect(p.passedDays, 31);
  });

  test('⑤ 还没开始的一期：一天没过、整期都可用', () {
    final Pacing p = of(today: d(2026, 9, 20));
    expect(p.passedDays, 0);
    expect(p.remainDays, 31);
    expect(p.finished, isFalse);
  });

  test('⑥ remainDays == 0 时「每天可花」按 1 天算（不除以 0）', () {
    final Pacing p = of(total: 310000, used: 100000, today: d(2026, 11, 5));
    expect(p.remainDays, 0);
    expect(p.canSpendPerDayCents, 210000, reason: '剩 2100 元全算在 1 天里');
  });

  test('⑦ left <= 0 → 每天可花 0（超支不出现负数建议）', () {
    expect(of(used: 310000, today: d(2026, 10, 20)).canSpendPerDayCents, 0);
    expect(of(used: 500000, today: d(2026, 10, 20)).canSpendPerDayCents, 0);
  });

  test('⑧ 计划日均整除（310000 / 31 = 10000，1000 / 31 = 32）', () {
    expect(of().perDayBudgetCents, 10000);
    expect(of(total: 1000).perDayBudgetCents, 32);
    expect(of(total: null).perDayBudgetCents, 0);
  });

  test('⑨ 实际日均 = 已花 ~/ 已过天数（整除）', () {
    expect(of(used: 1000, today: d(2026, 10, 3)).perDayRealCents, 333);
    expect(of(used: 1000, today: d(2026, 9, 1)).perDayRealCents, 0);
  });

  test('⑩ usedRatio 不截断（超支时 > 1）', () {
    expect(of(used: 155000, today: d(2026, 10, 10)).usedRatio, 0.5);
    expect(of(used: 620000, today: d(2026, 10, 10)).usedRatio, 2.0);
    expect(of(total: null).usedRatio, 0);
    expect(of(total: 0).usedRatio, 0, reason: '额度 0 不做除法');
  });

  test('⑪ 超支金额与 projectedOver', () {
    final Pacing p = of(total: 310000, used: 400000, today: d(2026, 10, 10));
    expect(p.overCents, 90000);
    expect(p.projectedOverCents, greaterThan(0));
    expect(of(total: null).projectedOverCents, 0);
  });

  test('⑫ 四种文案状态', () {
    // 1) 没设预算
    expect(of(total: null).sentence, contains('还没设预算'));
    // 2) 期已结束且还有剩余
    expect(
      of(total: 310000, used: 100000, today: d(2026, 11, 2)).sentence,
      contains('已结束，预算还剩'),
    );
    // 3) 期已结束且超支
    expect(
      of(total: 310000, used: 400000, today: d(2026, 11, 2)).sentence,
      contains('超支'),
    );
    // 4) 期未结束但已超支
    expect(
      of(total: 310000, used: 400000, today: d(2026, 10, 10)).sentence,
      contains('已经超支'),
    );
    // 5) 节奏正常
    expect(
      of(total: 310000, used: 10000, today: d(2026, 10, 2)).sentence,
      contains('节奏正常'),
    );
    // 6) 按现在速度会超
    expect(
      of(total: 310000, used: 300000, today: d(2026, 10, 5)).sentence,
      contains('大概会超支'),
    );
  });
}
