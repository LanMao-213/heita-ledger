/// 周期（账单日切分）与归属期计算。
///
/// 这个文件只回答三个问题，别处不要再自己算一遍：
/// 1. 一期从哪天到哪天 —— [cycleRange]
/// 2. 怎么往前/往后翻一期 —— [shiftCycle]
/// 3. 一笔记录算在哪一期 —— [periodStartOf]（含工资抬期 D22-R1）
///
/// 全是纯函数，不碰数据库、不碰 UI。这是整件事里最容易算错的部分，
/// 尤其是「9 月 20 日到账的工资不能被抬两期」这种边界。
library;

import 'models.dart';

/// 某月的账单日落在几号，短月收拢到月末。
///
/// 起始日 31 号遇到 2 月 → 28 / 29 号（D14）。[month] 允许超出 1–12，
/// `DateTime` 会自动进位，调用方不必先做归一化。
DateTime cycleStartOf(int year, int month, int startDay) {
  final day = startDay.clamp(1, 31);
  final last = Fmt.daysInMonth(year, month);
  return DateTime(year, month, day > last ? last : day);
}

/// [d] 所在那一期的起止日期（`YYYY-MM-DD`，含头含尾）。
///
/// 账单日当天算**新一期**（用 `>=` 判定），前一天算上一期。
(String from, String to) cycleRange(DateTime d, int startDay) {
  final thisStart = cycleStartOf(d.year, d.month, startDay);
  final from = d.isBefore(thisStart)
      ? cycleStartOf(d.year, d.month - 1, startDay)
      : thisStart;
  final next = cycleStartOf(from.year, from.month + 1, startDay);
  return (Fmt.date(from), Fmt.date(next.subtract(const Duration(days: 1))));
}

/// 按「期」平移，[delta] 为正往后翻。
///
/// 注意是「翻一期」不是「加一个月」：期长 28–31 天不等，直接加月份会在
/// 2 月附近把落点算到隔壁期去。
DateTime shiftCycle(DateTime d, int startDay, int delta) {
  final (from, _) = cycleRange(d, startDay);
  final start = DateTime.parse(from);
  return cycleStartOf(start.year, start.month + delta, startDay);
}

/// [shiftCycle] 的字符串版本，方便直接喂给查询。
String shiftCycleDate(String date, int startDay, int delta) =>
    Fmt.date(shiftCycle(DateTime.parse(date), startDay, delta));

/// 归属期：这条记录算在哪一期，返回该期的第一天（`YYYY-MM-DD`）。
///
/// [liftToNext] 打开时启用「工资抬期」（规则 R1）：若这笔发生在**同月账单日之前**，
/// 就并入本月账单日开始的那一期。语义是「这笔钱是拿来支撑下一期生活的」。
///
/// 为什么只跟「同月账单日」比，而不是一律抬一期：
/// - 10-10 到账（账单日 15）→ 10-10 在 09-15 那期里 → 抬到 10-15 ✅
/// - 10-17 到账 → 已在 10-15 那期里 → 不动 ✅（一律抬会错误地推到 11-15）
/// - 09-20 到账 → 已在 09-15 那期里，且不早于 09-15 → 不动 ✅（否则两个月工资挤进一期）
String periodStartOf(String date, int startDay, {bool liftToNext = false}) {
  final d = DateTime.parse(date);
  final (from, _) = cycleRange(d, startDay);
  if (!liftToNext) return from;

  final thisMonthStart = cycleStartOf(d.year, d.month, startDay);
  return d.isBefore(thisMonthStart) ? Fmt.date(thisMonthStart) : from;
}

/// 这笔记录落在「同月账单日之前」吗 —— 也就是**抬期会真的生效**吗。
///
/// 给 UI 用：只有它返回 true 时，「这笔算下一期」的开关才有意义。
/// 账单日是 1 时恒为 false（没有日期能早于当月 1 号），所以老用户永远看不到抬期。
bool liftable(String date, int startDay) {
  final d = DateTime.parse(date);
  return d.isBefore(cycleStartOf(d.year, d.month, startDay));
}

/// 某期是否包含「今天」——用于「回到本期」这类跳转。
bool isCurrentCycle(String from, String to, {DateTime? now}) {
  final today = Fmt.date(now ?? DateTime.now());
  return today.compareTo(from) >= 0 && today.compareTo(to) <= 0;
}

/// 明细页/周期条上的文案：`10-15 → 11-14`
String cycleLabel(String from, String to) => '${_short(from)} → ${_short(to)}';

/// `2026-10-15` → `10-15`
String _short(String ymd) {
  final p = ymd.split('-');
  return p.length == 3 ? '${p[1]}-${p[2]}' : ymd;
}
