// 冷启动的测试辅助：等启动页走完、稳定停在主界面。
//
// 为什么要单独一个文件：启动页现在有**固定的最短停留时长**
// （`kSplashMinVisible`，一段 840ms 的真实 Timer），而真实数据库 I/O 在假时钟
// 下又不会自己回包。于是「pump 一次 / pump 50ms 就去找底部 tab」这类写法
// 会停在启动页上，报一个跟被测逻辑毫无关系的错（2026-10-28 加最短停留时
// detail_swipe / ui_polish 一共 5 条用例就是这么红的）。
//
// 两个都必须做：推进假时钟（让定时器响）+ 让出真实事件循环（让 I/O 回包）。
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/pages/home_shell.dart';

/// 反复 pump，直到主界面出现。
///
/// 默认最多 100 步 × 20ms = 2s 假时钟，足够覆盖 840ms 的最短停留 + 开库。
Future<void> pumpUntilHome(WidgetTester tester, {int maxSteps = 100}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (find.byType(HomeShell).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  await tester.pump();
}
