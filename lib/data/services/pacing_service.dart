import '../../core/local_date.dart';
import '../../core/money.dart';
import '../../core/period.dart';

/// 预算节奏：**按现在的花法，这一期还撑得住吗？**
///
/// 「已花 / 剩余」是账本语言，用户看完还得自己心算；这里把它翻成
/// 「还剩几天、每天能花多少、照这个速度会不会超」，一句人话说完。
///
/// 全是派生值，不碰数据库、不碰 UI。
class Pacing {
  const Pacing({
    required this.period,
    required this.totalCents,
    required this.usedCents,
    required this.today,
    this.label = '本期',
  });

  /// 按一期算（周期视图）。
  ///
  /// [from]/[to] 含两端，期长**现算** —— 不能写死 31 天，否则 2 月那期会算出
  /// 「还剩 -3 天」这种数字。
  factory Pacing.ofRange({
    required Period period,
    required int? totalCents,
    required int usedCents,
    LocalDate? today,
    String label = '本期',
  }) {
    return Pacing(
      period: period,
      totalCents: totalCents,
      usedCents: usedCents,
      today: today ?? LocalDate.today(),
      label: label,
    );
  }

  final Period period;

  /// 预算总额；`null` 表示这一期没设预算。
  final int? totalCents;
  final int usedCents;
  final LocalDate today;

  /// 文案里的时间单位：周期视图用「本期」，自然月用「本月」。
  final String label;

  int get totalDays => period.dayCount;

  /// 已经过去的天数（含今天）；还没开始 = 0。
  int get passedDays {
    if (today < period.from) return 0;
    if (today > period.to) return totalDays;
    return today.diffDays(period.from) + 1;
  }

  /// 这一期是否已经过完（看历史期时）。
  bool get finished => today > period.to;

  /// 还剩几天（含今天）；已过完 = 0。
  ///
  /// 还没开始的一期返回整期天数（整期都还可用）。
  int get remainDays {
    if (finished) return 0;
    if (today < period.from) return totalDays;
    return totalDays - passedDays + 1;
  }

  bool get hasBudget => totalCents != null;

  int get leftCents => (totalCents ?? 0) - usedCents;

  /// 超支金额；没超就是 0。
  int get overCents => leftCents < 0 ? -leftCents : 0;

  /// 花掉的比例（**不截断**，超支时 > 1，界面自己 clamp）。
  double get usedRatio {
    final int? total = totalCents;
    if (total == null || total == 0) return 0;
    return usedCents / total;
  }

  /// 计划日均：总预算摊到每一天，**整除**（向下取整）。
  ///
  /// 用整除而不是四舍五入 —— 每天多算 1 分，月底就会超。
  int get perDayBudgetCents =>
      (totalCents == null || totalDays == 0) ? 0 : totalCents! ~/ totalDays;

  /// 实际日均：已花 / 已过天数。
  int get perDayRealCents => passedDays == 0 ? 0 : usedCents ~/ passedDays;

  /// 从今天起每天还能花多少。
  ///
  /// 两条边界：`left <= 0 → 0`；`remainDays == 0 → 按 1 天算`（不除以 0）。
  int get canSpendPerDayCents {
    if (!hasBudget || leftCents <= 0) return 0;
    final int days = remainDays == 0 ? 1 : remainDays;
    return leftCents ~/ days;
  }

  /// 按现在的速度推下去，整期会花多少。
  int get projectedCents => perDayRealCents * totalDays;

  /// 按现在的速度推下去会超多少（没超 = 0）。
  int get projectedOverCents {
    final int? total = totalCents;
    if (total == null) return 0;
    final int d = projectedCents - total;
    return d > 0 ? d : 0;
  }

  /// 一句人话。四种状态，读完就知道下一步该干嘛。
  String get sentence {
    if (!hasBudget) {
      return '还没设预算。设一个上限，就能算出每天还能花多少。';
    }
    if (finished) {
      return leftCents >= 0
          ? '$label已结束，预算还剩 ${Fmt.money(leftCents)}。'
          : '$label已结束，超支 ${Fmt.money(overCents)}。';
    }
    if (leftCents < 0) {
      return '已经超支 ${Fmt.money(overCents)}，接下来 $remainDays 天要悠着点。';
    }
    if (projectedOverCents > 0 && perDayRealCents > perDayBudgetCents) {
      return '按现在的节奏，$label大概会超支 ${Fmt.money(projectedOverCents)}。'
          '往后每天控制在 ${Fmt.money(canSpendPerDayCents)} 以内就没事。';
    }
    return '节奏正常，$label还剩 ${Fmt.money(leftCents)}，'
        '平均每天可以花 ${Fmt.money(canSpendPerDayCents)}。';
  }
}
