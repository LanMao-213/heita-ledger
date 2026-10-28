// 启动页的视觉规格 —— 渐变、底色与标志尺寸的**唯一来源**。
//
// 为什么值得单独一个文件：这套参数有三个消费者，而其中两个此前各写了一份：
//
//   · `lib/app.dart` 的 `_SplashScreen`（Flutter 首帧，真正生效的那个）
//   · `test/splash_final_test.dart`（渲染出图；曾经抄了一遍 `markH` 公式，
//     还漏掉了屏高钳制 —— 于是改实现它不会红，守卫等于摆设）
//   · `android/.../values/colors.xml` + `drawable-v21/launch_background.xml`
//     （原生冷启动窗口；只共享**底色**，渐变不出现在原生侧）
//
// 原生那几份是 XML，跨语言共享不了，只能靠注释互相提醒 + `splash_spec_test`
// 读文件比对；Dart 侧则必须共用同一份常量，否则「改一处漏一处」的代价是
// 冷启动时两屏之间闪一次色差。
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
/// 它只属于 Flutter 这一段：原生窗口与系统闪屏都用纯色 [kSplashNativeBackground]
/// 打底（纯色才能和桌面图标背景、系统闪屏三方对齐），渐变是从那层底色上
/// 淡入出来的。所以这里**不再**要求与 `launch_background.xml` 逐参数一致 ——
/// 那份 drawable 现在是一个纯色 shape。
///
/// 中心 50%/44%、半径 95% 短边。#07080B 只作渐变最外圈，不再作为整屏底色：
/// 它太暗，一整屏铺开就是用户说的「先黑一下」。
const RadialGradient kSplashGradient = RadialGradient(
  center: Alignment(0, -0.12), // y = (44% - 50%) * 2
  radius: 0.95,
  colors: [Color(0xFF2C323E), Color(0xFF07080B)],
  stops: [0.0, 1.0],
);

/// 渐变最外圈的颜色，用作无渐变时的兜底底色。
const Color kSplashEdge = Color(0xFF07080B);

/// 启动页的**底色**：整条冷启动链路共用这一个值。
///
/// 四个地方必须是它，缺一处就会看到接缝：
///
///   1. 桌面图标背景 `ic_launcher_background`
///      （Android 12+ 的图标放大动画从这块色里长出来）
///   2. Android 12+ 系统闪屏 `splash_background`（系统只接受纯色）
///   3. Android 12 以下的启动窗口 `launch_background.xml`（纯色 shape）
///   4. Flutter 首帧 `_SplashScreen` 的 `Scaffold.backgroundColor`
///      —— 它**不参与淡入**，所以渐变 opacity=0 时露出的就是它
///
/// 值取的是 [kSplashGradient] 的**整屏平均值** `#14161C`（亮度 22.1），不是
/// 渐变中心色（中心 `#2C323E`，亮度 43.7）。平均值才对应「整屏看上去多亮」；
/// 取中心色的话，渐变淡入到中途会比底色更暗，反而闪一下。
///
/// `test/splash_spec_test.dart` 会读上面那三个原生文件逐字符比对。
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

// ── 启动页的节奏 ─────────────────────────────────────────────────────────
//
// 时间轴上只剩两拍：**底色 → 图案（同帧出现）→ 停留**。没有淡入，也没有缩放。
//
// 第一拍由原生窗口负责：它的背景是纯色 `#14161A`（= 系统闪屏色 = 桌面图标
// 背景色），所以「点图标 → 原生窗口 → 系统闪屏 → Flutter 首帧」四屏同色，
// 交接时看不出任何变化，也不存在一块「比启动页更黑的画面」。
//
// 第二拍是**硬切**：Flutter 首帧就把渐变和标志完整画出来，`opacity` 恒为 1。
// 2026-10-28 之前这里是 360ms 的同步淡入（渐变与标志共用一个 `Opacity` 一起
// 浮现）—— 技术上没错，但真机上「先看到一块纯色、等 0.36 秒图案才长出来」
// 被判定为不必要的拖沓，改成直接显示。
//
// 代价要认：硬切意味着「纯色帧 → 有图案帧」是一次跳变，慢了会像闪一下；
// 好处是绝不会出现「启动页只显示了一半就被切走」。两者都靠下面这一个时长兜。

/// 启动页最短停留时长。
///
/// **这一条是「无论启动快慢都能看到完整图案」的关键。** 之前启动页跟着
/// `Store.boot()` 走：快设备上 boot 只要一两百毫秒，图案还没画稳就被
/// `HomeShell` 顶掉；慢设备上又反过来，图案早就在了还得干等。固定一个下限，
/// 快慢两种设备看到的画面是一样的。
///
/// 560ms 是「硬切」之后重定的：图案在第 1 帧就已经完整，不需要再为动画留时间，
/// 这个时长纯粹是「让人看清并认出这是哪个 App」。原来的 840ms 是按
/// 「360ms 淡入 + 480ms 静止」算的，淡入去掉后按原样留 840 会显得画面卡住。
/// 低于 400ms 则像是闪一下就过，起不到标识作用。
const Duration kSplashMinVisible = Duration(milliseconds: 560);
