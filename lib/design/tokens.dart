import 'package:flutter/material.dart';

/// 设计 token —— 单套「纸墨」色板。
///
/// 1.4.5 曾经做过一套「编译期双配色」（`--dart-define=HEITA=1` 出露露缇雅·泽金版），
/// 已整体移除：那套做法的代价是每个 token 都要维护两个值、每条界面改动都要验两遍，
/// 而实际用的人只会装一个包。1.4.6 起只有这一套，方向是**纸墨** ——
/// 纸白底、暖灰墨字、暖灰描边，不引入装饰色。
///
/// 为什么仍然全部是 `static const`：
/// 全仓库 457 处 `C.xxx` 都写在 `const TextStyle(...)` / `const BoxDecoration(...)`
/// 里。颜色一旦变成运行时 getter，这些 const 构造全部要拆掉，几百处机械改动、
/// 漏一个就编译不过；而单套色板本来就没有运行时可变的必要。新增颜色照旧先进这里，
/// 不要写死 `Color(0xFF...)` 字面量。
///
/// 层级（改色时别破）：
/// - `cardBg` 白 > `bg` 纸白 > `heroBg` 压下去 > `bg2` 卡内次级面（键帽要沉下去）
/// - 文字：`ink` (≥15:1) > `ink2` (>5.5:1) > `ink3` (≥4.5:1) > `ink4`（不承担可读性）
/// - 这四条由 `test/design/tokens_contrast_test.dart` 守着，改坏就红。
abstract final class C {
  /// 主文字 / 强调（对 [bg] 16.6:1）
  ///
  /// 「纸墨」的墨：不是纯黑，压一点暖调（`#1C1A17`），纯黑压在纸白上会发冷。
  static const ink = Color(0xFF1C1A17);

  /// 次要文字（对 [bg] 6.8:1）
  static const ink2 = Color(0xFF5C5850);

  /// 辅助文字（对 [bg] 5.2:1，对 [bg2] 4.6:1）
  ///
  /// 12.5px 的 `caption` 在用这个色，必须过 AA（4.5:1）。旧色板这里是 `#9AA0A8`，
  /// 白底上只有 2.6:1 —— 那是既有缺陷，这一轮一并修掉，所以它比旧值明显更深。
  static const ink3 = Color(0xFF6F695C);

  /// 占位 / 弱分割：不承担可读性，只要求比 [bg2] 深一点看得出来
  static const ink4 = Color(0xFFB9B2A5);

  /// 轮盘类选择器的选中行遮罩（墨 6%）
  static const inkWash = Color(0x0F1C1A17);

  /// 页面底 = 纸白
  ///
  /// 不是纯白：纯白留给 [cardBg]，底必须比卡暗一点点，「卡浮起来」才成立。
  static const bg = Color(0xFFFBFAF7);

  /// **卡内的次级面**：输入底、未选中的胶囊、数字键帽、小图标底。
  ///
  /// 两条约束同时成立才行：
  /// ① 比 [cardBg] 深 —— 卡面是纯白，同色的话「未选中」这一档会整片消失；
  /// ② 比 [bg] 深 —— 键帽必须比抽屉的面沉下去，反过来会像键浮在面上。
  static const bg2 = Color(0xFFEFEBE3);

  /// 更弱的面：比 [bg] 深一点点，比 [bg2] 浅
  static const bg3 = Color(0xFFF7F5F0);

  /// 1px 描边（对 [cardBg] 1.29:1：看得见，但不抢眼）
  static const line = Color(0xFFE6E2DA);

  /// 稍强的分隔
  static const line2 = Color(0xFFDBD5C9);

  /// 超支警示（对 [bg] 6.5:1）
  ///
  /// 唯一保留色相的位置：超支必须一眼能认出来，用墨色分级做不到这件事。
  /// 压到接近砖红，仍然落在暖色系里，不会把纸墨调子打断。
  static const over = Color(0xFFA6321F);

  /// 超支警示 · 压在深色块上时用（深底上 [over] 会糊）
  static const overD = Color(0xFFC4472F);

  /// 原型里手机机身外的舞台底色，仅调试用
  static const stage = Color(0xFFE8E5DD);

  /// 强调色：进度条填充、光标、选中指示。
  ///
  /// 纸墨原则：不引入装饰色，强调 = 主文字色。要「显得重要」靠层级和留白，
  /// 不靠加一个颜色。
  static const accent = Color(0xFF1C1A17);

  /// 压在 [accent] 上的字色
  static const onAccent = Color(0xFFFFFFFF);

  /// 选中胶囊 / 标签底：与 [bg2] 同一档（「被选中的那块面」= 沉下去的那块面）
  static const accentSoft = Color(0xFFEFEBE3);

  /// 「今天」那个圆点的底色：默认是主文字色（墨底白字）
  static const todayMark = Color(0xFF1C1A17);

  /// 压在 [todayMark] 上的字色
  static const onTodayMark = Color(0xFFFFFFFF);

  /// 选中行的整行染色（与 [accentSoft] 同值，避免同一档面出现两种色）
  static const accentWash = Color(0xFFEFEBE3);

  /// 卡片投影（墨 4%）
  static const cardShadow = Color(0x0A1C1A17);

  /// 底部面板的拖拽柄 / 分块底 / 进度条轨道
  static const handle = Color(0xFFE9E4DA);

  /// 概览卡的描边：比 [line] 再暖一点，和压下去的卡身同族
  static const heroEdge = Color(0xFFE3DED4);

  /// **浮起来**的卡片（明细日卡、往来卡、SectionCard、抽屉、对话框）。
  ///
  /// 纯白，是整屏最亮的一块 —— 「卡比底亮」靠这一对关系（[cardBg] > [bg]），
  /// 不靠投影。
  static const cardBg = Color(0xFFFFFFFF);

  /// **压下去**的概览卡：比 [bg] 深，且必须与 [cardBg] 不同，
  /// 否则「汇总区压下、记录卡浮上」的层级就没了。
  static const heroBg = Color(0xFFF3F1EC);
}

/// 图表色阶：按重要度从强到弱（越靠前越主要）。
///
/// 暖灰十档，与 [C] 同一族：第一档就是主文字色，最后一档是最浅的纸灰。
/// 相邻两档靠**明度**分，不靠色相 —— 饼图切片的颜色只是「区分」，不是「分类」，
/// 用彩色会让人以为颜色本身有含义。
const List<Color> kChart = [
  Color(0xFF1C1A17),
  Color(0xFF332F29),
  Color(0xFF4A453C),
  Color(0xFF605A4F),
  Color(0xFF766F62),
  Color(0xFF8C8477),
  Color(0xFFA29A8C),
  Color(0xFFB8B0A2),
  Color(0xFFCFC7B9),
  Color(0xFFE4DED2),
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

/// 全局主题。
///
/// 单套色板，`ThemeData` 的 base 是 `light()`：纸墨是亮色方案（纸白底 + 墨字），
/// 不是深色模式。Material 组件（Switch / 进度条 / 选择器）因此都按亮底取前景色，
/// 不会出现「暗底配暗字」那类问题。
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
    // 抽屉/对话框的面用卡面：页面底是纸白，抽屉再铺纸白就成了整片同色，
    // 卡面是纯白，压下去才看得出这是一层浮起来的面。
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: C.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(R.card)),
      ),
    ),
    // 去掉 Material 3 默认的彩色涟漪，保持纸墨的观感
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: C.accent,
      selectionHandleColor: C.accent,
    ),
  );
}
