import 'package:flutter/material.dart';

import 'palette.dart';
import 'typography.dart';

/// 间距（架构设计 §6.4）。页面左右内边距 16，卡片内 14。
abstract final class S {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// 页面左右内边距。
  static const double page = 16;

  /// 卡片内边距。
  static const double card = 14;

  /// 列表行最小高度（带副行 64、明细行 60）。
  static const double rowMin = 56;
  static const double rowTwoLine = 64;
  static const double rowTxn = 60;

  /// 触控目标最小值（chip 用 padding 撑，不缩小点击区）。
  static const double touch = 44;
}

/// 圆角。
abstract final class R {
  /// chip / 键帽。
  static const double sm = 8;

  /// 小卡 / 输入框。
  static const double md = 12;

  /// 主卡。
  static const double card = 16;

  /// 面板顶角 / 大卡。
  static const double lg = 20;

  /// 胶囊。
  static const double pill = 999;

  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rCard = BorderRadius.all(Radius.circular(card));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
}

/// 阴影。策略：**描边优先、阴影次之**，同屏阴影不超过 2 层。
///
/// 阴影颜色必须来自 [AppPalette.shadow]，否则切配色后阴影还是黑的。
abstract final class Elev {
  /// 白卡压在浅底上。
  static List<BoxShadow> card(AppPalette pal) => <BoxShadow>[
    BoxShadow(
      color: pal.shadow.withValues(alpha: 0.06),
      blurRadius: 10,
      offset: const Offset(0, 1),
    ),
  ];

  /// 底部面板。
  static List<BoxShadow> sheet(AppPalette pal) => <BoxShadow>[
    BoxShadow(
      color: pal.shadow.withValues(alpha: 0.12),
      blurRadius: 28,
      offset: const Offset(0, -6),
    ),
  ];

  /// 中央「记一笔」浮钮（外加 3px bg 描边，见 `HomeShell`）。
  static List<BoxShadow> fab(AppPalette pal) => <BoxShadow>[
    BoxShadow(
      color: pal.shadow.withValues(alpha: 0.18),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
}

/// 动效时长。
abstract final class Dur {
  static const Duration instant = Duration.zero;

  /// 按压反馈。
  static const Duration micro = Duration(milliseconds: 80);

  /// 面板展开收起。
  static const Duration size = Duration(milliseconds: 150);

  /// 配色插值（`AnimatedTheme` 用的就是这个数）。
  static const Duration theme = Duration(milliseconds: 200);

  /// 底部面板进/出。
  static const Duration sheet = Duration(milliseconds: 240);

  /// 翻页 / 翻期。
  static const Duration page = Duration(milliseconds: 260);

  /// 双击判定窗口。
  static const Duration dblTap = Duration(milliseconds: 300);
}

/// 缓动。一律 `easeOutCubic`；只有 sheet 进出对称性不同（进 easeOut、出 easeIn）。
abstract final class Ease {
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// 组装 [ThemeData]。
///
/// [brightness] 是**预留参数**：V1 只做浅色，但结构上必须能吃深色，
/// 否则将来加第三套深色配色要改所有调用点（见架构设计 §10-Q3）。
///
/// 所有颜色都从 [pal] 来，函数内**不出现任何色值字面量**。
ThemeData buildTheme(AppPalette pal, Brightness brightness) {
  // 必须用显式构造函数并把 brightness 传进去：`ColorScheme.light()` 的亮度是常量，
  // 配 `ThemeData(brightness: dark)` 会直接撞断言。V1 只有浅色，但结构上要能吃深色。
  final ColorScheme scheme = ColorScheme(
    brightness: brightness,
    primary: pal.accent,
    onPrimary: pal.onAccent,
    secondary: pal.accentSoft,
    onSecondary: pal.ink,
    error: pal.over,
    onError: pal.onInverse,
    surface: pal.surface,
    onSurface: pal.ink,
    surfaceContainerHighest: pal.surfaceAlt,
    outline: pal.line,
    outlineVariant: pal.lineStrong,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[pal],
    scaffoldBackgroundColor: pal.bg,
    canvasColor: pal.surface,
    dividerColor: pal.line,
    splashColor: pal.inkWash,
    highlightColor: pal.surfaceAlt,
    disabledColor: pal.ink4,
    textTheme: textThemeOf(pal),
    iconTheme: IconThemeData(color: pal.ink2, size: 20),
    dividerTheme: DividerThemeData(
      color: pal.line,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: pal.bg,
      surfaceTintColor: pal.bg,
      foregroundColor: pal.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Ts.title.copyWith(color: pal.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: pal.ink,
      contentTextStyle: Ts.body2.copyWith(color: pal.onInverse),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: R.rMd),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: pal.accent,
      foregroundColor: pal.onAccent,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const CircleBorder(),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: pal.ink,
        textStyle: Ts.body,
        minimumSize: const Size(S.touch, S.touch),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pal.accent,
        foregroundColor: pal.onAccent,
        disabledBackgroundColor: pal.surfaceAlt,
        disabledForegroundColor: pal.ink4,
        textStyle: Ts.section,
        minimumSize: const Size(0, 48),
        shape: const RoundedRectangleBorder(borderRadius: R.rMd),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.ink,
        side: BorderSide(color: pal.line),
        textStyle: Ts.body,
        minimumSize: const Size(0, 48),
        shape: const RoundedRectangleBorder(borderRadius: R.rMd),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: pal.accent,
      linearTrackColor: pal.surfaceAlt,
      linearMinHeight: 6,
    ),
    // 中文正文天生比拉丁字母高，Material 默认的视觉密度在这里显得挤。
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
