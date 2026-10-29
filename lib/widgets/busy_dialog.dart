import 'dart:async';

import 'package:flutter/material.dart';

import '../design/tokens.dart';

// ---------------------------------------------------------------------------
// 阻塞式进度：一段无法中断、也**看不出在进行**的等待
// ---------------------------------------------------------------------------
//
// ## 为什么必须有这个文件
//
// 加密 / 解密一个 20k 笔的库要 1.8 秒（低端机 3~5 秒），写库更久。这期间如果
// 界面一动不动，用户会：
//
//   1. 再点一次（于是同一份备份被加密两遍、或者恢复被触发两次）；
//   2. 以为崩了，从最近任务里划掉 App（写库中途被划掉，幸存的只有快照）；
//   3. 在极端情况下被系统判定 ANR。
//
// **一个 1.8 秒的冻结界面，体感上比 3 秒的转圈糟糕得多。** 所以性能预算可以
// 放宽（单次 2.5s），但必须配「让等待可见」—— 两者是一套东西，不能只放宽
// 门限不给出反馈。
//
// ## 三条硬要求
//
// 1. **不许用户点掉**：`barrierDismissible: false` + `PopScope(canPop: false)`。
//    点掉之后任务还在跑，用户以为取消了，实际只是失去了「它在跑」这个信息 ——
//    比没有弹窗更迷。
// 2. **必须在 finally 里关**：任务抛异常时弹窗不能留在屏幕上（那会把一个可
//    恢复的错误变成「界面卡死」）。
// 3. **pop 走事先取好的 NavigatorState**：`context` 在 await 之后可能已经失效
//    （页面被销毁），但那个 Navigator 还在。用 context 现场 `Navigator.of`
//    在页面已销毁时会抛错，或者弹错路由。

/// 跑一段耗时任务，期间显示一个不可点掉的进度弹窗。
///
/// [message] 要**说清在做什么、大概多久**（「正在加密…（约几秒）」），别只写
/// 「请稍候」—— 用户对「不知道要等多久」的忍耐度远低于对具体时长的忍耐度。
///
/// 任务抛异常时：弹窗先关掉，异常原样抛给调用方（调用方原来怎么处理错误，
/// 现在还是怎么处理）。
/// 类型参数叫 `TResult` 而不是 `T` / `R`：`design/tokens.dart` 里文字样式类叫
/// `T`、圆角类叫 `R`，同名的类型参数会把它们遮住 —— 这个文件凑巧还没用到，
/// 但下一个想在这里写 `T.body2` 的人会先撞一次。
Future<TResult> runWithBusy<TResult>(
  BuildContext context, {
  required String message,
  required Future<TResult> Function() task,
}) async {
  // 在 await 之前取好：await 之后 context 可能已经不属于活着的页面
  final navigator = Navigator.of(context, rootNavigator: true);

  // 不 await 这个 Future —— 它要等到 pop 才完成，await 就死锁了
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BusyDialog(message: message),
    ),
  );

  try {
    return await task();
  } finally {
    // 任务失败也要关：留着它等于把可恢复的错误变成「界面卡死」
    if (navigator.mounted && navigator.canPop()) navigator.pop();
  }
}

/// 进度弹窗本体。单独抽出来是为了能在测试里直接 pump 它。
class BusyDialog extends StatelessWidget {
  const BusyDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop: false 挡住返回键与手势返回。系统返回时 PopScope 会拦下这次 pop，
      // 界面留在原地 —— 任务还在跑，用户至少能看到「它在跑」。
      canPop: false,
      child: Dialog(
        backgroundColor: C.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(S.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: C.ink4),
              ),
              const SizedBox(width: S.md),
              Flexible(child: Text(message, style: T.body2)),
            ],
          ),
        ),
      ),
    );
  }
}
