// 启动页动画的守卫。
//
// 2026-10-28 真机反馈三连，一次比一次细：
//   1. 系统闪屏画着小图标（159dp），Flutter 首帧是 718dp —— 差 4.51 倍，跳一下；
//   2. 把系统图标去掉后，首帧只剩渐变：标志当时包在 `Opacity(v)` 里，v 从 0 起，
//      而快设备上 boot 结束得太快，动画还没走就被 HomeShell 顶掉，标志一次没出现；
//   3. 改成「小标志放大到铺满」之后，观感变成「先铺开一整块近黑的画面，
//      然后中间冒出一个小标志再长大」。
//
// 现在这一版是「底色先满、渐变与标志同步淡入」：
//
//   · 首帧上屏的是**不透明的品牌底色** #14161A（与系统闪屏 / 原生窗口同值），
//     不是黑屏，也不是全透明；
//   · 渐变与标志由同一个 `Opacity` 驱动，从 0 一起走到 1，没有先后；
//   · 标志只有 0.96 → 1.0 的轻微落定，不再从 22% 放大。
//
// 这个文件钉四件事：首帧有实底、二者同步淡入、淡入会真的走完、boot 很快时
// 启动页仍留满足够久。
//
// 和 `splash_final_test.dart` 的分工：那个自己拼一棵树出图，**测不到
// `_SplashScreen`**；这里 pump 真实入口 `HeitaApp`，走用户真会看到的那条路。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/design/icons.dart';
import 'package:ledger/design/splash_spec.dart';
import 'package:ledger/pages/home_shell.dart';
import 'package:ledger/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 淡入进度（0 → 1）。渐变与标志共用这一个值。
double _fade(WidgetTester tester) {
  final o = tester.widget<Opacity>(
    find.byKey(const ValueKey<String>('splash.fade')),
  );
  return o.opacity;
}

/// 取标志当前的落定缩放（0.96 → 1.0）。
///
/// 用 key 精确定位启动页自己的那个 `Transform`：直接 `find.byType(Transform)`
/// 会先抓到 MaterialApp 路由过渡里的那个（缩放恒为 1.0），读出来的永远不是它。
double _markScale(WidgetTester tester) {
  final t = tester.widget<Transform>(
    find.byKey(const ValueKey<String>('splash.mark.settle')),
  );
  // 读矩阵的 m00（x 轴缩放）。不能用 getMaxScaleOnAxis()：它取三个轴的最大值，
  // 而 Transform.scale 的 z 轴恒为 1.0，于是永远返回 1 —— 这个坑踩过一次。
  return t.transform.storage[0];
}

/// 启动页那层「不参与淡入」的底色。
///
/// 这是「不出现黑屏」的唯一依据：它必须在首帧就是**不透明**的实色，
/// 且等于系统闪屏的纯色。任何把它改成透明 / 去掉的改动都要在这里变红。
Color? _backdrop(WidgetTester tester) {
  final scaffold = tester.widget<Scaffold>(
    find
        .ancestor(of: find.byType(BrandMark), matching: find.byType(Scaffold))
        .first,
  );
  return scaffold.backgroundColor;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // 每个用例换一个库文件：ffi 的句柄在用例结束后不一定立刻释放，共用同一个
  // 文件名时第二个用例会在删除文件那一步报「另一个程序正在使用此文件」。
  var seq = 0;
  setUp(() async {
    await Db.close();
    Db.fileName = 'test_splash_${seq++}.db';
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const HeitaApp());
  }

  /// 收尾：把启动页挂着的定时器走完，并让真实数据库 I/O 有机会回包。
  ///
  /// 两件事都必须做，缺一个用例就红：
  ///   · 不推进假时钟 -> 结束时测试框架报 `Pending timers`（kSplashMinVisible
  ///     是个真实的 Timer，不会自己消失）；
  ///   · 只推进假时钟 -> boot 的真实 I/O 永远不完成，进不了主界面
  ///     （所以要和 runAsync 交替，和 boot_theme_sync_test 一个套路）。
  Future<void> drainToHome(WidgetTester tester) async {
    for (var i = 0; i < 60 && find.byType(HomeShell).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('首帧：整屏是不透明的品牌底色，渐变与标志都从 0 开始', (tester) async {
    await pumpApp(tester);
    // 只 pump 一帧 —— 就是真机上「系统闪屏刚交棒」的那一帧。

    expect(find.byType(HomeShell), findsNothing,
        reason: '首帧就进了主界面，说明这个用例没测到启动页');
    expect(find.byType(BrandMark), findsOneWidget, reason: '首帧的启动页里没有标志');

    // ── 硬底线：首帧必须有一层不透明的实底 ──
    // 上一版的缺陷是「整屏都塞进 Opacity(0)」，渲染出来全透明；这一版把底色
    // 放在 Scaffold 上，所以哪怕淡入还停在 0，用户看到的也是品牌底色，不是黑屏。
    final backdrop = _backdrop(tester);
    expect(backdrop, kSplashNativeBackground,
        reason: '启动页底色必须等于系统闪屏色（#14161A），否则交接那一帧会闪一次色差');
    expect(backdrop!.a, 1.0,
        reason: '底色被做成半透明了：淡入起点会露出窗口后面的黑');

    // 淡入起点是 0（渐变与标志都还没浮上来），这是设计，不是缺陷 ——
    // 前提就是上面那条：底下垫着实底。
    expect(_fade(tester), 0.0, reason: '淡入没有从头开始，用户会觉得画面「已经在了」');

    // 落定缩放的起点：0.96。不再是 0.22 —— 那个值就是「从中间冒出」的来源。
    expect(_markScale(tester), closeTo(kSplashMarkSettle, 0.001),
        reason: '标志起点缩放应等于 kSplashMarkSettle（接近终态，只轻微落定）');

    // 布局尺寸仍是方案①（D · 留白 88%）：Transform 只改绘制不改布局。
    final size = tester.getSize(find.byType(BrandMark));
    expect(size.height, closeTo(splashMarkHeight(const Size(390, 844)), 0.5));
    expect(size.height / 844, closeTo(0.844, 0.01));

    await drainToHome(tester);
  });

  testWidgets('渐变与标志在同一个淡入组里：两者的 opacity 不可能不同步', (tester) async {
    await pumpApp(tester);

    // 结构守卫：淡入用的那一个 Opacity，其子树里同时有径向渐变和标志。
    // 如果哪天有人把 Opacity 下放成「渐变常显 + 标志单独淡入」，
    // 这里立刻变红 —— 那正是用户看到的「先铺开画面，再从中间冒出 Logo」。
    final fade = find.byKey(const ValueKey<String>('splash.fade'));
    expect(
      find.descendant(of: fade, matching: find.byType(DecoratedBox)),
      findsWidgets,
      reason: '淡入组里没有背景层，说明渐变没跟着一起淡入',
    );
    expect(
      find.descendant(of: fade, matching: find.byType(BrandMark)),
      findsOneWidget,
      reason: '标志不在淡入组里，说明它和背景不是同步淡入的',
    );

    final decorated = tester.widgetList<DecoratedBox>(
      find.descendant(of: fade, matching: find.byType(DecoratedBox)),
    );
    final hasGradient = decorated.any((d) {
      final deco = d.decoration;
      return deco is BoxDecoration && deco.gradient == kSplashGradient;
    });
    expect(hasGradient, isTrue,
        reason: '淡入组里没有 kSplashGradient，说明背景渐变被挪到了别处');

    // 标志的祖先里只有那一个 Opacity，没有第二个把关。
    final ancestors = find
        .ancestor(of: find.byType(BrandMark), matching: find.byType(Opacity))
        .evaluate()
        .map((e) => (e.widget as Opacity).opacity)
        .toList();
    expect(ancestors, isNotEmpty);
    expect(ancestors, everyElement(closeTo(0.0, 1e-9)),
        reason: '标志身上还有别的 Opacity 压着，同步性就不成立了');

    await drainToHome(tester);
  });

  testWidgets('淡入会走完：360ms 后完全浮现，标志停在 1.0', (tester) async {
    await pumpApp(tester);

    await tester.pump(kSplashFadeIn ~/ 2);
    final mid = _fade(tester);
    expect(mid, greaterThan(0.0), reason: '半程还在 0，说明淡入没在推进');
    expect(mid, lessThan(1.0), reason: '半程就已经满不透明了，说明时长被压缩了');
    final midScale = _markScale(tester);
    expect(midScale, greaterThan(kSplashMarkSettle), reason: '缩放没跟着淡入走');
    expect(midScale, lessThan(1.0), reason: '缩放半程就到终点了');

    await tester.pump(kSplashFadeIn ~/ 2 + const Duration(milliseconds: 16));
    expect(_fade(tester), closeTo(1.0, 0.001), reason: '淡入结束时应当完全不透明');
    expect(_markScale(tester), closeTo(1.0, 0.001),
        reason: '落定结束时应当正好是定稿尺寸');

    await drainToHome(tester);
  });

  test('时序常量自洽：淡入要能被最短停留完整兜住，且缩放幅度足够小', () {
    expect(kSplashMinVisible, greaterThanOrEqualTo(kSplashFadeIn),
        reason: '最短停留比淡入还短，淡入一定播不完');

    // 淡入太短会「啪」地亮起来，太长会磨蹭。
    expect(kSplashFadeIn.inMilliseconds, greaterThanOrEqualTo(200));
    expect(kSplashFadeIn.inMilliseconds, lessThanOrEqualTo(600));

    // 幅度必须小到看不出「放大」，否则又回到「从中间冒出一个小标志」。
    expect(kSplashMarkSettle, lessThan(1.0));
    expect(kSplashMarkSettle, greaterThanOrEqualTo(0.9),
        reason: '起点缩放小于 0.9 就重新变成「冒出来」，这轮改动就白做了');
  });

  testWidgets('boot 已完成后，启动页仍要停满最短时长才交棒', (tester) async {
    await pumpApp(tester);

    // 关键：把 boot 真正跑完（真实 I/O 要靠 runAsync），但 pump 的时长是 0
    // —— 假时钟不走，`kSplashMinVisible` 那个 Timer 就不会响。
    // 于是此刻唯一还挡着主界面的，只剩「最短停留」这一道闸。
    for (var i = 0; i < 100 && !Store.i.ready; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(Store.i.ready, isTrue, reason: 'boot 没跑完，这个用例的前提不成立');

    // 这是「无论启动快慢都能完整呈现」的判据：boot 已经完成，再推进 700ms
    // （淡入 360ms 早就结束、最短停留 840ms 还没到），启动页必须还在。
    // 没有最短停留这一道闸的话，boot 一完成就会被切走 —— 这里立刻变红。
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(BrandMark), findsOneWidget,
        reason: 'boot 一完成就把启动页切走了，快速启动的机器上看不到完整淡入');
    expect(find.byType(HomeShell), findsNothing);
    // 而且这时候应该是全亮的静止画面，不是半透明 —— 否则「停留」是假的。
    expect(_fade(tester), closeTo(1.0, 0.001),
        reason: '停留阶段还没浮现完，等于把静止的那口气也省了');

    // 过了最短停留时长才放行。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(HomeShell), findsOneWidget,
        reason: '过了最短停留时长还没进主界面，说明闸门没放开');
  });
}
