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
    _boot = Store.i.ready
        ? Future<void>.value()
        : Store.i.boot().then((_) => seedDemoDataIfNeeded());
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
/// 理由是它和 Android 原生窗口的 `launch_background.xml` 是同一张图 ——
/// 冷启动时先出原生窗口、再接 Flutter 首帧，两边必须一模一样才不会跳。
/// 让启动页跟着皮肤变，就要给每套皮肤出一份 drawable，收益不抵复杂度。
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  /// 深色启动页的径向渐变。参数在 `design/splash_spec.dart`（Dart 侧唯一来源）。
  ///
  /// ⚠️ 那几个参数必须与
  /// `android/app/src/main/res/drawable-v21/launch_background.xml` 完全一致
  /// （中心 50%/44%、半径 95% 短边、#2C323E → #07080B）。原生那份是 XML，
  /// 跨语言共享不了，任何一边改动都要手工同步，
  /// 否则冷启动时「原生窗口 → Flutter 首帧」会看到渐变位置跳动。
  static const gradient = kSplashGradient;

  /// 渐变最外圈的颜色，用作无渐变时的兜底底色
  static const edge = kSplashEdge;

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
