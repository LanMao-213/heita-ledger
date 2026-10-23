import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 设计 token —— 单套「纸墨」色板，1.5.0 起按「柔和版」重做过一轮。
///
/// ## 这一轮改了什么，为什么
///
/// 上一版的问题不是颜色不好看，是**层级立不起来**：
/// - `bg #FBFAF7` 与 `cardBg #FFFFFF` 只差 1.06:1，肉眼几乎同一块面；
/// - 于是所有卡片只能靠 1px 描边（`C.line`，对白 1.29:1）互相区分，
///   而这么淡的描边又几乎看不见 —— 结果整屏退化成「一条被细线切开的白板」；
/// - 全库 59 处描边、只有 1 处卡片有投影，界面是纯平面的；
/// - 加上几乎没有动效，状态变化全是 0ms 硬切，所以整体观感「僵硬」。
///
/// 这一轮的修正原则：**用「面」分界，不用「线」分界。**
/// - 把 `bg` 压到 `#F5F2EA`，让 `cardBg`(白) 与它拉开到 1.12:1 —— 卡片第一次
///   真的「浮」起来了，不再依赖描边告诉用户边界在哪；
/// - 补齐中间面：`heroBg`(压下去) / `bg2`(键帽) / `bg3`，四档明度递进；
/// - 新增 [E] 三档柔和投影，替代「描边当边界」的旧做法；
/// - 圆角整体放大（9/13/16/20 → 8/12/16/20/24/30），卡片用连续圆角
///   （[Shape.squircle]，iOS 的超椭圆，比圆弧软）；
/// - 新增 [M] 动效令牌，把 0ms 硬切换成 120–420ms 的分档过渡。
///
/// ## 层级（改色时别破）
/// - 面：`cardBg` 白 > `bg` 纸白 > `bg3` > `heroBg` 压下去 > `bg2` 键帽
/// - 文字：`ink` (>15:1) > `ink2` (>6.5:1) > `ink3` (>5:1) > `ink4`（不承担可读性）
/// - 这四条由 `test/design/tokens_contrast_test.dart` 守着，改坏就红。
///
/// ## 为什么仍然全部是 `static const`
/// 全仓库 446 处 `C.xxx` 都写在 `const TextStyle(...)` / `const BoxDecoration(...)`
/// 里。颜色一旦变成运行时 getter，这些 const 构造全部要拆掉，几百处机械改动、
/// 漏一个就编译不过；而单套色板本来就没有运行时可变的必要。新增颜色照旧先进这里，
/// 不要写死 `Color(0xFF...)` 字面量。
abstract final class C {
  /// 主文字 / 强调（对 [bg] 15.5:1）
  ///
  /// 「纸墨」的墨：不是纯黑，压一点暖调（`#1C1A17`），纯黑压在纸白上会发冷。
  static const ink = Color(0xFF1C1A17);

  /// 次要文字（对 [bg] 6.6:1）
  static const ink2 = Color(0xFF5B554D);

  /// 辅助文字（对 [bg] 5.1:1）
  ///
  /// 12px 的 `caption` 在用这个色，必须过 AA（4.5:1）。旧色板这里是 `#9AA0A8`，
  /// 白底上只有 2.6:1 —— 那是既有缺陷，这一轮一并修掉。
  static const ink3 = Color(0xFF6D655B);

  /// 占位 / 弱分割：不承担可读性，只要求比 [bg2] 深一点看得出来
  static const ink4 = Color(0xFFACA69E);

  /// 轮盘类选择器的选中行遮罩（墨 6%）
  static const inkWash = Color(0x0F1C1A17);

  /// 页面底 = 纸白
  ///
  /// 比旧值（`#FBFAF7`）压深一档：旧的底与白卡只差 1.06:1，等于没有层级，
  /// 卡片只能靠描边撑边界。现在与 [cardBg] 拉开到 1.12:1，卡是真的浮起来的。
  static const bg = Color(0xFFF5F2EA);

  /// **卡内的次级面**：输入底、未选中的胶囊、数字键帽、小图标底。
  ///
  /// 两条约束同时成立才行：
  /// ① 比 [cardBg] 深 —— 卡面是纯白，同色的话「未选中」这一档会整片消失；
  /// ② 比 [bg] 深 —— 键帽必须比抽屉的面沉下去，反过来会像键浮在面上。
  static const bg2 = Color(0xFFE4DED0);

  /// 更弱的面：比 [bg] 深一点点，比 [bg2] 浅
  static const bg3 = Color(0xFFEDE8DF);

  /// 1px 描边（对 [cardBg] 1.30:1）
  ///
  /// ⚠️ 新界面的边界**优先用 [E] 的投影，不优先用描边**。这一轮把绝大多数
  /// 容器的描边去掉了，只保留真正需要「切断」的地方（表头、输入框、分段控件）。
  static const line = Color(0xFFE6E1D7);

  /// 稍强的分隔
  static const line2 = Color(0xFFD5CDBC);

  /// 超支警示（对 [bg] 5.5:1）
  ///
  /// 唯一保留色相的位置：超支必须一眼能认出来，用墨色分级做不到这件事。
  /// 压到接近砖红，仍然落在暖色系里，不会把纸墨调子打断。
  static const over = Color(0xFFB13521);

  /// 超支警示 · 压在深色块上时用（深底上 [over] 会糊）
  static const overD = Color(0xFFC46556);

  /// 原型里手机机身外的舞台底色，仅调试用
  static const stage = Color(0xFFDBD8D1);

  /// 强调色：进度条填充、光标、选中指示。
  ///
  /// 纸墨原则：不引入装饰色，强调 = 主文字色。要「显得重要」靠层级和留白，
  /// 不靠加一个颜色。
  static const accent = Color(0xFF1C1A17);

  /// 压在 [accent] 上的字色
  static const onAccent = Color(0xFFFFFFFF);

  /// 选中胶囊 / 标签底
  static const accentSoft = Color(0xFFEEEAE3);

  /// 「今天」那个圆点的底色：默认是主文字色（墨底白字）
  static const todayMark = Color(0xFF1C1A17);

  /// 压在 [todayMark] 上的字色
  static const onTodayMark = Color(0xFFFFFFFF);

  /// 选中行的整行染色
  static const accentWash = Color(0xFFF2F0EB);

  /// 卡片投影（墨 5%）—— 与 [E.low] 同值，留给还在用旧写法的调用点
  static const cardShadow = Color(0x0D1C1A17);

  /// 底部面板的拖拽柄 / 分块底 / 进度条轨道
  static const handle = Color(0xFFE9E5DC);

  /// 概览卡的描边：只在概览卡真的需要边界时才用
  static const heroEdge = Color(0xFFD8D0C1);

  /// **浮起来**的卡片（明细日卡、往来卡、SectionCard、抽屉、对话框）。
  ///
  /// 纯白，是整屏最亮的一块 —— 「卡比底亮」靠这一对关系（[cardBg] > [bg]），
  /// 再由 [E.low] 把边缘柔化，不靠描边。
  static const cardBg = Color(0xFFFFFFFF);

  /// **压下去**的概览卡：比 [bg] 深，且必须与 [cardBg] 不同，
  /// 否则「汇总区压下、记录卡浮上」的层级就没了。
  static const heroBg = Color(0xFFECE7DE);
}

/// 投影 —— 新界面的主要分界手段。
///
/// 三档都是「大 blur + 小 offset + 低透明」：模糊半径远大于位移，
/// 所以影子是「贴着卡片晕开」而不是「卡片后面拖一条黑边」。
/// 用墨色（不是纯黑）投影，免得把暖调的画面压灰。
abstract final class E {
  static const none = <BoxShadow>[];

  /// 卡片：blur 10 / 位移 2 / 墨 5%
  static const low = <BoxShadow>[
    BoxShadow(
      color: Color(0x0D1C1A17),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];

  /// 底部抽屉、对话框：blur 20 / 位移 6 / 墨 7%
  static const mid = <BoxShadow>[
    BoxShadow(
      color: Color(0x121C1A17),
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
  ];

  /// 悬浮按钮、跟随滚浮动的元素：blur 28 / 位移 10 / 墨 10%
  static const high = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A1C1A17),
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
  ];
}

/// 图表色阶：按重要度从强到弱（越靠前越主要）。
///
/// 暖灰十档，与 [C] 同一族：第一档就是主文字色，最后一档是最浅的纸灰。
/// 相邻两档靠**明度**分，不靠色相 —— 饼图切片的颜色只是「区分」，不是「分类」，
/// 用彩色会让人以为颜色本身有含义。
const List<Color> kChart = [
  Color(0xFF1C1A17),
  Color(0xFF322F2B),
  Color(0xFF47443F),
  Color(0xFF5D5952),
  Color(0xFF726E66),
  Color(0xFF88837A),
  Color(0xFF9D988E),
  Color(0xFFB3ADA1),
  Color(0xFFC8C2B5),
  Color(0xFFDED7C9),
];

/// 圆角。
///
/// 整体比旧值（9/13/16/20）放大一档：圆角越大，矩形的「盒子感」越弱。
/// 卡片级别请用 [Shape.squircle] 拿连续圆角，而不是 [BorderRadius.circular]。
abstract final class R {
  static const xs = 8.0;   // 小标签、角标
  static const sm = 12.0;  // 按钮、芯片、图标底
  static const md = 16.0;  // 行内块、输入框
  static const card = 20.0; // 卡片
  static const lg = 24.0;  // 大卡、对话框
  static const sheet = 30.0; // 底部抽屉顶部两角
  static const pill = 999.0;
}

/// 连续圆角（squircle）。
///
/// iOS 的圆角不是圆弧，是超椭圆：曲率在角上连续变化，视觉上比
/// `RoundedRectangleBorder` 更软、更紧。Flutter 3.13+ 原生提供
/// `RoundedSuperellipseBorder`，本项目 3.47 可用。
///
/// 用法（配 ShapeDecoration，因为它支持 shadows）：
/// ```dart
/// decoration: ShapeDecoration(
///   color: C.cardBg,
///   shadows: E.low,
///   shape: Shape.squircle(R.card),
/// )
/// ```
abstract final class Shape {
  static RoundedSuperellipseBorder squircle(double r) =>
      RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(r));

  static RoundedSuperellipseBorder top(double r) => RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(r)),
      );
}

/// 间距 —— 8pt 为主，4pt 只用于行内微调。
abstract final class S {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;  // 标准左右边距
  static const xl = 20.0;
  static const xxl = 24.0; // 分组间距
  static const xxxl = 32.0;
  static const huge = 40.0;
}

/// 动效 —— 这一轮新建。
///
/// 上一版全库只有 7 处隐式动画，翻期、Tab 选中、删除、展开全是 0ms 硬切，
/// 这是「僵硬」最主要的来源。现在所有状态变化至少走 [fast]，
/// 进入/退出类走 [base]，页面级走 [page]。
abstract final class M {
  /// 按下 / 抬手反馈
  static const tap = Duration(milliseconds: 120);

  /// 行内状态变化：勾选、高亮、图标切换
  static const fast = Duration(milliseconds: 180);

  /// 展开收起、数字滚动、列表项进出场
  static const base = Duration(milliseconds: 260);

  /// 抽屉、弹层
  static const slow = Duration(milliseconds: 380);

  /// 页面转场
  static const page = Duration(milliseconds: 420);

  /// 通用减速（easeOutCubic）：不出挑、不拖沓，绝大多数地方用这条
  static const standard = Cubic(0.215, 0.610, 0.355, 1.000);

  /// 强调减速（起步更慢、收尾更稳）：用于「用户主动触发」的大动作
  static const emphasized = Cubic(0.050, 0.700, 0.100, 1.000);

  /// iOS 抽屉曲线
  static const ios = Cubic(0.320, 0.720, 0.000, 1.000);

  /// 轻微回弹：只在需要「有弹性」的地方用（按下、勾选、数字跳动）
  static const spring = Cubic(0.340, 1.020, 0.640, 1.000);
}

/// 文本样式。
///
/// 不指定 fontFamily：Android 上交给系统 CJK 字体（华为 HarmonyOS Sans /
/// 小米 MiSans / 原生 Noto Sans CJK），比硬绑某个字体更稳。
///
/// 这一轮把相邻档位的差从 1px 拉开到 2–3px：旧值 14.5 / 13.5 / 12.5 三档
/// 只差 1px，一行里读不出主次，也是「糊成一片」的原因之一。
abstract final class T {
  /// 大数字（概览页余额）
  static const hero = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    color: C.ink,
    letterSpacing: -0.5,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: C.ink,
    letterSpacing: -0.2,
  );

  static const section = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: C.ink,
  );

  static const body = TextStyle(fontSize: 15, color: C.ink, height: 1.5);
  static const body2 = TextStyle(fontSize: 13, color: C.ink2, height: 1.45);

  /// 12px —— 对 [C.ink3] 5.1:1，小字仍过 AA
  static const caption = TextStyle(fontSize: 12, color: C.ink3, height: 1.35);

  /// 分组小标题 / 单位 / 角标：11px，字距放开一点更好读
  static const overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: C.ink3,
    letterSpacing: 0.4,
  );

  /// 金额（等宽数字，避免列表里数字跳动）
  static const amount = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: C.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const amountSm = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: C.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// 金额（最小号）：列表行尾、副数值、预算条旁边的余额。
  ///
  /// 原来这些位置写成 `amountSm.copyWith(fontSize: 13.5)` —— 13.5 是个
  /// 既不在字阶里、也不在金额档里的数，5 处各写一遍。补这一档，是为了
  /// 「小号金额」有名字可叫，而不是每次去改一个魔法数。
  static const amountXs = TextStyle(
    fontSize: 13,
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
    // 分隔线压到最细：新界面靠面分界，线只做「切断」不做「装饰」
    dividerTheme: const DividerThemeData(
      color: C.line,
      thickness: 1,
      space: 1,
    ),
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      foregroundColor: C.ink,
      // 从主题自带的 titleLarge 派生，而不是直接用 T.title：
      // T.title 没有 fontFamily，AppBar 会把它当整段样式覆盖掉，
      // 结果标题脱离主题字体族（测试环境里中文会掉成方块）。
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: C.ink,
      ),
    ),
    // 卡片统一走「白面 + 柔投影 + 连续圆角」，不再靠描边分界
    cardTheme: CardThemeData(
      color: C.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.squircle(R.card),
      margin: EdgeInsets.zero,
    ),
    // 抽屉/对话框的面用卡面：页面底是纸白，抽屉再铺纸白就成了整片同色，
    // 卡面是纯白，压下去才看得出这是一层浮起来的面。
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: C.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.top(R.sheet),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.squircle(R.lg),
    ),
    // 去掉 Material 3 默认的彩色涟漪，保持纸墨的观感
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: C.accent,
      selectionHandleColor: C.accent,
    ),
    // 页面转场换成 iOS 的右进右出：安卓默认的上下淡入在这个界面里
    // 显得「换页」，右推 + 边缘跟手返回才有连续感。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
