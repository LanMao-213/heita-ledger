import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design/icons.dart';
import 'design/splash_spec.dart';
import 'design/theme_ctrl.dart';
import 'design/tokens.dart';
import 'dev/seed.dart';
import 'pages/home_shell.dart';
import 'store.dart';

/// 应用名单一来源 —— 以后改名只需要动这一处（以及 pubspec / Android 清单）
const String kAppName = '黑塔消费日记';

/// 版本号。**必须与 pubspec.yaml 的 version 前两段保持一致**
/// （pubspec 里的 `+N` 是构建号，不显示给用户）。
const String kAppVersion = '1.5.0';

class HeitaApp extends StatelessWidget {
  const HeitaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 换肤必须让 MaterialApp 重建：`theme: buildAppTheme()` 读的是
    // ThemeCtrl 里的运行时色板，不重建就永远停在出厂那一套。
    return AnimatedBuilder(
      animation: ThemeCtrl.i,
      builder: (context, _) {
        final dark = ThemeCtrl.i.dark;
        return MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // 状态栏图标跟着主题走：深色皮肤用浅色图标，浅色皮肤用深色图标。
          // 启动页内部的 AnnotatedRegion 会覆盖这一层 —— 那是刻意的，
          // 启动页固定深色，不跟着皮肤变（见 _SplashScreen）。
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  dark ? Brightness.light : Brightness.dark,
              statusBarBrightness: dark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness:
                  dark ? Brightness.light : Brightness.dark,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          // key 绑主题 id：id 一变整棵子树重建，446 处 `C.xxx` getter 才会
          // 重新求值。ThemeCtrl 的文档里写了这个代价（丢局部状态，刻意接受）。
          home: _BootGate(key: ValueKey(ThemeCtrl.i.id)),
        );
      },
    );
  }
}

/// 启动闸门：先开库、补记周期账单、载入数据，再进主界面。
///
/// 开屏画面就是品牌标志（用户选定的「D · 留白 88%」方案），
/// 不放任何文字。
class _BootGate extends StatefulWidget {
  const _BootGate({super.key});

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  late final Future<void> _boot;

  @override
  void initState() {
    super.initState();
    // 已经开过库就不再开一次：重复 boot 会再跑一遍补记与全量查询，
    // 在测试环境里（真实事件循环被假时钟挡住）还会直接卡在启动页。
    //
    // seedDemoDataIfNeeded 只在带 `--dart-define=HEITA_SEED=1` 的构建里做事，
    // 正式包是空操作（见 lib/dev/seed.dart）。
    final booting = Store.i.ready
        ? Future<void>.value()
        : Store.i.boot().then((_) => seedDemoDataIfNeeded());

    // 启动页**不跟着 boot 的快慢走**：快设备上 boot 一两百毫秒就结束，动画
    // 刚起步就会被 HomeShell 顶掉（用户看到的是一帧小图标，然后突然进主界面）；
    // 慢设备上又反过来，动画早放完还干等。这里取「boot 完成」与「最短停留」
    // 中较慢的一边，两种设备看到的过渡一致。
    _boot = Future.wait<void>([
      booting,
      Future<void>.delayed(kSplashMinVisible),
    ]).then((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _boot,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        if (snap.hasError) {
          return _BootError(error: '${snap.error}');
        }
        return const HomeShell();
      },
    );
  }
}

/// ⚠️ 启动页**不跟主题走**：不管用户选了哪套皮肤，开屏都是这一屏深色。
///
/// 理由和原生窗口有关：启动页的底色必须与 `launch_background.xml`、
/// `@color/splash_background` 逐值相同，冷启动时三屏才接得上。让启动页跟着
/// 皮肤变，就要给每套皮肤出一份 drawable，收益不抵复杂度。
///
/// 动画的形状：**底色先满、内容后淡入**。
///
/// ```
///   0ms    Scaffold 底色 #14161A 铺满（不参与淡入）
///   0–360ms 渐变 + 标志，同一个 Opacity 0 → 1，同一条 easeOutCubic
///   360ms  全不透明，静止
///   840ms  交棒 HomeShell（或 boot 更慢时取 boot）
/// ```
///
/// 这样就没有「先铺开一整块黑、再从中间冒出标志」那一段：首帧看到的不是黑，
/// 是上一屏（系统闪屏）那张同色底继续留着，然后渐变和标志一起浮上来。
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  /// 深色启动页的径向渐变。参数在 `design/splash_spec.dart`（Dart 侧唯一来源）。
  ///
  /// 它只在这一段出现 —— 原生窗口是纯色，不再和这里对齐渐变参数。
  static const gradient = kSplashGradient;

  /// 首帧就铺满整屏的底色，**不参与淡入**。
  ///
  /// 「不出现黑屏」全靠它：它和 Android 12+ 系统闪屏、Android 12 以下的原生
  /// 窗口、桌面图标背景是同一个值 `#14161A`。渐变 opacity=0 时露出的就是这层，
  /// 与上一屏逐像素相同，所以看起来只是「底色还在，图案正在浮现」。
  static const _backdrop = kSplashNativeBackground;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // 方案①「D · 留白 88%」：宽 = 屏宽 × 0.88，高按标志自身比例 455:944 推导，
    // 再夹一道屏高上限（平板 / 折叠屏）。三个参数见 design/splash_spec.dart，
    // 测试与实现共用同一份，不各写一套。
    final markH = splashMarkHeight(size);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 深色底必须配浅色状态栏图标，否则时间和电量会看不见
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _backdrop,
        body: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: kSplashFadeIn,
          curve: kSplashFadeCurve,
          // 渐变与标志由**同一个 v** 驱动，包在同一个 Opacity 里 ——
          // 「同步」是结构保证的，不是两处时长恰好写成一样。
          //
          // 不把 Opacity 下放到标志上、让渐变常显：那样首帧就是「渐变铺满 +
          // 标志透明」，正是用户说的「先铺开画面再从中间冒出 Logo」。
          builder: (context, v, child) => Opacity(
            // 测试读这个值判断淡入进度；不给 key 会先抓到路由过渡里的 Opacity。
            key: const ValueKey<String>('splash.fade'),
            opacity: v,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: gradient),
                ),
                Center(
                  child: Transform.scale(
                    // 只包标志，不包整屏：包整屏会让渐变四周缩进 4%，
                    // 露出一圈比渐变更暗的底色边。
                    key: const ValueKey<String>('splash.mark.settle'),
                    scale: kSplashMarkSettle + (1 - kSplashMarkSettle) * v,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
          // 深色底：标志取白色，火焰取亮红（C.overD），与原型 dark 模式一致。
          // 作为 child 传进去，v 每帧变化时只重建 Opacity 与 Transform，
          // 标志本身不重建。
          child: BrandMark(
            height: markH,
            fg: const Color(0xFFFFFFFF),
            flameColor: C.overD,
          ),
        ),
      ),
    );
  }
}

// 为什么用 opacity 而不是「插值渐变色」：两者在数学上等价（底色恒定时
// `v·渐变 + (1-v)·底色` 就是颜色插值），但 opacity 只有一处要改，而且标志
// （白 + 红火焰）本来也只能走透明度。代价是 360ms 的全屏 saveLayer ——
// 启动页只有一个矢量，这点开销可以接受；真要省，就得把标志的 fg/flameColor
// 也拿去和底色做插值，可读性换那几帧不值得。
//
// 两条不能碰的红线（都是真机踩出来的）：
//
// 1. **底色必须在 Scaffold 上，不能靠 Opacity 里的那一层**。曾经把整屏都
//    塞进 `Opacity(v)` 且 v 从 0 起，首帧渲染出来是全透明的 —— 真机冷启动
//    帧推进慢，动画停在第 0 帧，等 boot 完成直接跳主界面，标志一次没出现
//    （2026-10-28 的真机截图：一块空的深色）。
// 2. **不能只靠 boot 决定时长**。快设备上 boot 一两百毫秒就结束，淡入会被
//    直接切走。「最短停留」在 `_BootGate` 里兜（见 kSplashMinVisible）。

class _BootError extends StatelessWidget {
  const _BootError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Padding(
        padding: const EdgeInsets.all(S.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('启动失败', style: T.title),
            const SizedBox(height: S.sm),
            Text(error, style: T.body2),
          ],
        ),
      ),
    );
  }
}
