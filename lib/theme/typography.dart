import 'package:flutter/material.dart';

import 'palette.dart';

/// 字号阶梯（架构设计 §6.3）。
///
/// 11 档，全部**只定字号/字重/行高/字间距**，不含颜色 —— 颜色由调用处给
/// （`pal.ink` / `pal.ink2` …），这样同一档字在卡面上和面板上都能用。
///
/// 字体族**不指定**：交给系统 CJK（HarmonyOS Sans / MiSans / Noto Sans CJK）。
/// 绑字体要打包 1–3MB 字重，且中文 fallback 反而更稳。
///
/// 金额档（[amount] / [amountSm]）必带 [FontFeature.tabularFigures]：
/// 等宽数字，否则列表里逐行金额的小数点会左右跳动。
abstract final class Ts {
  /// 概览卡主数字、净资产大数字。
  static const TextStyle hero = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    height: 1.10,
    letterSpacing: -0.6,
  );

  /// 预算卡大数字、往来摘要。
  static const TextStyle heroSm = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.4,
  );

  /// 页面标题、AppBar。
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.2,
  );

  /// 段落标题。
  static const TextStyle section = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.30,
  );

  /// 正文、行标题。
  static const TextStyle body = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// 副行、说明。
  static const TextStyle body2 = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// 弱说明、日期头。
  static const TextStyle caption = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.40,
  );

  /// 标签、单位。
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.35,
    letterSpacing: 0.1,
  );

  /// 「周期」小标签。
  static const TextStyle badge = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0.2,
  );

  /// 列表金额，必带等宽数字。
  static const TextStyle amount = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.20,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// 副行金额，必带等宽数字。
  static const TextStyle amountSm = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.20,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// 全部档位（测试用：断言 11 档、字号严格递增、金额档带等宽数字）。
  static const Map<String, TextStyle> all = <String, TextStyle>{
    'hero': hero,
    'heroSm': heroSm,
    'title': title,
    'section': section,
    'body': body,
    'body2': body2,
    'caption': caption,
    'micro': micro,
    'badge': badge,
    'amount': amount,
    'amountSm': amountSm,
  };
}

/// 把阶梯映射成 Material 的 [TextTheme]，让没显式给样式的 `Text` 也落在同一套阶梯上。
///
/// 只给 `ThemeData` 用；具体组件一律直接引 [Ts] 的常量，避免「取 TextTheme 里的
/// 某个字段、又忘了颜色」的两步走。
TextTheme textThemeOf(AppPalette pal) {
  return TextTheme(
    displayLarge: Ts.hero.copyWith(color: pal.ink),
    displayMedium: Ts.heroSm.copyWith(color: pal.ink),
    headlineMedium: Ts.title.copyWith(color: pal.ink),
    titleMedium: Ts.section.copyWith(color: pal.ink),
    bodyLarge: Ts.body.copyWith(color: pal.ink),
    bodyMedium: Ts.body2.copyWith(color: pal.ink2),
    bodySmall: Ts.caption.copyWith(color: pal.ink3),
    labelLarge: Ts.micro.copyWith(color: pal.ink2),
    labelSmall: Ts.badge.copyWith(color: pal.ink3),
  );
}
