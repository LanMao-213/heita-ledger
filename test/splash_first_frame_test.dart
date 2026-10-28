// 启动页动画的守卫。
//
// 2026-10-28 真机反馈两连：
//   1. 系统闪屏画着小图标（159dp），Flutter 首帧是 718dp —— 差 4.51 倍，跳一下；
//   2. 把系统图标去掉后，首帧只剩渐变：标志当时包在 `Opacity(v)` 里，v 从 0 起，
//      而快设备上 boot 结束得太快，动画还没走就被 HomeShell 顶掉，标志一次没出现。
//
// 现在的设计是「以桌面图标为起点，长到定稿尺寸」，并且**用固定的最短停留时长
// 兜住 boot 的快慢**。这个文件钉三件事：
//   · 首帧就有标志，且已经是图标大小（不是 0、不是透明）；
//   · 动画会真的走完（起点 0.22 → 终点 1.0）；
//   · boot 很快时，启动页仍然留满足够久（否则第 2 条复现的就是「动画被切走」）。
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

/// 取标志当前的缩放值。
///
/// 用 key 精确定位启动页自己的那个 `Transform`：直接 `find.byType(Transform)`
/// 会先抓到 MaterialApp 路由过渡里的那个（缩放恒为 1.0），读出来的永远不是它。
double _markScale(WidgetTester tester) {
  final t = tester.widget<Transform>(
    find.byKey(const ValueKey<String>('splash.mark.grow')),
  );
  // 读矩阵的 m00（x 轴缩放）。不能用 getMaxScaleOnAxis()：它取三个轴的最大值，
  // 而 Transform.scale 的 z 轴恒为 1.0，于是永远返回 1 —— 这个坑踩过一次。
  return t.transform.storage[0];
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

  testWidgets('首帧：标志已经是图标大小、可见、且尺寸等于方案①', (tester) async {
    await pumpApp(tester);
    // 只 pump 一帧 —— 就是真机上「系统闪屏刚交棒」的那一帧。

    expect(find.byType(HomeShell), findsNothing,
        reason: '首帧就进了主界面，说明这个用例没测到启动页');
    expect(find.byType(BrandMark), findsOneWidget, reason: '首帧的启动页里没有标志');

    // 不能有任何透明度 < 1 的 Opacity 包着它（上一版的缺陷就死在这里：
    // Opacity(0) 让标志「在但不可见」，只查 findsOneWidget 完全看不出来）。
    final opacities = find
        .ancestor(of: find.byType(BrandMark), matching: find.byType(Opacity))
        .evaluate()
        .map((e) => (e.widget as Opacity).opacity);
    for (final o in opacities) {
      expect(o, greaterThanOrEqualTo(0.95),
          reason: '首帧的标志被 Opacity($o) 压成半透明/透明，用户看到的是空屏');
    }

    // 起点是「桌面图标大小」，不是 0：太小会像从无到有，太大就丢了过渡感。
    expect(_markScale(tester), closeTo(kSplashMarkStartFraction, 0.02),
        reason: '首帧的缩放值应为动画起点（约等于桌面图标大小）');

    // 布局尺寸仍是方案①（D · 留白 88%）：Transform 只改绘制不改布局。
    final size = tester.getSize(find.byType(BrandMark));
    expect(size.height, closeTo(splashMarkHeight(const Size(390, 844)), 0.5));
    expect(size.height / 844, closeTo(0.844, 0.01));

    await drainToHome(tester);
  });

  testWidgets('动画会走完：720ms 后铺到定稿尺寸', (tester) async {
    await pumpApp(tester);

    await tester.pump(kSplashGrowDuration ~/ 2);
    final mid = _markScale(tester);
    expect(mid, greaterThan(kSplashMarkStartFraction),
        reason: '半程还停在起点，说明动画没在推进');
    expect(mid, lessThan(1.0), reason: '半程就已经到终点了，说明时长被压缩了');

    await tester.pump(kSplashGrowDuration ~/ 2 + const Duration(milliseconds: 16));
    expect(_markScale(tester), closeTo(1.0, 0.001),
        reason: '动画结束时应当正好铺满定稿尺寸');

    await drainToHome(tester);
  });

  test('最短停留时长必须覆盖整段动画（否则必然被截断）', () {
    expect(kSplashMinVisible, greaterThanOrEqualTo(kSplashGrowDuration),
        reason: '最短停留比动画还短，动画一定播不完');
    expect(kSplashMarkStartFraction, lessThan(0.5),
        reason: '起点应当明显小于终态，否则看不出「放大」');
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
    // （动画 720ms 快到尾声、最短停留 840ms 还没到），启动页必须还在。
    // 没有最短停留这一道闸的话，boot 一完成就会被切走 —— 这里立刻变红。
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(BrandMark), findsOneWidget,
        reason: 'boot 一完成就把启动页切走了，快速启动的机器上动画根本播不完');
    expect(find.byType(HomeShell), findsNothing);

    // 过了最短停留时长才放行。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(HomeShell), findsOneWidget,
        reason: '过了最短停留时长还没进主界面，说明闸门没放开');
  });
}
