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

/// 等到 `done()` 成立为止（真实时间和 pump 交替，最多 [maxRounds] 轮）。
///
/// 和 [settleWrites] 的区别：那个等**固定轮数**，够不够全看机器忙不忙。
/// 一条「点恢复 → afterCategoryChange → 三次真实查询 → 重建列表」的链路，
/// 满载并行跑全量时 20 轮 × 20ms 曾经走不完，测试体先结束、剩下的续体撞上
/// 已关闭的库抛 `database_closed` —— 表现就是「偶发 flaky，约一半概率红」。
///
/// 这里改成等**条件真的成立**：成立即刻返回（通常比固定轮数还快），
/// 不成立就一路等到超时再 `fail`，把「慢」和「坏」区分开 ——
/// 慢会通过，坏会带着清楚的理由失败。
Future<void> settleUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxRounds = 400,
}) async {
  for (var i = 0; i < maxRounds; i++) {
    await tester.pump();
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('等待界面条件成立超时（$maxRounds 轮 × 10ms）');
}

/// 等到某个计数器连续 [quietRounds] 轮**都不再变化**为止。
///
/// 用途：判断一条「界面回调里跑的多步异步链」是不是真的结束了。
///
/// 为什么要这个而不是数通知次数：`afterCategoryChange` 是
/// `_loadCategories()` → `loadCycle()` → `loadStats()` 三步串起来的，
/// 我一开始以为会发 3 次通知，写死 `>= 3` —— 实测只有 2 次（其中一步
/// 不 notify，具体哪步会随实现变），条件永远不成立，用例直接超时。
/// 按次数写死等于把实现细节抄进测试；按「不再动了」判断才是真的在问
/// 「还有没有挂起的活」。
///
/// 也不能只看界面：界面在中途就更新了（第一步之后就 notifyListeners），
/// 后面的真实数据库查询还没跑完，测试体一结束就会撞上下一条用例的
/// `Db.close()`。所以两者要合起来用 —— 先 `settleUntil` 等界面正确，
/// 再 `settleQuiet` 等链尾。
Future<void> settleQuiet(
  WidgetTester tester,
  int Function() counter, {
  int quietRounds = 30,
  int maxRounds = 400,
}) async {
  var last = counter();
  var quiet = 0;
  for (var i = 0; i < maxRounds; i++) {
    await tester.pump();
    final now = counter();
    if (now == last) {
      quiet++;
      if (quiet >= quietRounds) return;
    } else {
      quiet = 0;
      last = now;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('等待异步链静默超时（$maxRounds 轮 × 10ms）');
}
