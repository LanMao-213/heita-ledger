import 'package:flutter/material.dart';

/// 设计 token —— 与原型 `记账App/index.html` 的 `:root` 变量一一对应。
///
/// 配色原则（用户确认）：**黑白灰三级 + 红色两档**。
/// 红色只用于「超支」这一件事，不做装饰用途。
abstract final class C {
  /// 主文字 / 强调 / 黑
  static const ink = Color(0xFF14161A);

  /// 次要文字
  static const ink2 = Color(0xFF5C626B);

  /// 辅助文字
  static const ink3 = Color(0xFF9AA0A8);

  /// 占位 / 弱分割
  static const ink4 = Color(0xFFC4C9CF);

  /// 轮盘类选择器的选中行遮罩（ink 的 6% 叠色）
  static const inkWash = Color(0x0F14161A);

  static const bg = Color(0xFFFFFFFF);

  /// 卡片 / 输入底色
  static const bg2 = Color(0xFFF4F5F6);
  static const bg3 = Color(0xFFFAFAFB);
  static const line = Color(0xFFE8EAEC);
  static const line2 = Color(0xFFDFE2E5);

  /// 超支警示 · 深红（用在浅色底上，保证对比度）
  static const over = Color(0xFFA3231A);

  /// 超支警示 · 亮红（用在深色底上）
  static const overD = Color(0xFFE8493A);

  /// 原型里手机机身外的舞台底色，仅调试用
  static const stage = Color(0xFFE8EAEF);
}

/// 图表灰阶：按重要度从深到浅，越次要越淡。十档足够覆盖分类饼图。
const List<Color> kMono = [
  Color(0xFF14161A),
  Color(0xFF2E343C),
  Color(0xFF474E58),
  Color(0xFF616874),
  Color(0xFF7B8390),
  Color(0xFF949CA8),
  Color(0xFFAAB1BC),
  Color(0xFFBCC2CC),
  Color(0xFFCDD2D8),
  Color(0xFFDCE0E4),
];

/// 圆角
abstract final class R {
  static const sm = 9.0;
  static const md = 13.0;
  static const card = 16.0;
  static const lg = 20.0;
}

/// 间距
abstract final class S {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

/// 文本样式。
///
/// 不指定 fontFamily：Android 上交给系统 CJK 字体（华为 HarmonyOS Sans /
/// 小米 MiSans / 原生 Noto Sans CJK），比硬绑某个字体更稳。
abstract final class T {
  /// 大数字（概览页余额）
  static const hero = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    color: C.ink,
    letterSpacing: -0.6,
    height: 1.1,
  );

  static const title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: C.ink,
    letterSpacing: -0.2,
  );

  static const section = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: C.ink,
  );

  static const body = TextStyle(fontSize: 14.5, color: C.ink, height: 1.45);
  static const body2 = TextStyle(fontSize: 13.5, color: C.ink2, height: 1.45);
  static const caption = TextStyle(fontSize: 12.5, color: C.ink3);

  /// 金额（等宽数字，避免列表里数字跳动）
  static const amount = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: C.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const amountSm = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: C.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 全局主题。目前只做浅色（原型即浅色），结构上可直接扩展深色。
ThemeData buildAppTheme() {
  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: C.ink,
      onPrimary: C.bg,
      surface: C.bg,
      onSurface: C.ink,
      error: C.over,
    ),
    dividerColor: C.line,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: C.ink,
      // 从主题自带的 titleLarge 派生，而不是直接用 T.title：
      // T.title 没有 fontFamily，AppBar 会把它当整段样式覆盖掉，
      // 结果标题脱离主题字体族（测试环境里中文会掉成方块）。
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: C.ink,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(R.card)),
      ),
    ),
    // 去掉 Material 3 默认的彩色涟漪，保持黑白灰观感
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: C.ink,
      selectionHandleColor: C.ink,
    ),
  );
}
