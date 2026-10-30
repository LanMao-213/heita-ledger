import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design/theme_ctrl.dart';
import 'design/tokens.dart';
import 'dev/seed.dart';
import 'pages/home_shell.dart';
import 'store.dart';

/// 应用名单一来源 —— 以后改名只需要动这一处（以及 pubspec / Android 清单）
const String kAppName = '黑塔消费日记';

/// 版本号。**必须与 pubspec.yaml 的 version 前两段保持一致**
/// （pubspec 里的 `+N` 是构建号，不显示给用户）。
const String kAppVersion = '1.7.2';

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
/// 2026-10-28 起**没有品牌启动页**：等待期间只铺一层应用底色（[_BootBlank]），
/// boot 一结束就交棒 [HomeShell]，不设最短停留。
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
    // 在测试环境里（真实事件循环被假时钟挡住）还会一直停在等待画面。
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
          return _BootBlank();
        }
        if (snap.hasError) {
          return _BootError(error: '${snap.error}');
        }
        return const HomeShell();
      },
    );
  }
}

/// boot 期间的画面：**只铺一层应用底色**，不放标志、不放文字、不加动画。
///
/// 2026-10-28 删除了品牌启动页（`_SplashScreen`）。原来这里是一屏深色渐变 +
/// 标志，配 560ms 最短停留；现在目标只有一个——**不要在启动路上被看见**。
///
/// 底色必须在**第一帧**就画满，理由和当初删动画一样：Flutter 首帧渲染慢于
/// 引擎启动是常态，若这里返回 `SizedBox.shrink()`，那几帧就是一片纯黑
/// （窗口默认底色），看起来像崩溃。返回 `ColoredBox` 则首帧就是纸白，
/// 与原生 `@color/app_background`、主界面 `C.bg` 同色，整条衔接没有色块跳变。
///
/// **不给最短停留**。当初那 560ms 是为了"让人看清是哪个 App"，现在没有图案
/// 可看，停留只会变成白屏等待——boot 多快就多快进主界面。
class _BootBlank extends StatelessWidget {
  const _BootBlank();

  @override
  Widget build(BuildContext context) => ColoredBox(color: C.bg);
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
