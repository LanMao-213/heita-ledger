// 冷启动的测试辅助：一直 pump 到主界面出现。
//
// 为什么要单独一个文件：boot 是**真实数据库 I/O**，在假时钟下不会自己回包。
// 于是「pump 一次 / pump 50ms 就去找底部 tab」这类写法会停在等待画面上，
// 报一个跟被测逻辑毫无关系的错。
//
// 做法：推进假时钟（让帧调度继续）+ 让出真实事件循环（让 I/O 回包）。
//
// 2026-10-28 删除启动页后，这里**不再有最短停留定时器**（原来的
// kSplashMinVisible 560ms）。两个动作仍然都要做 —— 定时器没了，I/O 还在。
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
