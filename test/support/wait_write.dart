import 'package:flutter_test/flutter_test.dart';

/// 等一次「界面触发的写入」真正落库。
///
/// 为什么需要（1.4.5）：写入改走 `WriteGateway` 之后，一次保存要经过
/// 「开事务 → 写流水 → 改余额 → 提交」四步，每步都是跨 isolate 的真实 I/O。
/// 在 `testWidgets` 的假时钟里，每一步的续体都要一次 `pump` 才会推进 ——
/// 只写一句 `runAsync(Future.delayed(200ms))` 然后立刻查库，会读到事务
/// 提交之前的状态（表现为「保存了但库里没有」）。
///
/// 这不是功能回归，是等待方式太脆：真实设备上没有假时钟，写入在几十毫秒内完成。
/// 这里把「真实时间」和「pump」交替跑若干轮，让事务走完。
Future<void> settleWrites(WidgetTester tester, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
}
