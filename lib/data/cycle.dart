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

/// 周期条上的文案：`10-15 至 11-14`
///
/// 起止之间用「至」而不是箭头：这两个日期是**一段区间**，不是「从 A 流向 B」，
/// 箭头会让人以为有什么在往右边转移。
String cycleLabel(String from, String to) =>
    '${shortYmd(from)} 至 ${shortYmd(to)}';

/// 页头之下的**大号**区间文案：`10月1日 – 10月31日`
///
/// 区间文案升到 20px 之后，原来的 `10-01 至 10-31` 读起来有两个问题：
/// ① 20px 的数字容易被当成金额或日期里的「10.01」；② 两个短横加一个「至」，
/// 一行里三条分隔符打架。中文月日最没有歧义。
///
/// 跨年的一期也不带年份 —— 一年只发生一次，不值得为它给 360 天的标签都加年份。
/// 卡内紧凑位（概览卡）仍用 [periodLabel]：那里宽度只有一行的一小截。
String longRangeLabel(String from, String to) =>
    '${_cnYmd(from)} – ${_cnYmd(to)}';

String _cnYmd(String ymd) {
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  return '${int.tryParse(p[1]) ?? 0}月${int.tryParse(p[2]) ?? 0}日';
}

/// 明细页概览卡上的文案：`10.01 至 10.31`
///
/// 和 [cycleLabel] 的差别只有两处，但读起来轻很多：
/// - 连字符换成 `·` 样式的点分（10.01），数字之间不再有两条横线打架
/// - 「至」照旧，和周期条保持同一个词
String periodLabel(String from, String to) => '${dotYmd(from)} 至 ${dotYmd(to)}';

/// `2026-10-15` → `10-15`。UI 里所有「期」的文案都用这个，别各处自己截。
String shortYmd(String ymd) {
  final p = ymd.split('-');
  return p.length == 3 ? '${p[1]}-${p[2]}' : ymd;
}

/// `2026-10-15` → `10.15`，给 [periodLabel] 用
String dotYmd(String ymd) {
  final p = ymd.split('-');
  return p.length == 3 ? '${p[1]}.${p[2]}' : ymd;
}

/// 日历能翻的范围（`YYYY-MM`，含两端）。
///
/// 上下界都是以**今天**为基准往前/往后数的，不是写死的某一年：
/// 2026-10 打开是 2023-11…2027-01，到了 2027-02 再打开就是 2024-03…2027-05。
/// 所以「只能翻到 27 年 1 月」不是上限，是这个月的上限。
///
/// [anchorYm] 是打开时要停住的那个月，必须落在范围里 —— 翻到很旧的账
/// （比如账单日是两年前某月）时，下界会跟着 [anchorYm] 一起往前挪。
(String, String) calendarRange(
  String anchorYm, {
  DateTime? now,
  int back = 23,
  int forward = 3,
}) {
  final thisYm = Fmt.month(now ?? DateTime.now());
  final earlier = thisYm.compareTo(anchorYm) < 0 ? thisYm : anchorYm;
  final later = thisYm.compareTo(anchorYm) > 0 ? thisYm : anchorYm;
  final oldest = Fmt.shiftMonth(earlier, -back);
  var newest = Fmt.shiftMonth(later, forward);
  if (newest.compareTo(anchorYm) < 0) newest = anchorYm;
  return (oldest, newest);
}
