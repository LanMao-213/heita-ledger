/// 金额：`int` 分 + [Money] 值类 + [Fmt] 格式化。
///
/// 三条铁律（架构设计 §1.5）：
/// 1. **全程 `int` 分**，禁止与 `double` 混算（`0.1+0.2` 这类误差会累积成真金白银）；
/// 2. 键盘表达式内部可以用 `double`，但**只在最后 `(v*100).round()` 取整一次**；
/// 3. 显示一律走 [Fmt]，不许各处自己拼千分位。
library;

import 'package:flutter/foundation.dart';

/// 金额值类。单位恒为「分」。
///
/// 为什么要有这个类而不是到处传 `int`：`int` 没法阻止「元」和「分」混着传
/// （原版 Excel 导出是元、JSON 备份是分，两个方向都靠人记着）。有了类型，
/// 至少签名上能看出来。
@immutable
class Money implements Comparable<Money> {
  const Money(this.cents);

  final int cents;

  static const Money zero = Money(0);

  /// 上限 ≈ ¥99.99 亿，与键盘（`calc_service`）的上限同一个数。
  static const int maxAbsCents = 999999999999;

  /// 分 → 元（仅用于展示与 Excel 导出，不要拿它参与计算）
  double get yuanValue => cents / 100.0;

  bool get isZero => cents == 0;
  bool get isNegative => cents < 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);
  Money operator *(int n) => Money(cents * n);
  Money abs() => Money(cents.abs());

  /// 是否在上限内（键盘与 Excel 导入都要判）。
  bool get isWithinLimit => cents.abs() <= maxAbsCents;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  /// 「1,234.56」/「+1,234.56」/「1,234」
  String format({bool sign = false, bool trimZero = false, bool compact = false}) {
    if (compact) return Fmt.compact(cents);
    return Fmt.money(cents, sign: sign, trimZero: trimZero);
  }

  /// 「1,234.56」/「¥12」→ 分。非法返回 `null`（**与 0 区分**）。
  static Money? tryParseYuan(String s) {
    final String cleaned = s.trim().replaceAll('¥', '').replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    final double? d = double.tryParse(cleaned);
    if (d == null) return null;
    return Money((d * 100).round());
  }

  /// 非法返回 [zero]。导入路径用（与 `Fmt.parseCents` 完全一致的口径）。
  static Money parseYuanOrZero(String s) => tryParseYuan(s) ?? zero;

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money($cents)';
}

/// 金额与日期的统一格式约定。
///
/// 日期相关（`YYYY-MM-DD`、按月分组）在 `local_date.dart` / `period.dart`，
/// 这里只管金额 —— 两件事混在一个类里，改一处很容易碰坏另一处。
abstract final class Fmt {
  /// 分 → 「1,234.56」。`sign` 给正数加 `+`；`trimZero` 时整数不带 `.00`。
  static String money(int cents, {bool sign = false, bool trimZero = false}) {
    final bool neg = cents < 0;
    final int v = cents.abs();
    final int yuan = v ~/ 100;
    final int fen = v % 100;

    final StringBuffer buf = StringBuffer();
    final String s = yuan.toString();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }

    String out = '$buf.${fen.toString().padLeft(2, '0')}';
    if (trimZero && fen == 0) out = buf.toString();

    if (neg) return '-$out';
    if (sign && cents > 0) return '+$out';
    return out;
  }

  /// 分 → 「¥1,234.56」
  static String yuan(int cents, {bool sign = false}) =>
      '¥${money(cents, sign: sign)}';

  /// 分 → 紧凑写法「1.2万」「3,456」，用于卡片上的大数字。
  static String compact(int cents) {
    final double yuan = cents / 100.0;
    if (yuan.abs() >= 10000) {
      final double w = yuan / 10000.0;
      final String s = w.toStringAsFixed(w.abs() >= 100 ? 0 : 1);
      return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}万';
    }
    return money(cents, trimZero: true, sign: true);
  }

  /// 元字符串 → 分，非法返回 **0**（导入路径，与 v1 行为一致）。
  static int parseCents(String input) {
    final String s = input.trim().replaceAll('¥', '').replaceAll(',', '');
    if (s.isEmpty) return 0;
    final double? d = double.tryParse(s);
    if (d == null) return 0;
    return (d * 100).round();
  }

  /// `1234` → `1,234`（千分位，不带小数）。用于笔数、天数这类整数。
  static String count(int n) {
    final bool neg = n < 0;
    final String s = n.abs().toString();
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return neg ? '-$buf' : buf.toString();
  }
}
