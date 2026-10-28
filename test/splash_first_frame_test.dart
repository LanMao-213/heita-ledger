// 启动页的守卫。
//
// 这块地方前后改了四版，每一版都被真机反馈打回一次，记下来免得再走回头路：
//   1. 系统闪屏画着小图标（159dp），Flutter 首帧是 718dp —— 差 4.51 倍，跳一下；
//   2. 把系统图标去掉后，首帧只剩渐变：标志当时包在 `Opacity(v)` 里，v 从 0 起，
//      而快设备上 boot 结束得太快，动画还没走就被 HomeShell 顶掉，标志一次没出现；
//   3. 改成「小标志放大到铺满」之后，观感变成「先铺开一整块近黑的画面，
//      然后中间冒出一个小标志再长大」；
//   4. 改成「渐变与标志同步淡入 360ms」之后，又嫌「先看到一块纯色、等 0.36 秒
//      图案才长出来」不必要 —— 最终定为**硬切**：图案在第 1 帧就完整。
//
// 现在钉四件事：
//   · 首帧有**不透明的品牌底色**，不是黑屏也不是全透明；
//   · 首帧的图案已经完整 —— 没有 Opacity、没有缩放，也没有正在跑的动画；
//   · 图案不会随时间变化（硬切的另一种说法）；
//   · boot 很快时，启动页仍留满 560ms，否则图案一闪而过。
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

/// 启动页那层底色。
///
/// 这是「不出现黑屏」的依据：它必须在首帧就是不透明实色，且等于系统闪屏的纯色。
/// 任何把它改成透明 / 去掉的改动都要在这里变红。
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

  testWidgets('首帧：底色不透明、图案已完整显示，没有半透明也没有缩放', (tester) async {
    await pumpApp(tester);
    // 只 pump 一帧 —— 就是真机上「系统闪屏刚交棒」的那一帧。

    expect(find.byType(HomeShell), findsNothing,
        reason: '首帧就进了主界面，说明这个用例没测到启动页');
    expect(find.byType(BrandMark), findsOneWidget, reason: '首帧的启动页里没有标志');

    // ── 底线一：首帧必须有一层不透明的实底 ──
    // 曾经把整屏都塞进 Opacity(0)，渲染出来全透明；现在底色放在 Scaffold 上。
    final backdrop = _backdrop(tester);
    expect(backdrop, kSplashNativeBackground,
        reason: '启动页底色必须等于系统闪屏色（#14161A），否则交接那一帧会闪一次色差');
    expect(backdrop!.a, 1.0,
        reason: '底色被做成半透明了：会露出窗口后面的黑');

    // ── 底线二：图案在首帧就已经是完整形态 ──
    // 硬切的意思是「没有过渡」，所以标志身上不能有 Opacity 压着，
    // 也不能有 Transform 缩放（曾经从 0.22 放大、后来 0.96 落定，都去掉了）。
    final opacityAncestors = find
        .ancestor(of: find.byType(BrandMark), matching: find.byType(Opacity))
        .evaluate()
        .map((e) => (e.widget as Opacity).opacity)
        .toList();
    expect(opacityAncestors, isEmpty,
        reason: '标志身上还挂着 Opacity(${opacityAncestors.join(", ")})，'
            '说明淡入没有拆干净，用户会看到「等一会儿图案才出来」');

    final transformAncestors = find
        .ancestor(of: find.byType(BrandMark), matching: find.byType(Transform))
        .evaluate()
        .length;
    expect(transformAncestors, 0,
        reason: '标志身上还挂着 Transform，说明缩放/落定没删干净');

    // ── 底线三：没有任何动画在跑 ──
    // `transientCallbackCount` 就是当前登记的 ticker 数。启动页里只要还有
    // 一个 AnimationController 在 forward，这个值就不为 0。
    expect(tester.binding.transientCallbackCount, 0,
        reason: '启动页还有动画在跑：硬切应当是零时长的');

    // 布局尺寸仍是方案①（D · 留白 88%）。
    final size = tester.getSize(find.byType(BrandMark));
    expect(size.height, closeTo(splashMarkHeight(const Size(390, 844)), 0.5));
    expect(size.height / 844, closeTo(0.844, 0.01));

    await drainToHome(tester);
  });

  testWidgets('图案不随时间变化：第 1 帧和 400ms 之后画的是同一张', (tester) async {
    await pumpApp(tester);

    final firstSize = tester.getSize(find.byType(BrandMark));
    final firstFg = tester.widget<BrandMark>(find.byType(BrandMark)).fgOverride;
    final firstOpacity = find.byType(Opacity).evaluate().length;

    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BrandMark), findsOneWidget);
    expect(tester.getSize(find.byType(BrandMark)), firstSize,
        reason: '标志尺寸随时间变了，说明还有缩放在跑');
    expect(tester.widget<BrandMark>(find.byType(BrandMark)).fgOverride, firstFg,
        reason: '标志颜色随时间变了');
    expect(find.byType(Opacity).evaluate().length, firstOpacity,
        reason: '中途冒出了 Opacity，说明有淡入');
    expect(tester.binding.transientCallbackCount, 0,
        reason: '400ms 了还有动画在跑');

    await drainToHome(tester);
  });

  test('停留时长要够看清，又不能拖：560ms 是定稿', () {
    // 图案第 1 帧就完整，所以这个数只负责「让人认出是哪个 App」。
    expect(kSplashMinVisible, const Duration(milliseconds: 560),
        reason: '改这个数之前先想清楚：低于 400ms 像闪一下就过，高于 800ms 像卡住');
    expect(kSplashMinVisible.inMilliseconds, greaterThanOrEqualTo(400));
    expect(kSplashMinVisible.inMilliseconds, lessThanOrEqualTo(800));
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

    // 推进 400ms（离 560ms 还有 160ms），启动页必须还在。
    // 没有最短停留这一道闸的话，boot 一完成就会被切走 —— 这里立刻变红。
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BrandMark), findsOneWidget,
        reason: 'boot 一完成就把启动页切走了，快速启动的机器上图案一闪而过');
    expect(find.byType(HomeShell), findsNothing);

    // 过了最短停留时长才放行。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(HomeShell), findsOneWidget,
        reason: '过了最短停留时长还没进主界面，说明闸门没放开');
  });
}
