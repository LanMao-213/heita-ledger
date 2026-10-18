import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design/icons.dart';
import 'design/tokens.dart';
import 'pages/home_shell.dart';
import 'store.dart';

/// 应用名单一来源 —— 以后改名只需要动这一处（以及 pubspec / Android 清单）
const String kAppName = '黑塔消费日记';

/// 版本号。**必须与 pubspec.yaml 的 version 前两段保持一致**
/// （pubspec 里的 `+N` 是构建号，不显示给用户）。
const String kAppVersion = '1.1.2';

class HeitaApp extends StatelessWidget {
  const HeitaApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      // App 本体是浅色界面 → 状态栏图标用深色。
      // 启动页内部的 AnnotatedRegion 会覆盖这一层，切回浅色界面时自动失效。
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _BootGate(),
    );
  }
}

/// 启动闸门：先开库、补记周期账单、载入数据，再进主界面。
///
/// 开屏画面就是品牌标志（用户选定的「D · 留白 88%」方案），
/// 不放任何文字。
class _BootGate extends StatefulWidget {
  const _BootGate();

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
    _boot = Store.i.ready ? Future<void>.value() : Store.i.boot();
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

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  /// 深色启动页的径向渐变。
  ///
  /// ⚠️ 这四个参数必须与
  /// `android/app/src/main/res/drawable-v21/launch_background.xml` 完全一致
  /// （中心 50%/44%、半径 95% 短边、#2C323E → #07080B）。任何一边改动都要同步，
  /// 否则冷启动时「原生窗口 → Flutter 首帧」会看到渐变位置跳动。
  static const gradient = RadialGradient(
    center: Alignment(0, -0.12), // y = (44% - 50%) * 2
    radius: 0.95,
    colors: [Color(0xFF2C323E), Color(0xFF07080B)],
    stops: [0.0, 1.0],
  );

  /// 渐变最外圈的颜色，用作无渐变时的兜底底色
  static const edge = Color(0xFF07080B);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // 用户选定的「D · 留白 88%」：标志宽 = 屏宽 × 0.88，
    // 高度按标志自身比例 455:944 推导；再夹一道屏高上限，防止平板上撑爆。
    final markH =
        math.min(size.width * 0.88 * 944 / 455, size.height * 0.92);

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
        backgroundColor: edge,
        body: SizedBox.expand(
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: gradient),
            child: Center(child: _SplashMark(height: markH)),
          ),
        ),
      ),
    );
  }
}

class _SplashMark extends StatelessWidget {
  const _SplashMark({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        // 从 0.94 放大到 1.0，配合淡入 —— 标志像从暗处浮出来
        child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
      ),
      // 深色底：标志取白色，火焰取亮红（C.overD），与原型 dark 模式一致
      child: BrandMark(
        height: height,
        fg: const Color(0xFFFFFFFF),
        flameColor: C.overD,
      ),
    );
  }
}

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
