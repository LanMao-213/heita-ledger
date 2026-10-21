import 'package:flutter/material.dart';

/// 视觉 token 的唯一容器：22 个语义色 + 10 档图表色阶。
///
/// **整个 App 只有这个文件允许出现十六进制色值。** `lib/ui/` 下必须一律通过
/// `context.pal.xxx` 取色（由 `tools/check_theme_hardcode.sh` 强制）——否则切配色时
/// 写死的那一块不会变，就是原版「457 处 `static const` 颜色、编译期定死」的病根。
///
/// 两套配色的定位（见架构设计 §6.1）：
/// - [paletteInk]（柏油黑塔）：极简黑白灰 + 单一红色警示。纸感、克制、数字优先。
/// - [paletteAurora]（露露缇雅·泽金）：明亮天空 × 暖白 × 绯红 × 天青。清透低饱和。
///
/// V1 只有浅色。深色模式留了 [Brightness] 参数（见 `buildTheme`），不在本版做。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.id,
    required this.label,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunk,
    required this.heroBg,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.inkWash,
    required this.over,
    required this.overSoft,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.todayMark,
    required this.shadow,
    required this.onInverse,
    required this.avatarBg,
    required this.navActive,
    required this.chart,
  });

  /// 落库用的稳定标识：`setting['theme.palette']`。**不许改**（老库会读不到）。
  final String id;

  /// 界面上给人看的中文名。
  final String label;

  /// 页面底。
  final Color bg;

  /// 卡面 / 面板面。与 [bg] 同色时靠 1px [line] 分层。
  final Color surface;

  /// 卡内次级面（输入底 / 未选中胶囊 / 键帽）。**必须比 [surface] 深，也比 [bg] 深。**
  final Color surfaceAlt;

  /// 更弱的面（灰底一段说明文字）。
  final Color surfaceSunk;

  /// 概览卡底。
  final Color heroBg;

  /// 1px 描边 / 分割线。
  final Color line;

  /// 稍强分隔。
  final Color lineStrong;

  /// 主文字 / 标题 / 进度填充。
  final Color ink;

  /// 次要文字。
  final Color ink2;

  /// 辅助文字，**借贷金额的中性色**。
  final Color ink3;

  /// 占位 / 弱分割，不承担可读性。
  final Color ink4;

  /// 轮盘选中行遮罩（带 alpha 的深色）。
  final Color inkWash;

  /// 超支 / 危险按钮。
  final Color over;

  /// 超支浅底。
  final Color overSoft;

  /// 进度填充 / 选中指示。
  final Color accent;

  /// 压在 [accent] 上的字。
  final Color onAccent;

  /// 天青柔底 / 标签底。只能当底，上面压 [ink]。
  final Color accentSoft;

  /// 日历「今天」圆点。
  final Color todayMark;

  /// 阴影基色（与 alpha 组合使用，见 `Elev`）。
  final Color shadow;

  /// 反白字（toast / 中央＋浮钮上的字）。
  final Color onInverse;

  /// 分类图标圆底。
  final Color avatarBg;

  /// 底栏选中。
  final Color navActive;

  /// 图表色阶，**严格由深到浅**，索引 0 = 金额最大的那一档。
  ///
  /// 两套都由「深 → 近白」等距取值，保证「黑白色盲也能看出主次」这条行为在两套里都成立。
  final List<Color> chart;

  /// 图表色阶档数。饼图 / 排行 / 双柱共用，改这里等于改所有图。
  static const int chartSteps = 10;

  /// 所有可选配色，顺序即「我的 → 配色」里的展示顺序。
  static List<AppPalette> get all => <AppPalette>[paletteInk(), paletteAurora()];

  /// 按落库 id 取配色。认不出（老库脏值 / 未来新增后回滚）→ 回落默认的 ink，
  /// **不抛异常**：一个配色 id 不认识不该让用户开不了 App。
  static AppPalette byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return paletteInk();
  }

  @override
  AppPalette copyWith({
    String? id,
    String? label,
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceSunk,
    Color? heroBg,
    Color? line,
    Color? lineStrong,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? ink4,
    Color? inkWash,
    Color? over,
    Color? overSoft,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? todayMark,
    Color? shadow,
    Color? onInverse,
    Color? avatarBg,
    Color? navActive,
    List<Color>? chart,
  }) {
    return AppPalette(
      id: id ?? this.id,
      label: label ?? this.label,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceSunk: surfaceSunk ?? this.surfaceSunk,
      heroBg: heroBg ?? this.heroBg,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      ink4: ink4 ?? this.ink4,
      inkWash: inkWash ?? this.inkWash,
      over: over ?? this.over,
      overSoft: overSoft ?? this.overSoft,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      todayMark: todayMark ?? this.todayMark,
      shadow: shadow ?? this.shadow,
      onInverse: onInverse ?? this.onInverse,
      avatarBg: avatarBg ?? this.avatarBg,
      navActive: navActive ?? this.navActive,
      chart: chart ?? this.chart,
    );
  }

  /// 逐字段插值。`MaterialApp` 内部的 `AnimatedTheme` 会调它做 200ms 配色过渡
  /// （见 `Dur.theme`），所以**每个 token 都必须在这里出现**，漏一个就会有一块
  /// 颜色在切换瞬间跳变。
  @override
  AppPalette lerp(covariant ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    if (t <= 0) return this;
    if (t >= 1) return other;

    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;

    final chartLength = chart.length < other.chart.length
        ? chart.length
        : other.chart.length;
    return AppPalette(
      // id / label 是标识不是颜色，切换过程中取目标值（否则中途拿到的 id 无意义）
      id: other.id,
      label: other.label,
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      surfaceSunk: mix(surfaceSunk, other.surfaceSunk),
      heroBg: mix(heroBg, other.heroBg),
      line: mix(line, other.line),
      lineStrong: mix(lineStrong, other.lineStrong),
      ink: mix(ink, other.ink),
      ink2: mix(ink2, other.ink2),
      ink3: mix(ink3, other.ink3),
      ink4: mix(ink4, other.ink4),
      inkWash: mix(inkWash, other.inkWash),
      over: mix(over, other.over),
      overSoft: mix(overSoft, other.overSoft),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentSoft: mix(accentSoft, other.accentSoft),
      todayMark: mix(todayMark, other.todayMark),
      shadow: mix(shadow, other.shadow),
      onInverse: mix(onInverse, other.onInverse),
      avatarBg: mix(avatarBg, other.avatarBg),
      navActive: mix(navActive, other.navActive),
      chart: <Color>[
        for (int i = 0; i < chartLength; i++) mix(chart[i], other.chart[i]),
      ],
    );
  }

  /// 全部 token 的 (名字, 颜色) 对。测试用：`palette_contract_test` 靠它遍历
  /// 22 个 token 断言对比度，避免「加了一个 token 忘了写断言」。
  Map<String, Color> get tokens => <String, Color>{
    'bg': bg,
    'surface': surface,
    'surfaceAlt': surfaceAlt,
    'surfaceSunk': surfaceSunk,
    'heroBg': heroBg,
    'line': line,
    'lineStrong': lineStrong,
    'ink': ink,
    'ink2': ink2,
    'ink3': ink3,
    'ink4': ink4,
    'inkWash': inkWash,
    'over': over,
    'overSoft': overSoft,
    'accent': accent,
    'onAccent': onAccent,
    'accentSoft': accentSoft,
    'todayMark': todayMark,
    'shadow': shadow,
    'onInverse': onInverse,
    'avatarBg': avatarBg,
    'navActive': navActive,
  };

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.id == id &&
      other.bg == bg &&
      other.surface == surface &&
      other.surfaceAlt == surfaceAlt &&
      other.ink == ink &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(id, bg, surface, surfaceAlt, ink, accent);

  @override
  String toString() => 'AppPalette($id)';
}

/// 柏油黑塔（默认）。色值照抄架构设计 §6.2，**不许自己调色**。
const AppPalette _ink = AppPalette(
  id: 'ink',
  label: '柏油黑塔',
  bg: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFF4F5F6),
  surfaceSunk: Color(0xFFFAFAFB),
  heroBg: Color(0xFFF4F5F6),
  line: Color(0xFFE8EAEC),
  lineStrong: Color(0xFFDFE2E5),
  ink: Color(0xFF14161A),
  ink2: Color(0xFF5C626B),
  ink3: Color(0xFF9AA0A8),
  ink4: Color(0xFFC4C9CF),
  inkWash: Color(0x0F14161A),
  over: Color(0xFFA3231A),
  overSoft: Color(0xFFFFF1EF),
  accent: Color(0xFF14161A),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFF4F5F6),
  todayMark: Color(0xFF14161A),
  shadow: Color(0xFF14161A),
  onInverse: Color(0xFFFFFFFF),
  avatarBg: Color(0xFFF4F5F6),
  navActive: Color(0xFF14161A),
  chart: <Color>[
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
  ],
);

/// 露露缇雅·泽金。色值照抄架构设计 §6.2。
const AppPalette _aurora = AppPalette(
  id: 'aurora',
  label: '露露缇雅·泽金',
  bg: Color(0xFFEAF3F6),
  surface: Color(0xFFFDFBF8),
  surfaceAlt: Color(0xFFE0EEF1),
  surfaceSunk: Color(0xFFF4F9FB),
  heroBg: Color(0xFFF4EBF0),
  line: Color(0xFFD5E5EA),
  lineStrong: Color(0xFFE1D3DC),
  ink: Color(0xFF4A2C3A),
  ink2: Color(0xFF6E5566),
  ink3: Color(0xFF7E6478),
  ink4: Color(0xFFBC9DB1),
  inkWash: Color(0x14814864),
  over: Color(0xFF814864),
  overSoft: Color(0xFFF6E9EF),
  accent: Color(0xFF3E7A8B),
  onAccent: Color(0xFFFDFBF8),
  accentSoft: Color(0xFF9AC7D3),
  todayMark: Color(0xFF9AC7D3),
  shadow: Color(0xFF4A2C3A),
  onInverse: Color(0xFFFDFBF8),
  avatarBg: Color(0xFFE0EEF1),
  navActive: Color(0xFF3E7A8B),
  chart: <Color>[
    Color(0xFF2F5F6E),
    Color(0xFF3E7A8B),
    Color(0xFF548E9C),
    Color(0xFF6FA3AE),
    Color(0xFF8AB5BE),
    Color(0xFFA3C6CC),
    Color(0xFFB7D4D9),
    Color(0xFFC8E0E4),
    Color(0xFFD8EAED),
    Color(0xFFE7F2F4),
  ],
);

/// 柏油黑塔（默认配色）。
AppPalette paletteInk() => _ink;

/// 露露缇雅·泽金。
AppPalette paletteAurora() => _aurora;

/// 取当前主题的调色板。
///
/// 这是 `lib/ui/` 里**唯一**允许的取色方式：`context.pal.ink2`。
/// 主题扩展缺失时（只可能发生在没套 `buildTheme` 的裸 `MaterialApp` 里）
/// 回落默认 ink，让界面仍然可读，而不是抛异常白屏。
extension AppPaletteContext on BuildContext {
  AppPalette get pal =>
      Theme.of(this).extension<AppPalette>() ?? paletteInk();
}
