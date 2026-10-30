import 'package:flutter/material.dart';

/// 色板 —— 多套主题的唯一来源。
///
/// ## 为什么不再是 `static const`
///
/// 之前 [C] 里的颜色全是 `static const`，全仓库 446 处 `C.xxx` 写在
/// `const TextStyle(...)` / `const BoxDecoration(...)` 里。要想在 App 内
/// **实时**换整套配色（而不是出 N 个包），颜色就必须是运行时可读的值，
/// 那些 `const` 构造就得拆。这一次把它们拆掉了。
///
/// 拆的代价是可接受的：`const` 只是编译期常量优化，对一个 4 页的记账 App
/// 没有可测量的收益；换来的是「一套代码、多套皮肤、用户自己选」。
///
/// ## 加一套新皮肤要做什么
///
/// 1. 在这里加一个 [HeitaThemeId] 枚举值；
/// 2. 在 `kPalettes` 里给一份完整的 [Palette]（24 个 token 一个都不能少，
///    少一个就是运行时 null 色）；
/// 3. 在 `test/design/palette_test.dart` 里它会自动被对比度断言覆盖
///    （那份测试是遍历所有色板的，不需要为它单独写用例）；
/// 4. 名字会直接出现在「我的 → 偏好 → 主题」里。
enum HeitaThemeId {
  /// 中性冷灰（默认，1.4.21 起的视觉基线）
  cold,

  /// 纸墨暖米（1.4.6 那一版的色温）
  warm,

  /// 露露缇雅·泽金（天青底 + 暖白卡 + 绯紫字，2026-10-24 按「四色各归其位」重做）
  zeikin,

  /// 黑塔·永夜（深色）：靛黑底 + 鎏金
  tower,

  /// 血族·深红（深色）：酒红黑底 + 冰蓝
  crimson,

  /// 圣地（亮色）：冷白制服 + 钢灰武装 + 法庭铁红
  holy,
}

/// 一套完整配色。
///
/// `dark` 决定 [buildAppTheme] 用 `ThemeData.light()` 还是 `dark()` 做底，
/// 进而决定 Material 组件（Switch / 进度条 / 选择器）取哪套前景色。
class Palette {
  const Palette({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.dark,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.inkWash,
    required this.bg,
    required this.bg2,
    required this.bg3,
    required this.line,
    required this.line2,
    required this.over,
    required this.overD,
    required this.stage,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.todayMark,
    required this.onTodayMark,
    required this.accentWash,
    required this.cardShadow,
    required this.handle,
    required this.heroEdge,
    required this.cardBg,
    required this.heroBg,
    required this.chart,
  });

  final HeitaThemeId id;
  final String name;
  final String subtitle;
  final bool dark;

  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color ink4;
  final Color inkWash;

  final Color bg;
  final Color bg2;
  final Color bg3;
  final Color line;
  final Color line2;

  final Color over;
  final Color overD;
  final Color stage;

  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color todayMark;
  final Color onTodayMark;
  final Color accentWash;

  final Color cardShadow;
  final Color handle;
  final Color heroEdge;

  final Color cardBg;
  final Color heroBg;

  /// 图表十档，按重要度从强到弱（越靠前越主要）。
  ///
  /// 亮色板：由深到浅（最重要的切片最深）；
  /// 深色板：由浅到深（最重要的切片最亮）—— 关系反过来，但「靠明度分档
  /// 不靠色相」这条不变。
  final List<Color> chart;
}

/// 全部色板。顺序即「我的 → 偏好 → 主题」里的顺序。
const List<Palette> kPalettes = [
  _cold,
  _warm,
  _zeikin,
  _tower,
  _crimson,
  _holy,
];

/// 出厂默认主题。
///
/// 默认给「圣地 · 审判白」（亮色）。用户换过之后由 `ui.theme` 记住；
/// 老版本没有这个键 → 也是这一套。
///
/// 为什么从「黑塔 · 永夜」改成它（1.6.0）：
/// 1. 原生启动窗口只能取一个固定色（它读不到 SQLite 里的换肤设置）。默认深色皮肤时，
///    冷启动必然出现一次「浅窗口 → 深界面」的跳变，这是 1.5.0 真机实测留下的已知缺陷。
///    默认换成亮色后，把 `@color/app_background` 也一起换成这套的 `bg`（#E9ECF0），
///    默认路径上就没有跳变了 —— 两处必须同时改，只改一边只是把跳变从「大」变成「小」。
/// 2. 六套皮肤里只有它把「冷白底 + 钢灰武装 + 法庭铁红」做成了完整的亮色体系，
///    作为首次启动的第一印象更接近产品定位（制度化的可见性，不是装饰）。
///
/// 注意：`app.dart` 的 `ValueKey(ThemeCtrl.i.id)` 依赖这个值做首帧重建，
/// 改它不影响那套机制；但 `paletteOf()` 的兜底、`themeIdFromString()` 的回落
/// 都指向它，测试里断言默认值的用例要一起改。
const HeitaThemeId kDefaultTheme = HeitaThemeId.holy;

/// 按 id 取色板。
///
/// `kPalettes` 的顺序与 [HeitaThemeId] 的声明顺序一致（加皮肤时两者一起加），
/// 所以先按下标直取 —— 这是热路径：`C.*` 全库 541 处调用，滚动时每帧上千次。
/// 下标那一步带了一次 `id` 校验，两者不同步时会落到下面的线性兜底，
/// 宁可多走几轮，也不能因为加皮肤漏改一处就返回错色板。
Palette paletteOf(HeitaThemeId id) {
  final i = id.index;
  if (i < kPalettes.length && kPalettes[i].id == id) return kPalettes[i];
  for (final p in kPalettes) {
    if (p.id == id) return p;
  }
  // 走到了这里说明 id 是枚举里有、色板表里没有的新值（加皮肤时漏了第 2 步）
  for (final p in kPalettes) {
    if (p.id == kDefaultTheme) return p;
  }
  return kPalettes.first;
}

/// 把持久化字符串解析回 id。
///
/// 老版本没有 `ui.theme` 这个键 → 回落出厂默认（圣地 · 审判白），
/// 与 [kDefaultTheme] 保持同一处定义，不在这里再抄一遍枚举值。
HeitaThemeId themeIdFromString(String? s) {
  for (final t in HeitaThemeId.values) {
    if (t.name == s) return t;
  }
  return kDefaultTheme;
}

// ---------------------------------------------------------------- 1 冷灰
const Palette _cold = Palette(
  id: HeitaThemeId.cold,
  name: '中性冷灰',
  subtitle: '默认 · 对齐 iOS 分组列表',
  dark: false,
  ink: Color(0xFF14161A),
  ink2: Color(0xFF5C626B),
  ink3: Color(0xFF656A75),
  ink4: Color(0xFF838C9C),
  inkWash: Color(0x0F14161A),
  bg: Color(0xFFF3F4F7),
  bg2: Color(0xFFE8EAF0),
  bg3: Color(0xFFF6F7FA),
  line: Color(0xFFE2E5EA),
  line2: Color(0xFFCFD4DB),
  over: Color(0xFFB0302A),
  overD: Color(0xFFC0625A),
  stage: Color(0xFFD8DBE1),
  accent: Color(0xFF14161A),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFEEF0F4),
  todayMark: Color(0xFF14161A),
  onTodayMark: Color(0xFFFFFFFF),
  accentWash: Color(0xFFF0F2F5),
  cardShadow: Color(0x0D14161A),
  handle: Color(0xFFE7EAF0),
  heroEdge: Color(0xFFD8DDE5),
  cardBg: Color(0xFFFFFFFF),
  heroBg: Color(0xFFE8EBF1),
  chart: [
    Color(0xFF14161A),
    Color(0xFF2E3238),
    Color(0xFF454A52),
    Color(0xFF5C626B),
    Color(0xFF737A84),
    Color(0xFF8B929C),
    Color(0xFFA3AAB4),
    Color(0xFFBBC2CB),
    Color(0xFFD2D8E0),
    Color(0xFFE8ECF2),
  ],
);

// ---------------------------------------------------------------- 2 暖米
const Palette _warm = Palette(
  id: HeitaThemeId.warm,
  name: '纸墨暖米',
  subtitle: '1.4.6 的色温 · 米黄纸感',
  dark: false,
  ink: Color(0xFF1C1A17),
  ink2: Color(0xFF5B554D),
  ink3: Color(0xFF6D655B),
  ink4: Color(0xFF91897F),
  inkWash: Color(0x0F1C1A17),
  bg: Color(0xFFF5F2EA),
  bg2: Color(0xFFE4DED0),
  bg3: Color(0xFFEDE8DF),
  line: Color(0xFFE6E1D7),
  line2: Color(0xFFD5CDBC),
  over: Color(0xFFB13521),
  overD: Color(0xFFC46556),
  stage: Color(0xFFDBD8D1),
  accent: Color(0xFF1C1A17),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFEEEAE3),
  todayMark: Color(0xFF1C1A17),
  onTodayMark: Color(0xFFFFFFFF),
  accentWash: Color(0xFFF2F0EB),
  cardShadow: Color(0x0D1C1A17),
  handle: Color(0xFFE9E5DC),
  heroEdge: Color(0xFFD8D0C1),
  // 暖白而不是纯白：纯白压在米黄底上会往冷里走（白卡显得发灰发青），
  // 一屏里就成了两族色温。B 减 9 而已，肉眼是「白得暖」而不是「白得黄」。
  cardBg: Color(0xFFFFFDF6),
  heroBg: Color(0xFFECE7DE),
  chart: [
    Color(0xFF1C1A17),
    Color(0xFF3A3730),
    Color(0xFF57534A),
    Color(0xFF746E63),
    Color(0xFF918A7C),
    Color(0xFFADA695),
    Color(0xFFC9C2B0),
    Color(0xFFDCD5C4),
    Color(0xFFE9E3D5),
    // cardBg 由纯白改成暖白（#FFFDF6）后，这一档与卡面的差值从 1.147
    // 掉到 1.117（阈值 1.12），所以跟着压深一阶。
    Color(0xFFF2EDE3),
  ],
);

// --------------------------------------------------------- 3 露露缇雅·泽金
//
// 四原色：天青 #9AC7D3、暖白 #FDFBF8、绯红 #814864、薰衣草 #BC9DB1。
// 1.4.5 开发期出过这个包，后因「两个包太乱」删掉；现在改成 App 内一套皮肤。
//
// ## 2026-10-24 重做：从「有四个颜色」变成「四个颜色各管一件事」
//
// 上一版是照着四原色直接铺的，结果是四条互相打架的规则：
//   ① 绯紫既当**字色**（ink）又当**面**（heroBg #F4EBF0 粉底）—— 同一色相在同屏里
//      承担两种语义，读起来「脏」；
//   ② 卡是**暖白**（#FDFBF8），而底、概览卡全是冷天青 —— 冷暖在一屏里对撞；
//   ③ 四个色相的岗位没分清：薰衣草只是 ink4 的一个值，没有强的语义；
//   ④ 概览卡对底只有 1.04:1，比别的五套（1.09–1.19）都薄，那块卡几乎浮不起来。
//
// 这一版的分工只有一条规则，其余全部从它推出来：
//
//   **天青 = 面（底/卡/次级面/概览卡/强调）、绯紫 = 字（含超支）、薰衣草 = 弱化**
//
// 于是：
// - 绯紫再也不用当背景，`heroBg` 回到天青一族（#D7E8EE），对底 1.11:1；
// - 卡也留在天青一族（见 ⑤）—— 它本来就只是「最亮的一块」这个功能，
//   不该顺手给整屏再加一个色温；
// - 薰衣草的岗位是 `ink4`：非本月日期、占位符「—」、图表里的对比柱。
//   （`accentSoft` / `accentWash` 目前全库**没有调用点**，是预留 token，
//   不要把「有颜色」当成「有用处」—— 这两个值现在不产生任何视觉效果。）
// - `accent` 保持钢青 #3E7A8B（对卡 4.67:1，够压在进度条轨道上）。
//
// ⑤ **2026-10-24 第二轮（用户要求「卡片与背景统一」）**：上一稿卡还是暖白
//    （#FFFDFA）、底是冷天青，一屏里仍有两族色温。所以把卡也拉进天青一族：
//    #F9FCFD。对底 1.10:1 —— 与冷灰那套「白卡压浅灰底 1.10:1」是同一个手感，
//    卡照样浮得起来，但整屏只剩一个色温了。
//    代价：四原色里的暖白 #FDFBF8 退位（它原本只承担「最亮的一块」，
//    天青白完全接得住）。现在的四色其实是「天青 / 绯紫 / 薰衣草 / 天青白」。
const Palette _zeikin = Palette(
  id: HeitaThemeId.zeikin,
  name: '露露缇雅·泽金',
  subtitle: '天青为面 · 绯紫为字 · 薰衣草为记',
  dark: false,
  // 字：绯紫一族，四档只差明度
  ink: Color(0xFF4A2C3A),
  ink2: Color(0xFF6A5060),
  ink3: Color(0xFF786070),
  ink4: Color(0xFFA17F96),
  inkWash: Color(0x14814864),
  // 面：天青一族，四档明度递进（底 > 概览卡 > 次级面）
  bg: Color(0xFFE9F2F5),
  bg2: Color(0xFFDEEBF0),
  bg3: Color(0xFFF2F8FA),
  line: Color(0xFFD0E1E7),
  line2: Color(0xFFBFD4DC),
  // 超支：绯紫压到最饱和的一档，不和正文紫糊在一起
  over: Color(0xFF8E3A55),
  overD: Color(0xFFC25A6E),
  stage: Color(0xFFE3EBEE),
  // 强调：钢青，是「面」这一族里最重的一档
  accent: Color(0xFF3E7A8B),
  onAccent: Color(0xFFF9FCFD),
  // 薰衣草的岗位：图标底、今天标记
  accentSoft: Color(0xFFEFDDE6),
  todayMark: Color(0xFF3E7A8B),
  onTodayMark: Color(0xFFF9FCFD),
  accentWash: Color(0x1FBC9DB1),
  cardShadow: Color(0x0F4A2C3A),
  handle: Color(0xFFD5E3E9),
  heroEdge: Color(0xFFC4DAE2),
  // 卡片也回到天青一族（见上方第 ⑤ 条）：#F9FCFD 对底 1.10:1，
  // 与冷灰那套「白卡压浅灰底 1.10:1」是同一个手感。
  cardBg: Color(0xFFF9FCFD),
  heroBg: Color(0xFFD7E8EE),
  // 前七档是按「绯紫 → 天青 → 薰衣草」挑的多色相顺序，后三档收进天青灰。
  // ⚠️ 最后一档不能贴到 cardBg：最早给的是 #F2F7F9（对当时的暖白卡只有 1.05:1），
  // 第十个饼图切片等于消失了。卡面改成天青白之后又整体压深了一档
  // （#C2DBE2/#D4E6EC/#E4EFF3 → #BCD8E0/#CFE3EB/#E0ECF2），
  // 让末档对卡面有 1.17:1 而不是 1.14:1。见 palette_test 的断言。
  chart: [
    Color(0xFF4A2C3A),
    Color(0xFF814864),
    Color(0xFF3E7A8B),
    Color(0xFF6E8FA0),
    Color(0xFF9AC7D3),
    Color(0xFFBC9DB1),
    Color(0xFFD6BFCB),
    Color(0xFFBCD8E0),
    Color(0xFFCFE3EB),
    Color(0xFFE0ECF2),
  ],
);

// ------------------------------------------------------------ 4 黑塔·永夜
//
// 深色。机构色：靛黑 #13111C + 鎏金 #C9A24B + 宝石蓝 #2E5C8A。
// ⚠️ 深色的面关系与亮色**反过来**：底色最深，卡片高一档浮起来，
// 键帽再高一档；概览卡要「压下去」，所以它比页面底还深。
//
// ## 2026-10-24 修正：概览卡对页面底只有 1.04:1，那块卡是糊的
//
// 亮色板里「概览卡压下去」很好做（白纸上压一层灰）。深色板照搬就出事：
// bg 已经暗到 #0E0C14（L≈0.0056），再往下只剩纯黑，**天花板就是 1.08**。
// 而实测只有 1.04 —— 因为「压下去」的深度被另外两条约束吃掉了一半：
//
//   底/概览 = (卡/概览) ÷ (卡/底)
//
// 上面两条各要 ≥1.10 / ≥1.08，除出来只剩 1.04。这不是某个色值写错，
// 是三条约束在深色板这个低亮度区间里彼此挤压。泽金当时也是 1.04，
// 诊断记录在那一套的注释里（④），但只量了亮色板，漏了深色这两套。
//
// 两条改动：
// 1. `heroBg` 压到**纯黑**（深色界面里「最深」就是黑，AMOLED 上
//    不发光与近黑之间差别比数值更大）；
// 2. `bg` 微提一档（#0E0C14 → #100D17，肉眼分辨不出），把纯黑能给的
//    差值从 1.081 抬到 1.091 —— 不然刚好压在阈值上，刻度一动就红。
//
// `onAccent` / `onTodayMark` 原本直接复用了 bg 的数值，跟着一起改。
const Palette _tower = Palette(
  id: HeitaThemeId.tower,
  name: '黑塔 · 永夜',
  subtitle: '深色 · 靛黑底 + 鎏金',
  dark: true,
  ink: Color(0xFFF1EAF8),
  ink2: Color(0xFFC6BED6),
  ink3: Color(0xFFA79FBB),
  ink4: Color(0xFF6B6480),
  inkWash: Color(0x1FF1EAF8),
  bg: Color(0xFF100D17),
  bg2: Color(0xFF2A2636),
  bg3: Color(0xFF16131E),
  line: Color(0xFF2A2636),
  line2: Color(0xFF3B3650),
  over: Color(0xFFF0737F),
  overD: Color(0xFFFF8E96),
  stage: Color(0xFF07060A),
  accent: Color(0xFFD8B45C),
  onAccent: Color(0xFF100D17),
  accentSoft: Color(0xFF2A2636),
  todayMark: Color(0xFFD8B45C),
  onTodayMark: Color(0xFF100D17),
  accentWash: Color(0x1FD8B45C),
  cardShadow: Color(0x66000000),
  handle: Color(0xFF2A2636),
  heroEdge: Color(0xFF2A2636),
  cardBg: Color(0xFF1B1826),
  // 纯黑：概览卡是深色板里最深的一档，见文件顶部的修正说明。
  heroBg: Color(0xFF000000),
  // 十档由最亮收到中暗。⚠️ 最后一档不能继续往下收到卡面色 #1B1826：
  // 早先第十档就是 #1B1826（与卡面 1.00:1），那一片饼图是隐形的。
  // 所以深端的终点停在 #2E2846（对卡面 1.25:1），十档亮度均匀铺开。
  chart: [
    Color(0xFFF1EAF8),
    Color(0xFFDBD4E4),
    Color(0xFFC6BFD0),
    Color(0xFFB0A9BD),
    Color(0xFF9A94A9),
    Color(0xFF857E95),
    Color(0xFF6F6981),
    Color(0xFF59536E),
    Color(0xFF443E5A),
    Color(0xFF2E2846),
  ],
);

// ------------------------------------------------------------------ 6 圣地
//
// 亮色。圣地是三大阵营里**唯一的高明度阵营**：白不是纯洁，是制度化的可见性
// （「所有人都在同一套规则下被识别」）。红必须是「法庭铁红」而不是血红 ——
// 血红是血肉，铁红是制度，两者在同一屏里不能混。
const Palette _holy = Palette(
  id: HeitaThemeId.holy,
  name: '圣地 · 审判白',
  subtitle: '冷白制服 · 钢灰武装 · 法庭铁红',
  dark: false,
  ink: Color(0xFF171B21),
  ink2: Color(0xFF4C5763),
  // 辅助文字。早先是 #64707D，对冷白底只有 4.26:1 —— 12px 的 caption 用这个色，
  // 差一点点没过 AA。压到 #5E6A77 后是 4.66:1。
  ink3: Color(0xFF5E6A77),
  ink4: Color(0xFF78879A),
  inkWash: Color(0x0F171B21),
  bg: Color(0xFFE9ECF0),
  bg2: Color(0xFFDDE2E9),
  bg3: Color(0xFFF4F6F8),
  line: Color(0xFFDFE3E9),
  line2: Color(0xFFC6CCD6),
  over: Color(0xFF8C1C28),
  overD: Color(0xFFC9584F),
  stage: Color(0xFFD2D7DE),
  // 圣地的钢蓝。早先是 #4E8FB5：压在轨道 #DFE3E9 上只有 2.75:1（图形下限是 3），
  // 白字压在它上面也只有 3.55:1（日历「今天」那个圆点里是文字，要求 4.5）。
  // 压深到 #3A7BA1 后：对轨道 3.60:1、对白字 4.64:1。
  accent: Color(0xFF3A7BA1),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFDEEAF2),
  todayMark: Color(0xFF3A7BA1),
  onTodayMark: Color(0xFFFFFFFF),
  accentWash: Color(0xFFE7F0F6),
  cardShadow: Color(0x0A171B21),
  handle: Color(0xFFDFE3E9),
  heroEdge: Color(0xFFC6CCD6),
  cardBg: Color(0xFFFFFFFF),
  // 对页面底只有 1.079（阈值 1.08，差 0.001）—— 只量「对卡面」时看不出来。
  heroBg: Color(0xFFDBE0E7),
  chart: [
    Color(0xFF171B21),
    Color(0xFF2F3944),
    Color(0xFF485460),
    Color(0xFF616E7C),
    Color(0xFF7B8794),
    Color(0xFF94A0AC),
    Color(0xFFADB8C3),
    Color(0xFFC6CFD9),
    Color(0xFFDDE3EA),
    Color(0xFFEFF2F6),
  ],
);

// ------------------------------------------------------------ 5 血族·深红
//
// 深色。深酒红 #7A1224 的血统 + 月光冰蓝 #A6D8E8 的边光；
// 血红 #C81E3A 只留给超支（它是全站唯一带语义的色相，不能滥用）。
const Palette _crimson = Palette(
  id: HeitaThemeId.crimson,
  name: '血族 · 深红',
  subtitle: '深色 · 酒红黑底 + 冰蓝边光',
  dark: true,
  ink: Color(0xFFF7EEF0),
  ink2: Color(0xFFD6C2C6),
  ink3: Color(0xFFB8A0A6),
  ink4: Color(0xFF7A646A),
  inkWash: Color(0x1FF7EEF0),
  bg: Color(0xFF160C11),
  bg2: Color(0xFF332024),
  bg3: Color(0xFF1B1014),
  line: Color(0xFF332024),
  line2: Color(0xFF472C31),
  over: Color(0xFFF2778A),
  overD: Color(0xFFFF9AA6),
  stage: Color(0xFF0A0507),
  accent: Color(0xFFA6D8E8),
  onAccent: Color(0xFF160C11),
  accentSoft: Color(0xFF332024),
  todayMark: Color(0xFFA6D8E8),
  onTodayMark: Color(0xFF160C11),
  accentWash: Color(0x1FA6D8E8),
  cardShadow: Color(0x66000000),
  handle: Color(0xFF332024),
  heroEdge: Color(0xFF332024),
  cardBg: Color(0xFF221619),
  // 纯黑，同永夜。血族的 bg 更暗（L≈0.0038），不提底的话纯黑也只有
  // 1.075，够不到 1.08 —— 所以这一套连 bg 一起提了两阶。
  heroBg: Color(0xFF000000),
  // 同黑塔：深端停在 #362A2E（对卡面 1.30:1），不再往下贴到卡面色。
  chart: [
    Color(0xFFF7EEF0),
    Color(0xFFE2D8DA),
    Color(0xFFCCC2C5),
    Color(0xFFB7ADAF),
    Color(0xFFA1979A),
    Color(0xFF8C8184),
    Color(0xFF766B6F),
    Color(0xFF615659),
    Color(0xFF4B4044),
    Color(0xFF362A2E),
  ],
);
