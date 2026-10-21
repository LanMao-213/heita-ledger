import 'package:flutter/foundation.dart';

/// 「哪一天」。无时区、无时分秒，可直接比较、可作 Map 键。
///
/// **为什么不用 `DateTime`**（架构设计 §1.6）：
/// `DateTime.parse('2026-10-16')` 得到的是本地时区午夜，`add(Duration(days: 1))`
/// 在夏令时地区会跨错天；而用户改系统时区/时间在国内是真实场景，原版「回前台补记」
/// 就依赖日期比较。把「日期」和「时刻」彻底分开：业务日期一律 [LocalDate]，
/// `created_at` / `closed_at` 才用 [DateTime]。
@immutable
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  factory LocalDate.fromDateTime(DateTime d) =>
      LocalDate(d.year, d.month, d.day);

  /// 今天（本地时区）。
  static LocalDate today() => LocalDate.fromDateTime(DateTime.now());

  final int year;
  final int month;
  final int day;

  /// 持久层唯一格式：`YYYY-MM-DD`。
  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// `YYYY-MM`（月份键）。
  String get ym =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// 1 = 周一 … 7 = 周日。
  int get weekday => DateTime(year, month, day).weekday;

  DateTime toDateTime() => DateTime(year, month, day);

  /// 只认 `YYYY-MM-DD` / `YYYY/MM/DD` / `YYYYMMDD`；其他一律 `null`（含 2 月 30 日这种非法日）。
  static LocalDate? tryParse(String s) {
    final String t = s.trim();
    if (t.isEmpty) return null;

    int? y;
    int? m;
    int? d;
    if (t.length == 8 && !t.contains('-') && !t.contains('/')) {
      // YYYYMMDD
      y = int.tryParse(t.substring(0, 4));
      m = int.tryParse(t.substring(4, 6));
      d = int.tryParse(t.substring(6, 8));
    } else {
      final List<String> parts = t.split(RegExp('[-/]'));
      if (parts.length != 3) return null;
      y = int.tryParse(parts[0]);
      m = int.tryParse(parts[1]);
      d = int.tryParse(parts[2]);
    }
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1) return null;
    if (d > daysInMonth(y, m)) return null;
    return LocalDate(y, m, d);
  }

  /// 同 [tryParse]，但非法时抛 [FormatException]。
  static LocalDate parse(String s) {
    final LocalDate? d = tryParse(s);
    if (d == null) throw FormatException('不是合法日期：$s');
    return d;
  }

  /// 某月天数。`month` 允许越界（内部 `DateTime` 自动进位）。
  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// 加天数：走日历进位而不是 `Duration`，避免时区/夏令时导致跨错天。
  LocalDate addDays(int n) => LocalDate.fromDateTime(DateTime(year, month, day + n));

  /// 加月份。默认把日号收拢到目标月月末（1-31 + 1 月 → 2-28/29）。
  ///
  /// `clampToMonthEnd: false` 时允许溢出（1-31 + 1 月 → 3-03），
  /// 走 `DateTime` 的自然进位。
  LocalDate addMonths(int n, {bool clampToMonthEnd = true}) {
    final DateTime base = DateTime(year, month + n);
    if (!clampToMonthEnd) {
      return LocalDate.fromDateTime(DateTime(base.year, base.month, day));
    }
    final int last = daysInMonth(base.year, base.month);
    final int targetDay = day > last ? last : day;
    return LocalDate(base.year, base.month, targetDay);
  }

  /// 本月一号。
  LocalDate get firstOfMonth => LocalDate(year, month, 1);

  /// 本月最后一天。
  LocalDate get lastOfMonth => LocalDate(year, month, daysInMonth(year, month));

  /// 相差天数（`this - other`）。
  int diffDays(LocalDate other) =>
      toDateTime().difference(other.toDateTime()).inDays;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  bool operator <(LocalDate other) => compareTo(other) < 0;
  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >(LocalDate other) => compareTo(other) > 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  /// 是否落在 [from]–[to] 之间（含两端）。
  bool isBetween(LocalDate from, LocalDate to) => this >= from && this <= to;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}

/// `2026-10` → 该月一号。非法返回 `null`。
LocalDate? firstDayOfMonth(String ym) {
  final List<String> p = ym.split('-');
  if (p.length != 2) return null;
  final int? y = int.tryParse(p[0]);
  final int? m = int.tryParse(p[1]);
  if (y == null || m == null || m < 1 || m > 12) return null;
  return LocalDate(y, m, 1);
}
