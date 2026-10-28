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

    // 启动页**不跟着 boot 的快慢走**：快设备上 boot 一两百毫秒就结束，图案
    // 会一闪而过（用户只看到一次跳变，来不及认出是哪个 App）；慢设备上又反过来，
    // boot 早就完了还要干等。这里取「boot 完成」与「最短停留」中较慢的一边，
    // 两种设备看到的是一样的画面。
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
/// `@color/splash_background` 逐值相同，冷启动时四屏才接得上。让启动页跟着
/// 皮肤变，就要给每套皮肤出一份 drawable，收益不抵复杂度。
///
/// 时间轴上只有两拍，**没有动画**：
///
/// ```
///   0ms    Scaffold 底色 #14161A + 渐变 + 标志，同一帧完整画出（opacity 恒为 1）
///   560ms  交棒 HomeShell（或 boot 更慢时取 boot）
/// ```
///
/// 2026-10-28 这里先后试过「小标志放大到铺满」和「渐变与标志同步淡入」两版，
/// 都被真机反馈否掉了：前者是「从中间冒出一个小标志」，后者是「先看到一块纯色、
/// 等 0.36 秒图案才长出来」。现在直接硬切 —— 图案在首帧就是完整的。
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  /// 深色启动页的径向渐变。参数在 `design/splash_spec.dart`（Dart 侧唯一来源）。
  ///
  /// 它只在这一段出现 —— 原生窗口是纯色，不再和这里对齐渐变参数。
  static const gradient = kSplashGradient;

  /// 铺满整屏的底色，压在渐变下面。
  ///
  /// 它和 Android 12+ 系统闪屏、Android 12 以下的原生窗口、桌面图标背景是
  /// 同一个值 `#14161A`，所以「点图标 → 原生窗口 → 系统闪屏 → 这一帧」四屏同色，
  /// 交接时看不出变化。渐变虽然覆盖了整屏，这层仍不能删：它是首帧万一没画出
  /// 渐变时的兜底，也是「这个底色值改一处就全链路生效」的那个锚点。
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
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(gradient: gradient),
            ),
            Center(
              child: BrandMark(
                height: markH,
                // 深色底：标志取白色，火焰取亮红（C.overD），与原型 dark 模式一致。
                //
                // 这个白是**定稿值**：2026-10-28 比过三档（#FFFFFF / #E4E7EC /
                // #D6DBE3 + 压光渐变），选了不调暗的那一版 —— 深底上降亮度会让
                // 标志发灰，而「白得醒目」正是这个开屏唯一的表达。
                fg: const Color(0xFFFFFFFF),
                flameColor: C.overD,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 为什么这里没有任何动画：
//
// 首帧就必须是完整图案，所以既不能用 `Opacity(v)`、也不能用 `Transform.scale`。
// 曾经的坑要记着：把整屏塞进 `Opacity(v)` 且 v 从 0 起，首帧渲染出来是全透明的
// —— 真机冷启动帧推进慢，动画停在第 0 帧，等 boot 完成直接跳主界面，标志一次
// 没出现（2026-10-28 的真机截图：一块空的深色）。
//
// 现在图案在第 1 帧就画完，唯一的时序只剩「停多久」：由 `_BootGate` 里的
// kSplashMinVisible（560ms）与 boot 取较慢的一边。少了这一道，快设备上 boot
// 一两百毫秒就结束，图案会一闪而过。

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
