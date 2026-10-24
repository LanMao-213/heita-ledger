import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'theme_ctrl.dart';

/// 设计 token —— 颜色全部是**运行时 getter**，读的是 [ThemeCtrl] 里的当前色板。
///
/// ## 为什么不再是 `static const`（2026-10-24）
///
/// 之前这里是单套「纸墨/冷灰」色板，25 个颜色全是 `static const`。想在 App 内
/// 让用户自己换皮肤（而不是出 N 个包），颜色就必须是运行时可读的值。
/// 代价是全仓库 446 处 `const TextStyle/BoxDecoration` 里的 `C.xxx` 全部要拆
/// `const`（由 `lab/deconst.py` 机械拆完并逐轮 `dart analyze` 验证）。
///
/// 拆的收益是「一套代码、六套皮肤、用户自己选」；代价可以忽略 —— `const`
/// 只是编译期常量优化，对一个 4 页的记账 App 没有可测量的收益。
///
/// ⚠️ 因为不再是常量，**换肤后必须让整棵树重建**才会重新求值。
/// `app.dart` 给主子树挂了 `ValueKey(ThemeCtrl.i.id)` 做这件事，
/// 详见 [ThemeCtrl] 的文档。
///
/// ## 色板在哪
///
/// 六套色板的定义在 `design/palette.dart`（[Palette] / `kPalettes` / [kDefaultTheme]）。
/// 新增颜色先加进 [Palette]（六套都要给，少一个就是运行时空色），
/// 再在这里补一个 getter —— **不要**在这里写死 `Color(0xFF...)` 字面量。
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
/// - 把 `bg` 压到 `#F3F4F7`，让 `cardBg`(白) 与它拉开到 1.12:1 —— 卡片第一次
///   真的「浮」起来了，不再依赖描边告诉用户边界在哪；
/// - 补齐中间面：`heroBg`(压下去) / `bg2`(键帽) / `bg3`，四档明度递进；
/// - 新增 [E] 三档柔和投影，替代「描边当边界」的旧做法；
/// - 圆角整体放大（9/13/16/20 → 8/12/16/20/24/30），卡片用连续圆角
///   （[Shape.squircle]，iOS 的超椭圆，比圆弧软）；
/// - 新增 [M] 动效令牌，把 0ms 硬切换成 120–420ms 的分档过渡。
///
/// ## 层级（改色时别破）—— 深浅两族的**方向相反**
/// - 亮色板：`cardBg` > `bg` > `bg3` > `heroBg` > `bg2`（压下去 = 更暗）
/// - 深色板：`bg2` > `cardBg` > `bg` > `heroBg`（卡片比底亮，概览卡比底更暗）
/// - 文字：`ink` (>7:1) > `ink2` (>4.5:1) > `ink3` (>4.5:1) > `ink4`（≥3:1，图形 AA）
/// - 这四条由 `test/theme_palette_test.dart` **遍历全部六套**守着，改坏就红。
abstract final class C {
  /// 主文字 / 强调（对 [bg] 15.5:1）
  ///
  /// 「纸墨」的墨：不是纯黑，压一点暖调（`#14161A`），纯黑压在纸白上会发冷。
  static Color get ink => ThemeCtrl.i.palette.ink;

  /// 次要文字（对 [bg] 6.6:1）
  static Color get ink2 => ThemeCtrl.i.palette.ink2;

  /// 辅助文字（对 [bg] 5.1:1）
  ///
  /// 12px 的 `caption` 在用这个色，必须过 AA（4.5:1）。旧色板这里是 `#9AA0A8`，
  /// 白底上只有 2.6:1 —— 那是既有缺陷，这一轮一并修掉。
  static Color get ink3 => ThemeCtrl.i.palette.ink3;

  /// 最弱的一档墨：占位符「—」、弱分割「·」、非本月日期、图表的配角柱
  ///
  /// ⚠️ 别被「最弱」骗了：它同时承担**图形**岗位 —— 图表里的收入柱、安全页
  /// 的进度圈都用它。图形对象的门槛是 3:1（WCAG 1.4.11），不是「看得出就行」。
  /// 1.4.21 之前四套亮色板只有 1.47～2.37，柱子淡到几乎看不见；现已全部压到
  /// 对卡面 / 页面底都 ≥3.05（色相不动，只降明度）。文字岗位顺带可读性更好了。
  ///
  /// 仍然要明显淡于 [ink3]（层差 ≥1.5 倍对比度），「弱化」这个语义不能丢。
  static Color get ink4 => ThemeCtrl.i.palette.ink4;

  /// 轮盘类选择器的选中行遮罩（墨 6%）
  static Color get inkWash => ThemeCtrl.i.palette.inkWash;

  /// 页面底 = 冷浅灰
  ///
  /// 与 [cardBg]（纯白）拉开约 1.13:1 —— 层级靠**明度差**，不靠投影。
  /// 这是 iOS grouped 的做法：底色比卡暗一档，卡自然成立，不需要浮起来。
  static Color get bg => ThemeCtrl.i.palette.bg;

  /// **卡内的次级面**：输入底、未选中的胶囊、数字键帽、小图标底。
  ///
  /// 两条约束同时成立才行：
  /// ① 比 [cardBg] 深 —— 卡面是纯白，同色的话「未选中」这一档会整片消失；
  /// ② 比 [bg] 深 —— 键帽必须比抽屉的面沉下去，反过来会像键浮在面上。
  static Color get bg2 => ThemeCtrl.i.palette.bg2;

  /// 更弱的面：比 [bg] 深一点点，比 [bg2] 浅
  static Color get bg3 => ThemeCtrl.i.palette.bg3;

  /// 1px 描边（对 [cardBg] 1.30:1）
  ///
  /// ⚠️ 边界靠「底色差 + 1px 描边」，**不再用投影**。
  /// 上一版把描边几乎全去掉、用柔和投影分界；这一版反过来 —— 投影去掉，
  /// 卡面靠底色差立起来，必要时用这 1px 收边。
  static Color get line => ThemeCtrl.i.palette.line;

  /// 稍强的分隔
  static Color get line2 => ThemeCtrl.i.palette.line2;

  /// 超支警示（对 [bg] 5.5:1）
  ///
  /// 唯一保留色相的位置：超支必须一眼能认出来，用墨色分级做不到这件事。
  /// 压到接近砖红，仍然落在暖色系里，不会把纸墨调子打断。
  static Color get over => ThemeCtrl.i.palette.over;

  /// 超支警示 · 压在深色块上时用（深底上 [over] 会糊）
  static Color get overD => ThemeCtrl.i.palette.overD;

  /// 原型里手机机身外的舞台底色，仅调试用
  static Color get stage => ThemeCtrl.i.palette.stage;

  /// 强调色：进度条填充、光标、选中指示。
  ///
  /// 纸墨原则：不引入装饰色，强调 = 主文字色。要「显得重要」靠层级和留白，
  /// 不靠加一个颜色。
  static Color get accent => ThemeCtrl.i.palette.accent;

  /// 压在 [accent] 上的字色
  static Color get onAccent => ThemeCtrl.i.palette.onAccent;

  /// 选中胶囊 / 标签底
  static Color get accentSoft => ThemeCtrl.i.palette.accentSoft;

  /// 「今天」那个圆点的底色：默认是主文字色（墨底白字）
  static Color get todayMark => ThemeCtrl.i.palette.todayMark;

  /// 压在 [todayMark] 上的字色
  static Color get onTodayMark => ThemeCtrl.i.palette.onTodayMark;

  /// 选中行的整行染色
  static Color get accentWash => ThemeCtrl.i.palette.accentWash;

  /// 卡片投影（墨 5%）—— 与 [E.low] 同值，留给还在用旧写法的调用点
  static Color get cardShadow => ThemeCtrl.i.palette.cardShadow;

  /// 底部面板的拖拽柄 / 分块底 / 进度条轨道
  static Color get handle => ThemeCtrl.i.palette.handle;

  /// 概览卡的描边：只在概览卡真的需要边界时才用
  static Color get heroEdge => ThemeCtrl.i.palette.heroEdge;

  /// **浮起来**的卡片（明细日卡、往来卡、SectionCard、抽屉、对话框）。
  ///
  /// 纯白，是整屏最亮的一块 —— 「卡比底亮」靠这一对关系（[cardBg] > [bg]），
  /// 再由 [E.low] 把边缘柔化，不靠描边。
  static Color get cardBg => ThemeCtrl.i.palette.cardBg;

  /// **压下去**的概览卡。
  ///
  /// 必须比 [bg] 明显深一档（约 1.07:1），否则在浅灰底上「这块是不是卡」
  /// 会读不出来 —— 上一轮的暖米底与概览卡差 1.12:1，直接套用冷灰后
  /// 只差 1.02:1，第一版渲染出来概览卡像是不存在。
  static Color get heroBg => ThemeCtrl.i.palette.heroBg;
}

/// 投影 —— **已全部归零**。
///
/// 上一版把柔和投影当作主要分界手段（大 blur + 小 offset + 墨 5%）。
/// 这一版改成 iOS grouped 的做法：底色比卡暗一档，卡面自己就立住了，
/// 再加一层投影只会让画面发雾、显软。
///
/// 字段保留（值都是空数组）是为了不动调用点 —— 以后若某个浮层确实需要
/// 离开页面（比如 FAB、底部抽屉），再给它单独一档，而不是整站都铺。
abstract final class E {
  static const none = <BoxShadow>[];
  static const low = none;
  static const mid = none;
  static const high = none;
}

/// 图表色阶：按重要度从强到弱（越靠前越主要）。
///
/// 中性灰十档，与 [C] 同一族：第一档就是主文字色，最后一档是最浅的分隔灰。
/// 相邻两档靠**明度**分，不靠色相 —— 饼图切片的颜色只是「区分」，不是「分类」，
/// 用彩色会让人以为颜色本身有含义。
List<Color> get kChart => ThemeCtrl.i.palette.chart;

/// 圆角。
///
/// 整体比旧值（9/13/16/20）放大一档：圆角越大，矩形的「盒子感」越弱。
/// 卡片级别请用 [Shape.squircle] 拿连续圆角，而不是 [BorderRadius.circular]。
/// 圆角 —— 这一版整体收紧一档。
///
/// 上一版是 20 / 24 / 30（偏「软」，接近圆润的卡片风）。iOS 的实际取值
/// 小得多：设置页的卡 10、按钮 8~12、大面板 16~20。圆角一大，界面会
/// 显得"胖"，这也是「不像 iOS」的第二个来源。
abstract final class R {
  static const xs = 8.0;    // 小标签、角标
  static const sm = 10.0;   // 按钮、芯片、图标底
  static const md = 12.0;   // 行内块、输入框
  static const card = 14.0; // 卡片
  static const lg = 18.0;   // 大卡、对话框
  static const sheet = 22.0; // 底部抽屉顶部两角
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
  static TextStyle get hero => TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    color: C.ink,
    letterSpacing: -0.5,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle get title => TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: C.ink,
    letterSpacing: -0.2,
  );

  /// 页头之下、内容之上的**主文字**：区间行（「10月1日 – 10月31日」）、
  /// 图表环形中心这类「卡片内次级大数字」。
  ///
  /// 22（[title]）给页面标题，20 给这一层 —— 两级都要，只差 2px 但该差。
  static TextStyle get titleSm => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: C.ink,
    letterSpacing: -0.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle get section => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: C.ink,
  );

  static TextStyle get body => TextStyle(fontSize: 15, color: C.ink, height: 1.5);
  static TextStyle get body2 => TextStyle(fontSize: 13, color: C.ink2, height: 1.45);

  /// 12px —— 对 [C.ink3] 5.1:1，小字仍过 AA
  static TextStyle get caption => TextStyle(fontSize: 12, color: C.ink3, height: 1.35);

  /// 分组小标题 / 单位 / 角标：11px，字距放开一点更好读
  static TextStyle get overline => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: C.ink3,
    letterSpacing: 0.4,
  );

  /// 金额（等宽数字，避免列表里数字跳动）
  static TextStyle get amount => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: C.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle get amountSm => TextStyle(
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
  static TextStyle get amountXs => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: C.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 全局主题。
///
/// `ThemeData` 的 base 由当前色板的 `dark` 决定：深色板走 `dark()`、
/// 亮色板走 `light()` —— Material 组件（Switch / 进度条 / 选择器）据此取
/// 前景色，不会出现「暗底配暗字」那类问题。
///
/// 色值全部从 [ThemeCtrl.i.palette] 取，换肤后由 `app.dart` 重建整棵子树
/// 重新调用这里。
ThemeData buildAppTheme() {
  final p = ThemeCtrl.i.palette;
  final base = p.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    // ⚠️ 这里要覆盖的远比「primary / surface」多。只覆盖这两个的话，
    // Material 组件里凡是取 `surfaceContainer*`、`outline`、`secondary`、
    // `inverseSurface` 的面就都还是 M3 的默认色 —— 亮色板下那套默认色是
    // **带紫的灰**（surfaceContainer #F3EDF7 / outline #79747E / secondary
    // #625B71），在中性灰、暖米、泽金、圣地四套里一眼就看得出「这块不是
    // 我们家的颜色」。已踩到的：Switch 轨道、PopupMenu 弹出菜单。
    //
    // 规则：凡是 Material 默认从 colorScheme 派生、且我们界面上真的会用到
    // 的面，一律换成色板里的对应 token；用不到的也顺手兜住，省得以后新加
    // 组件再踩一次。
    colorScheme: base.colorScheme.copyWith(
      primary: p.ink,
      onPrimary: p.bg,
      secondary: p.accent,
      onSecondary: p.onAccent,
      surface: p.bg,
      onSurface: p.ink,
      // 逐级浮起的面：底 → 纸 → 卡
      surfaceContainerLowest: p.bg,
      surfaceContainerLow: p.bg2,
      surfaceContainer: p.bg2,
      surfaceContainerHigh: p.bg2,
      surfaceContainerHighest: p.bg2,
      onSurfaceVariant: p.ink3,
      outline: p.line2,
      outlineVariant: p.line,
      // 反色面（SnackBar / Tooltip）：墨底纸字
      inverseSurface: p.ink,
      onInverseSurface: p.bg,
      // M3 会给浮起的面染一层 primary 的色调（亮色板下就是紫色调），
      // 卡片、弹层、对话框都各自显式关掉了，这里再兜一道。
      surfaceTint: Colors.transparent,
      error: p.over,
    ),
    dividerColor: p.line,
    // 分隔线压到最细：新界面靠面分界，线只做「切断」不做「装饰」
    dividerTheme: DividerThemeData(
      color: p.line,
      thickness: 1,
      space: 1,
    ),
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      foregroundColor: p.ink,
      // 从主题自带的 titleLarge 派生，而不是直接用 T.title：
      // T.title 没有 fontFamily，AppBar 会把它当整段样式覆盖掉，
      // 结果标题脱离主题字体族（测试环境里中文会掉成方块）。
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: p.ink,
      ),
    ),
    // 卡片统一走「白面 + 柔投影 + 连续圆角」，不再靠描边分界
    cardTheme: CardThemeData(
      color: p.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.squircle(R.card),
      margin: EdgeInsets.zero,
    ),
    // 抽屉/对话框的面用卡面：页面底是纸白，抽屉再铺纸白就成了整片同色，
    // 卡面是纯白，压下去才看得出这是一层浮起来的面。
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.top(R.sheet),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.squircle(R.lg),
    ),
    // 弹出菜单（安全页备份项的「更多」）。不给的话它取 surfaceContainer，
    // 亮色板下是 M3 的淡紫白 #F3EDF7，浮在纸墨面上像贴了块别家的纸。
    popupMenuTheme: PopupMenuThemeData(
      color: p.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.squircle(R.md),
      textStyle: T.body2.copyWith(color: p.ink),
    ),
    // 开关。轨道不给的话取 surfaceContainerHighest（亮色板 #E6E0E9，紫灰）。
    // 开：轨道是墨、滑块是纸；关：轨道是次级纸面、滑块是浅墨 —— 两个状态
    // 都靠「墨/纸」这对关系表达，不吃任何彩色。
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.ink4;
        return states.contains(WidgetState.selected) ? p.bg : p.ink3;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.bg2;
        return states.contains(WidgetState.selected) ? p.ink : p.bg2;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return p.line2;
      }),
    ),
    // 日期选择器 / 日期范围选择器。全 App 有 5 处调用（记一笔、周期账单、
    // 债务还款日、筛选卡自定义时间段），都没传任何颜色参数 —— 不在这里给
    // 就整个吃 M3 默认：对话框面是 surfaceContainerHigh，顶部那块日期大字
    // 区是 primary 的淡色调（亮色板下就是淡紫 #EADDFF 一族），选中的日子
    // 是实心紫圆。也就是说这是**唯一一处会露出一整片紫的地方**。
    datePickerTheme: DatePickerThemeData(
      backgroundColor: p.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.squircle(R.lg),
      headerBackgroundColor: p.heroBg,
      headerForegroundColor: p.ink,
      weekdayStyle: T.caption.copyWith(color: p.ink3),
      dayStyle: T.body2.copyWith(color: p.ink),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.ink4;
        if (states.contains(WidgetState.selected)) return p.onAccent;
        return p.ink;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.accent;
        return Colors.transparent;
      }),
      dayOverlayColor: WidgetStateProperty.all(p.inkWash),
      // 「今天」不填色，只描边 —— 否则它和「选中」两个圆点会打架
      todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
      todayForegroundColor: WidgetStateProperty.all(p.accent),
      todayBorder: BorderSide(color: p.accent, width: 1.2),
      yearStyle: T.body2.copyWith(color: p.ink),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.onAccent;
        return p.ink;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.accent;
        return Colors.transparent;
      }),
      yearOverlayColor: WidgetStateProperty.all(p.inkWash),
      rangePickerBackgroundColor: p.cardBg,
      rangePickerHeaderBackgroundColor: p.heroBg,
      rangePickerHeaderForegroundColor: p.ink,
      rangePickerHeaderHeadlineStyle: T.titleSm.copyWith(color: p.ink),
      rangePickerHeaderHelpStyle: T.caption.copyWith(color: p.ink3),
      rangeSelectionBackgroundColor: p.accentSoft,
      rangeSelectionOverlayColor: WidgetStateProperty.all(p.inkWash),
      dividerColor: p.line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.bg2,
        hintStyle: T.body2.copyWith(color: p.ink3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
    ),
    // 提示条。代码里 `showToast` 已经显式给了墨底纸字，这里兜住的是将来
    // 直接用 `ScaffoldMessenger.showSnackBar` 的地方 —— 不兜的话会拿到
    // inverseSurface（M3 默认的深灰 #322F35），在深色板上近乎看不见。
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: T.body2.copyWith(color: p.bg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
    ),
    // 去掉 Material 3 默认的彩色涟漪，保持纸墨的观感
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionHandleColor: p.accent,
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
