import 'package:flutter/foundation.dart';

import 'local_date.dart';

/// 一期（含头含尾）。`from` 一定是某个账单日，`to` 是下一个账单日的前一天。
@immutable
class Period {
  const Period({required this.from, required this.to});

  final LocalDate from;
  final LocalDate to;

  /// 这一期多少天（28–31 天不等，**不许写死 31**）。
  int get dayCount => to.diffDays(from) + 1;

  bool contains(LocalDate d) => d >= from && d <= to;

  bool get isValid => to >= from;

  String get fromIso => from.iso;
  String get toIso => to.iso;

  /// `10-15 至 11-14`
  String get shortLabel => cycleLabel(this);

  /// `10.15 至 11.14`
  String get dotLabel => periodLabel(this);

  /// `2026-10-15 至 2026-11-14`
  String get label => '${from.iso} 至 ${to.iso}';

  Period copyWith({LocalDate? from, LocalDate? to}) =>
      Period(from: from ?? this.from, to: to ?? this.to);

  @override
  bool operator ==(Object other) =>
      other is Period && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'Period($label)';

  // --------------------------------------------------------------- 口径函数

  /// 账单日 `startDay` 在 `year-month` 里落在几号 —— **短月收拢到月末**（D14）。
  ///
  /// `month` 允许越界（`DateTime` 自动进位），调用方不必先归一化。
  /// 账单日 31 遇 2 月 → 28 / 29 号，这是「期」不会丢天的关键。
  static LocalDate cycleStartIn(int year, int month, int startDay) {
    final int day = startDay.clamp(1, 31);
    final DateTime base = DateTime(year, month);
    final int last = LocalDate.daysInMonth(base.year, base.month);
    return LocalDate(base.year, base.month, day > last ? last : day);
  }

  /// [d] 所在那一期的第一天。**账单日当天算新一期**（`>=`）。
  static LocalDate cycleStartOf(LocalDate d, int startDay) {
    final LocalDate thisMonthStart = cycleStartIn(d.year, d.month, startDay);
    return d < thisMonthStart
        ? cycleStartIn(d.year, d.month - 1, startDay)
        : thisMonthStart;
  }

  /// [d] 所在那一期的区间。
  static Period cycleRange(LocalDate d, int startDay) {
    final LocalDate from = cycleStartOf(d, startDay);
    final LocalDate next = cycleStartIn(from.year, from.month + 1, startDay);
    return Period(from: from, to: next.addDays(-1));
  }

  /// 今天的期。
  static Period current(int startDay) => cycleRange(LocalDate.today(), startDay);

  /// 按「一期」平移，`delta` 为正往后翻。
  ///
  /// **不是「加一个月」**：期长 28–31 天不等，直接把 `from` 加一个月会在 2 月
  /// 附近把落点算到隔壁期去（比如 01-31 那期 +1 月 = 02-28 那期是对的，但
  /// 02-28 那期 +1 月得回到 03-31，不能是 03-28）。
  static Period shiftCycle(Period p, int delta, int startDay) {
    final LocalDate newFrom = cycleStartIn(p.from.year, p.from.month + delta, startDay);
    final LocalDate next = cycleStartIn(newFrom.year, newFrom.month + 1, startDay);
    return Period(from: newFrom, to: next.addDays(-1));
  }

  /// 归属期：这条记录算在哪一期，返回该期第一天。
  ///
  /// [liftToNext] 打开时启用「工资抬期」（规则 R1）：若这笔发生在**同月账单日之前**，
  /// 就并入本月账单日开始的那一期（语义：这笔钱是拿来支撑下一期生活的）。
  ///
  /// 为什么只跟「同月账单日」比、而不是一律 +1 期：
  /// - 10-10 到账（账单日 15）→ 在 09-15 那期里 → 抬到 10-15 ✅
  /// - 10-17 到账 → 已在 10-15 那期里 → 不动 ✅（一律抬会错误推到 11-15）
  /// - 09-20 到账 → 已在 09-15 那期里且不早于 09-15 → 不动 ✅（否则两个月工资挤一期）
  static LocalDate periodStartOf(
    LocalDate d,
    int startDay, {
    bool liftToNext = false,
  }) {
    final Period p = cycleRange(d, startDay);
    if (!liftToNext) return p.from;
    final LocalDate thisMonthStart = cycleStartIn(d.year, d.month, startDay);
    return d < thisMonthStart ? thisMonthStart : p.from;
  }

  /// 抬期会不会真的生效（只有为真时，「这笔算下一期」开关才有意义）。
  ///
  /// 账单日是 1 时**恒为 false**（没有日期早于当月 1 号）—— 这也是「账单日为 1 的
  /// 老用户行为零变化」的保证。
  static bool liftable(LocalDate d, int startDay) =>
      d < cycleStartIn(d.year, d.month, startDay);

  /// 抬期白名单：收入侧只有这三类（用户定稿）。
  static const Set<String> liftableCategoryNames = <String>{'工资', '奖金', '提成'};

  /// 这笔是否命中抬期白名单（收入 + 分类名 ∈ 白名单 + 早于同月账单日）。
  ///
  /// 用手动开关逐笔覆盖时，那**一笔**不看这里；这里只回答「默认该不该抬」。
  static bool shouldLift({
    required bool isIncome,
    required String? categoryName,
    required LocalDate date,
    required int startDay,
  }) {
    if (!isIncome) return false;
    final String name = (categoryName ?? '').trim();
    if (!liftableCategoryNames.contains(name)) return false;
    return liftable(date, startDay);
  }

  /// 某期是否包含今天 —— 「回到本期」这类跳转用。
  ///
  /// 不看 `startDay`：期区间已经算好了，包不包含今天只跟区间本身有关。
  static bool isCurrentCycle(Period p, {LocalDate? today}) =>
      p.contains(today ?? LocalDate.today());
}

/// `2026-10-15` → `10-15`
String shortYmd(LocalDate d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `2026-10-15` → `10.15`
String dotYmd(LocalDate d) =>
    '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

/// 周期条文案：`10-15 至 11-14`
///
/// 用「至」而不是箭头：这两个日期是**一段区间**，不是「从 A 流向 B」，
/// 箭头会让人以为有什么在往右边转移。
String cycleLabel(Period p) => '${shortYmd(p.from)} 至 ${shortYmd(p.to)}';

/// 概览卡文案：`10.01 至 10.31`（点分，读起来更轻）
String periodLabel(Period p) => '${dotYmd(p.from)} 至 ${dotYmd(p.to)}';

/// `2026-10-15` → `2026年10月15日 周四`
String friendlyDate(LocalDate d) {
  const List<String> week = <String>['一', '二', '三', '四', '五', '六', '日'];
  return '${d.year}年${d.month}月${d.day}日 周${week[d.weekday - 1]}';
}

/// `2026-10` → `2026年10月`
String monthLabel(String ym) {
  final List<String> p = ym.split('-');
  if (p.length != 2) return ym;
  return '${p[0]}年${int.tryParse(p[1]) ?? 0}月';
}
