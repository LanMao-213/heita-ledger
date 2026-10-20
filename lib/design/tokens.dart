import 'package:flutter/material.dart';

/// 编译期主题开关：`flutter build apk --dart-define=HEITA=1` 出「露露缇雅·泽金」版。
///
/// ⚠️ 这一版是**亮色**（明亮天空 + 白裙 + 绯带），不是深色模式 —— 见 [C] 的说明。
///
/// 为什么是**编译期**而不是运行时换肤：颜色 token 全是 `static const`，
/// 全仓库 457 处 `C.xxx` 又都写在 `const TextStyle(...)` 里。一旦颜色变成
/// 运行时可变的 getter，所有 `const` 构造都得拆掉，几百处机械改动、每次
/// 都是漏一个就编译不过。而换主题本来就是「一个人自己装哪个包」的事，
/// 不值得为它把整个 widget 树的 const 优化全废掉。
///
/// 代价说清楚：装哪个包就是哪个主题，App 内不提供切换。要对比就两个包都装
/// （`-PappIdSuffix=.heita` 与默认包可以共存）。
///
/// 默认值 false = **现有黑白灰版本一分不动**，这就是「保留现在版本」的实现方式。
///
/// ⚠️ 开关必须写成 `--dart-define=HEITA=1` 并**按字符串比较**：
/// `bool.fromEnvironment` 只认 `"true"`，传 `1` 会静默得到 false ——
/// 和 `HEITA_SEED` 是同一个坑（那次是包打出来了、首页还是空的，这次是
/// 包打出来了、界面还是浅色）。所以这里不省这一步。
const String _kThemeFlag = String.fromEnvironment('HEITA');
const bool kHeita = _kThemeFlag == '1' || _kThemeFlag == 'true';

/// 设计 token —— 与原型 `记账App/index.html` 的 `:root` 变量一一对应。
///
/// 两套配色共用同一组语义名，`kHeita` 决定取哪一档：
///
/// | 语义 | 默认（黑白灰） | 露露缇雅·泽金（明亮） |
/// | --- | --- | --- |
/// | 底 | 纯白 `#FFFFFF` | 天青极淡 `#EFF6F8`（明亮天空） |
/// | 卡 / 输入 | 浅灰 `#F4F5F6` | 暖白 `#FDFBF8`（白裙） |
/// | 概览卡 | 浅灰 `#F4F5F6` | 薰衣草极淡 `#F7F2F4` |
/// | 描边 | 冷灰 `#E8EAEC` | 天青灰 `#D5E5EA` |
/// | 主文字 | 近黑 `#14161A` | 绯红压暗 `#4A2C3A` |
/// | 超支 | 深红 `#A3231A` | 绯红 `#814864`（绯带） |
/// | 强调 | 与主文字同色 | 深天青 `#3E7A8B` |
///
/// ⚠️ **露露缇雅版不是深色模式。** 方案原文写的是「明亮天空下的白裙绯带，
/// 是黑塔角色中最清透的一套」—— 底色是亮的（`#EFF6F8` / `#FDFBF8`，亮度均 > 0.9），
/// 文字是暗的，`ThemeData` 也仍然走 `light()`。之前按「暗石底 + 骨白」的
/// 黑塔阵营基调做过一版，那是深色的，已经被这一版替换掉。
///
/// 四色用法（尽量用原色，用不了的才用它们的明度变体）：
/// - 天青 `#9AC7D3` → 大块淡底/徽标底/图表（原色可以直接上，字压深绯紫）
/// - 暖白 `#FDFBF8` → 卡片面（原色）
/// - 绯红 `#814864` → 超支（原色）、主文字与占位取它的压暗/提亮变体
/// - 薰衣草 `#BC9DB1` → 占位、弱分割、概览卡底与描边
abstract final class C {
  /// 主文字 / 强调
  ///
  /// 绯红 `#814864` 压暗到近黑：整段正文用纯绯红太艳，压暗后仍是「绯」的
  /// 底子（11.8:1，比默认主题的 `#14161A` 还高一点）。
  static const ink = kHeita ? Color(0xFF4A2C3A) : Color(0xFF14161A);

  /// 次要文字（绯红系中间调，6.3:1）
  static const ink2 = kHeita ? Color(0xFF6E5566) : Color(0xFF5C626B);

  /// 辅助文字（提亮的绯红系，5.1:1 —— 12.5px 的小字也要看得清）
  static const ink3 = kHeita ? Color(0xFF7E6478) : Color(0xFF9AA0A8);

  /// 占位 / 弱分割：**薰衣草原色**，这个位置不承担可读性
  static const ink4 = kHeita ? Color(0xFFBC9DB1) : Color(0xFFC4C9CF);

  /// 轮盘类选择器的选中行遮罩（默认黑 6%，露露版用绯红 8%）
  static const inkWash = kHeita ? Color(0x14814864) : Color(0x0F14161A);

  /// 底 = 明亮天空（天青 `#9AC7D3` 约 16% 叠白）
  static const bg = kHeita ? Color(0xFFEAF3F6) : Color(0xFFFFFFFF);

  /// **卡内的次级面**：输入底、未选中的胶囊、小图标底。
  ///
  /// 默认主题是 `#F4F5F6` 的浅灰；露露缇雅版是比底更深一档的天青 `#E0EEF1`。
  ///
  /// 两条约束同时成立才行：
  /// ① 它要**比卡面深** —— 卡面是暖白 `#FDFBF8`，同色的话「未选中」这一档
  ///    会整片消失，看不出哪些是可点的；
  /// ② 它要**比页面底深** —— 数字键盘的键用这个色，键必须比抽屉的面
  ///    沉下去一点（原来白面 + 灰键就是这个关系，反过来会像键浮在面上）。
  static const bg2 = kHeita ? Color(0xFFE0EEF1) : Color(0xFFF4F5F6);
  static const bg3 = kHeita ? Color(0xFFF4F9FB) : Color(0xFFFAFAFB);

  /// 描边：天青灰
  static const line = kHeita ? Color(0xFFD5E5EA) : Color(0xFFE8EAEC);

  /// 稍强的分隔：薰衣草灰
  static const line2 = kHeita ? Color(0xFFE1D3DC) : Color(0xFFDFE2E5);

  /// 超支警示 · **绯红原色**（对暖白 6.9:1）
  static const over = kHeita ? Color(0xFF814864) : Color(0xFFA3231A);

  /// 超支警示 · 亮绯红（压在深色块上时用）
  static const overD = kHeita ? Color(0xFFC25A6E) : Color(0xFFE8493A);

  /// 原型里手机机身外的舞台底色，仅调试用
  static const stage = kHeita ? Color(0xFFE3EBEE) : Color(0xFFE8EAEF);

  // ------------------------------------------------------------ 露露缇雅专属
  //
  // 下面这组在默认主题里**刻意等于现状**（`C.ink` / `C.line` / `C.bg2`），
  // 所以黑白灰版本的渲染结果一个像素都不变 —— 新增 token 不等于改设计。

  /// 强调色：进度条填充、选中指示、需要「一点颜色」的地方。
  ///
  /// 天青原色 `#9AC7D3` 太亮，压在淡底上只有 1.3:1（进度条属于「图形对象」，
  /// 至少要 3:1 才看得出进度到哪了），所以这里用它的压暗变体 `#3E7A8B`；
  /// 原色留给 [accentSoft]。默认主题回落到主文字色（黑白灰原则：不引入装饰色）。
  static const accent = kHeita ? Color(0xFF3E7A8B) : Color(0xFF14161A);

  /// 压在 [accent] 上的字色
  static const onAccent = kHeita ? Color(0xFFFDFBF8) : Color(0xFFFFFFFF);

  /// **天青原色**：选中胶囊 / 标签底 / 图表主色。
  /// 这么亮的颜色只能当底，上面压深绯紫的字（6.7:1）。
  static const accentSoft = kHeita ? Color(0xFF9AC7D3) : Color(0xFFF4F5F6);

  /// 「今天」那个圆点的底色：默认主题是主文字色（黑底白字），
  /// 露露缇雅版是**天青原色** —— 日历里唯一的那一小块天空。
  static const todayMark = kHeita ? Color(0xFF9AC7D3) : Color(0xFF14161A);

  /// 压在 [todayMark] 上的字色（天青太亮，得换成深绯紫，6.7:1）
  static const onTodayMark = kHeita ? Color(0xFF4A2C3A) : Color(0xFFFFFFFF);

  /// 天青 12% 的淡底（选中行的整行染色）
  static const accentWash = kHeita ? Color(0x1F9AC7D3) : Color(0xFFF4F5F6);

  /// 卡片投影。深色模式才需要把黑压到 40%；这一版是亮底，和默认一样克制，
  /// 只是把黑换成带一点绯紫的 `#4A2C3A`，免得投影把画面压灰。
  static const cardShadow = kHeita ? Color(0x0F4A2C3A) : Color(0x0A14161A);

  /// 底部面板的拖拽柄 / 分块底 / 进度条轨道（天青灰）
  static const handle = kHeita ? Color(0xFFDCE4E8) : Color(0xFFEEF0F2);

  /// 概览卡的描边：薰衣草灰，和卡身同族
  static const heroEdge = kHeita ? Color(0xFFE2CDD8) : Color(0xFFE8EAEC);

  /// **浮起来**的卡片（明细日卡、往来卡、SectionCard）。
  ///
  /// 默认主题是纯白（D-10）；这一版是**暖白原色**，压在天青底的上面
  /// —— 同一套「卡比底亮」的关系，只是换成有色彩的说法。
  static const cardBg = kHeita ? Color(0xFFFDFBF8) : Color(0xFFFFFFFF);

  /// **压下去**的概览卡：默认主题是 `#F4F5F6`，这一版是薰衣草极淡。
  ///
  /// 直接沿用 bg2 会让概览卡和明细卡同色，D-09 那条「汇总区压下去、记录卡浮上来」
  /// 的层级就没了 —— 所以它必须和 [cardBg] 是两个值。
  static const heroBg = kHeita ? Color(0xFFF4EBF0) : Color(0xFFF4F5F6);
}

/// 图表色阶：按重要度从强到弱。
///
/// 默认主题是十档灰；露露缇雅版是「绯红 → 深天青 → 天青 → 薰衣草」四色
/// 加它们的明度变体 —— 四色循环时相邻两档的明度差比色相更容易分辨。
const List<Color> kChart = kHeita
    ? [
        Color(0xFF814864), // 绯红（原色）
        Color(0xFF3E7A8B), // 深天青
        Color(0xFF9AC7D3), // 天青（原色）
        Color(0xFFBC9DB1), // 薰衣草（原色）
        Color(0xFFA86377), // 玫瑰绯
        Color(0xFF6FA3B2), // 中天青
        Color(0xFFC9AFC0), // 淡薰衣草
        Color(0xFFA88CA2), // 藕紫
        Color(0xFFC4D9DF), // 极淡天青
        Color(0xFFE0CFD8), // 极淡薰衣草
      ]
    : [
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

/// 全局主题。
///
/// 两套主题共用同一组 `C.*`，`ThemeData` 的 base **都是 `light()`** ——
/// 露露缇雅版是亮色方案（明亮天空下的白裙绯带），不是深色模式。
/// Material 组件（Switch / 进度条 / 选择器）因此都按亮底取前景色，
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
    // 抽屉/对话框的面用卡面：露露缇雅版的页面底是天青，抽屉再铺天青
    // 就成了整片蓝；卡面是暖白，读起来才是「纸」。默认主题里两者同色。
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
    // 去掉 Material 3 默认的彩色涟漪，保持各自的观感
    textSelectionTheme: const TextSelectionThemeData(
      // 光标/拖柄用强调色：默认主题等于主文字色（黑白灰），
      // 露露缇雅版是深天青 —— 比纯黑光标多一点辨识度，又不抢戏
      cursorColor: C.accent,
      selectionHandleColor: C.accent,
    ),
  );
}
