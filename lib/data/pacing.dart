import 'models.dart';

/// 预算节奏。
///
/// 只回答一个问题：**按现在的花法，这个月还撑得住吗？**
///
/// 「已花 / 剩余」是账本语言，用户看完还得自己心算；这里把它翻成
/// 「还剩几天、每天能花多少、照这个速度会不会超」，一句人话说完。
/// 参考 app 的 `planStats()` 就是这个思路，但它的「周期」我们用自然月。
///
/// 全是纯函数/纯派生值，不碰数据库、不碰 UI，可以单独测。
class Pacing {
  const Pacing({
    required this.totalCents,
    required this.usedCents,
    required this.totalDays,
    required this.passedDays,
    required this.remainDays,
    required this.finished,
    this.label = '本期',
  });

  /// 文案里的时间单位：周期视图用「本期」，自然月用「本月」
  final String label;

  /// 预算总额；null 表示这个月没设预算
  final int? totalCents;
  final int usedCents;

  /// 这一期的总天数（周期视图下是 28–31 天不等）
  final int totalDays;

  /// 已经过去的天数（含今天）
  final int passedDays;

  /// 还剩几天（含今天）；已过完为 0
  final int remainDays;

  /// 这个月已经过完（看历史月份时）
  final bool finished;

  factory Pacing.of({
    required String month,
    required int? totalCents,
    required int usedCents,
    String? today,
    String label = '本月',
  }) {
    final year = int.parse(month.substring(0, 4));
    final mon = int.parse(month.substring(5, 7));
    final totalDays = Fmt.daysInMonth(year, mon);
    return Pacing.ofRange(
      from: '$month-01',
      to: '$month-${totalDays.toString().padLeft(2, '0')}',
      totalCents: totalCents,
      usedCents: usedCents,
      today: today,
      label: label,
    );
  }

  /// 按任意区间算节奏（周期归集后，一期是 28–31 天且不固定）。
  ///
  /// [from] / [to] 含两端，期长现算 —— 不能写死 31 天，否则 2 月那期会算出
  /// 「还剩 -3 天」这种数字。
  factory Pacing.ofRange({
    required String from,
    required String to,
    required int? totalCents,
    required int usedCents,
    String? today,
    String label = '本期',
  }) {
    final now = today ?? Fmt.today();
    final totalDays = _daysBetween(from, to) + 1;

    int passed;
    bool finished = false;
    if (now.compareTo(from) < 0) {
      // 还没开始的一期：一天没过，整期都还可用
      passed = 0;
    } else if (now.compareTo(to) > 0) {
      passed = totalDays;
      finished = true;
    } else {
      passed = _daysBetween(from, now) + 1; // 含今天
    }
    final remain = finished ? 0 : (passed == 0 ? totalDays : totalDays - passed + 1);

    return Pacing(
      totalCents: totalCents,
      usedCents: usedCents,
      totalDays: totalDays,
      passedDays: passed,
      remainDays: remain,
      finished: finished,
      label: label,
    );
  }

  bool get hasBudget => totalCents != null;

  int get leftCents => (totalCents ?? 0) - usedCents;

  /// 超支金额；没超就是 0
  int get overCents => leftCents < 0 ? -leftCents : 0;

  /// 花掉的比例（0–1 之外不截断，超支时 >1，供进度条自己处理）
  double get usedRatio =>
      (totalCents == null || totalCents == 0) ? 0 : usedCents / totalCents!;

  /// 计划日均：总预算摊到每一天，向下取整。
  ///
  /// 用整除而不是四舍五入 —— 每天多算 1 分，月底就会超。
  int get perDayBudgetCents =>
      (totalCents == null || totalDays == 0) ? 0 : totalCents! ~/ totalDays;

  /// 实际日均：已花 / 已过天数
  int get perDayRealCents =>
      passedDays == 0 ? 0 : usedCents ~/ passedDays;

  /// 从今天起，每天还能花多少。剩不到一天时按 1 天算，不除以 0。
  int get canSpendPerDayCents {
    if (!hasBudget || leftCents <= 0) return 0;
    final days = remainDays == 0 ? 1 : remainDays;
    return leftCents ~/ days;
  }

  /// 按现在的速度推下去，整月会花多少
  int get projectedCents => perDayRealCents * totalDays;

  /// 按现在的速度推下去，会超支多少（没超就是 0）
  int get projectedOverCents {
    if (totalCents == null) return 0;
    final d = projectedCents - totalCents!;
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

int _daysBetween(String from, String to) {
  final a = DateTime.parse(from);
  final b = DateTime.parse(to);
  return b.difference(a).inDays;
}
