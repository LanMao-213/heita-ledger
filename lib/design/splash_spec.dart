// 启动页的视觉规格 —— 渐变与标志尺寸的**唯一来源**。
//
// 为什么值得单独一个文件：这套参数有三个消费者，而其中两个此前各写了一份：
//
//   · `lib/app.dart` 的 `_SplashScreen`（Flutter 首帧，真正生效的那个）
//   · `test/splash_final_test.dart`（渲染出图；曾经抄了一遍 `markH` 公式，
//     还漏掉了屏高钳制 —— 于是改实现它不会红，守卫等于摆设）
//   · `android/.../drawable-v21/launch_background.xml`（原生冷启动窗口）
//
// 原生那份是 XML，跨语言共享不了，只能靠注释互相提醒；但 Dart 侧必须共用
// 同一份常量，否则「改一处漏一处」的代价是冷启动时渐变位置跳一下。
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 标志画布的高宽比（944 : 455）。
///
/// `BrandMark` 的绘制盒严格按路径 viewBox 的这个比例走，所以给定宽度就能
/// 反推出高度。屏幕比它更「肥」时，钳制由下面的 [kSplashMarkHeightCap] 负责。
const double kSplashMarkHeightPerWidth = 944 / 455;

/// 方案①「D · 留白 88%」：标志宽 = 屏宽 × 0.88。
///
/// 这是设计原型的四档里被选定的那档（A 满宽 100% / B 满屏 106% /
/// C 出血 112% / **D 留白 88%**）。选 D 的理由写在
/// `docs/设计资产/启动页.html`：标志宽高比 0.482 与手机屏 0.462 几乎一致，
/// 「撑满」在物理上可行，但留白更符合这套极简基调。
///
/// 改这个值之前先想清楚：`kSplashMarkHeightCap` 会独立生效，只放大倍率
/// 未必变大（16:9 机型上倍率早就被钳制吃掉了）。
const double kSplashMarkWidthRatio = 0.88;

/// 屏高上限：标志最高占屏高 92%，防止平板 / 折叠屏上撑爆。
///
/// 16:9 这类「矮屏」会先撞上这道上限，此时实际宽度会小于
/// [kSplashMarkWidthRatio]（约 79%）—— 这是有意为之，不是 bug。
const double kSplashMarkHeightCap = 0.92;

/// 深色启动页的径向渐变。
///
/// ⚠️ 这四个参数必须与
/// `android/app/src/main/res/drawable-v21/launch_background.xml` 完全一致
/// （中心 50%/44%、半径 95% 短边、#2C323E → #07080B）。原生窗口先出、Flutter
/// 首帧后接，两边不一致就会在交接的那一帧看到渐变位置跳一下。
const RadialGradient kSplashGradient = RadialGradient(
  center: Alignment(0, -0.12), // y = (44% - 50%) * 2
  radius: 0.95,
  colors: [Color(0xFF2C323E), Color(0xFF07080B)],
  stops: [0.0, 1.0],
);

/// 渐变最外圈的颜色，用作无渐变时的兜底底色。
const Color kSplashEdge = Color(0xFF07080B);

/// Android 12+ 系统闪屏（SplashScreen API）的纯色背景。
///
/// ⚠️ 必须与 `android/app/src/main/res/values/colors.xml` 的
/// `splash_background` 完全一致 —— `test/splash_spec_test.dart` 会读那个 XML
/// 做逐字符比对，所以这条注释不会失效。
///
/// 值取的是 [kSplashGradient] 的**整屏平均值** `#14161C`（亮度 22.1），不是
/// 渐变中心色（中心 `#2C323E`，亮度 43.7）。平均值才对应「整屏看上去多亮」，
/// 用它接 Flutter 首帧不会看到一次整体提亮；取中心色则会明显闪一下。
///
/// 与 `ic_launcher_background` 同值是有意的：桌面图标放大成启动窗口的那段
/// 动画里，两个色块要接得上。
const Color kSplashNativeBackground = Color(0xFF14161A);

/// 给定屏幕尺寸，算出标志的绘制高度。
///
/// 逻辑就两行：先按宽度定高，再用屏高封顶。抽成函数是为了让实现与测试
/// 走同一条路径 —— 测试自己抄公式的那种写法，等于给真相拍了张照片。
double splashMarkHeight(Size screen) => math.min(
      screen.width * kSplashMarkWidthRatio * kSplashMarkHeightPerWidth,
      screen.height * kSplashMarkHeightCap,
    );

/// 标志实际占屏宽的比例。
///
/// 撞上屏高上限时会小于 [kSplashMarkWidthRatio]；想看「有没有被钳制」用它。
double splashMarkWidthFraction(Size screen) =>
    splashMarkHeight(screen) / kSplashMarkHeightPerWidth / screen.width;

// ── 启动动画 ─────────────────────────────────────────────────────────────
//
// 为什么需要这三个常量：Android 12+ 的系统闪屏会先画一个小图标（带
// iconBackgroundColor 时可见内容约 160dp），再把窗口交给 Flutter 首帧，而首帧
// 的标志是 718dp —— 差 4.51 倍，冷启动时就是「小图标突然跳成大标志」。
//
// 把这段时间交给动画：Flutter 首帧从**图标大小**起画，再用 720ms 长到定稿尺寸。
// 起点的 0.22 不是随手取的 —— 390×844 上终态 712dp × 0.22 ≈ 157dp，与真机
// 测到的系统闪屏图标 159dp 基本重合，所以两段接得上。

/// 动画起点：标志高度占终态高度的比例（≈ 桌面图标的视觉大小）。
const double kSplashMarkStartFraction = 0.22;

/// 从起点长到终态用的时长。取 720ms 而不是 Android 默认的 ~500ms：
/// 这是在「感觉得到」和「不磨蹭」之间的取舍，真机上 500ms 会显得没展开完。
const Duration kSplashGrowDuration = Duration(milliseconds: 720);

/// 启动页最短停留时长。
///
/// **这一条才是「无论启动快慢都能完整呈现」的关键。** 之前启动页跟着
/// `Store.boot()` 走：快设备上 boot 只要一两百毫秒，动画刚起步就被
/// `HomeShell` 顶掉，用户看到的是一帧小图标然后突然进主界面；慢设备上又反过来，
/// 动画早放完了还得干等。固定一个下限，快慢两种设备看到的过渡是一样的。
///
/// 比 [kSplashGrowDuration] 多 120ms，让定稿尺寸停一下再交棒 —— 否则
/// 「长满」和「切走」在同一帧发生，看着像没长完就闪了。
const Duration kSplashMinVisible = Duration(milliseconds: 840);
