import 'package:flutter/material.dart';

/// 横向翻页手势的**唯一实现**（4 个调用点：明细概览卡 / 计划周期条 /
/// 统计区间条 / 月条）。
///
/// 为什么单独一个组件：原版 `PeriodChip` 零调用点活到 1.4.5（每个页面各写一遍
/// 手势，改一处漏三处）。这里把「左右滑动 + 双击回今天 + 单击弹选择器」收成一份，
/// `check_dead_public.sh` 与 `swipe_flip_test` 一起盯着它有没有被真的用上。
///
/// 手势判定（§6.6）：
/// - 速度 ≥ [flipVelocity]（px/s）**或** 位移 ≥ [flipDistance]（px）→ 翻一页；
/// - 双击 → 回今天；
/// - 单击 → 弹选择器（日历）。
///
/// [enabled] 为 false 时**不注册横向识别器**，手势落回外层（明细页筛选态时，
/// 横向滑动要让给 `PageView` 切 tab）。
class SwipeFlip extends StatefulWidget {
  const SwipeFlip({
    super.key,
    required this.child,
    this.onPrev,
    this.onNext,
    this.onToday,
    this.onPick,
    this.enabled = true,
    this.flipDistance = 48,
    this.flipVelocity = 260,
  });

  final Widget child;

  /// 上一期（右滑）。
  final VoidCallback? onPrev;

  /// 下一期（左滑）。
  final VoidCallback? onNext;

  /// 回今天（双击）。
  final VoidCallback? onToday;

  /// 弹选择器（单击）。
  final VoidCallback? onPick;

  final bool enabled;
  final double flipDistance;
  final double flipVelocity;

  /// 目前有多少处调用点（测试断言「这个数 == 源码里的真实调用点数」）。
  ///
  /// 阶段 3 起：明细概览卡 / 图表区间条 / 计划周期条 = 3 处。
  /// 阶段 4 还会涨（月度条）。**改调用点必须同步改这里** ——
  /// 它是防「原版 `PeriodChip` 零调用活到 1.4.5」重演的唯一门禁。
  static int callSites = 3;

  @override
  State<SwipeFlip> createState() => _SwipeFlipState();
}

class _SwipeFlipState extends State<SwipeFlip> {
  double _dx = 0;
  double _downX = 0;

  void _end(DragEndDetails details) {
    final double velocity = details.velocity.pixelsPerSecond.dx;
    final bool fast = velocity.abs() >= widget.flipVelocity;
    final bool far = _dx.abs() >= widget.flipDistance;
    if (fast || far) {
      // 手指往左滑（dx < 0）＝ 看下一期
      if (_dx < 0 || velocity < 0) {
        widget.onNext?.call();
      } else {
        widget.onPrev?.call();
      }
    }
    _dx = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      // 不注册横向识别器：连 GestureDetector 都不套，让外层 PageView 拿走
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 从「按下点」开始量：识别器吃掉的那段 slop 也算进位移，
      // 这样「手指移动 48px」就是真的 48px（否则 48px 只能算出 30px）
      onHorizontalDragDown: (DragDownDetails d) {
        _downX = d.globalPosition.dx;
        _dx = 0;
      },
      onHorizontalDragUpdate: (DragUpdateDetails d) {
        _dx = d.globalPosition.dx - _downX;
      },
      onHorizontalDragEnd: _end,
      onTap: widget.onPick,
      onDoubleTap: widget.onToday,
      child: widget.child,
    );
  }
}
