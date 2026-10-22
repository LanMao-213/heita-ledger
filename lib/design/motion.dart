import 'package:flutter/material.dart';

import 'tokens.dart';

/// 通用动效组件。
///
/// 这一层存在的理由只有一个：把界面里的「0ms 硬切」拿掉。改这一轮之前全库
/// 没有一处 `AnimationController`，翻期、Tab 选中、删除记录、展开详情、大数字
/// 变化全是一帧换掉，观感就是「僵硬」。
///
/// 用法约定：
/// - 时长一律取 [M] 的分档值，这里不出现裸的 `Duration(milliseconds: ...)`；
/// - 只负责「怎么变」，不碰「变了什么」—— 数据流、业务判断仍然归 store / repo。
abstract final class Motion {
  /// 金额类文字纵向位移的距离（px）。
  static const moneyShift = 8.0;
}

/// 数字 / 金额变化：新的从下方滑入，旧的向上淡出。
///
/// 硬切最扎眼的地方就是大数字 —— 它视觉权重最大，一帧换掉会让人以为看错了。
///
/// 两个必须注意的点：
/// - child 要带随 [text] 变化的 `ValueKey`，否则 [AnimatedSwitcher] 判定
///   「还是同一个 widget」，根本不会触发切换（最常见的坑）；
/// - 进出方向相反，靠比较 `child.key` 和当前 [text] 区分是进场还是出场 ——
///   [AnimatedSwitcher] 只给一个 animation，出场时它是反向跑的。
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney({
    super.key,
    required this.text,
    this.style,
    this.duration = M.base,
    this.curve = M.standard,
    this.maxLines = 1,
    this.alignment = Alignment.centerLeft,
  });

  final String text;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;
  final int? maxLines;

  /// 新旧两帧叠在一起时的对齐方式。金额多数是左对齐，默认给 centerLeft。
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: curve,
      // 默认 layoutBuilder 是居中叠放；金额换位数时字宽会变，居中会左右晃，
      // 这里按调用方给的对齐方式叠，新旧帧的基线才不会跳。
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: <Widget>[...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<String>(text);
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final v = animation.value;
            return Opacity(
              opacity: v,
              child: Transform.translate(
                // 进场：从下方 8px 归位；出场：继续往上走 8px 同时淡出
                offset: Offset(
                  0,
                  (incoming ? Motion.moneyShift : -Motion.moneyShift) * (1 - v),
                ),
                child: child,
              ),
            );
          },
        );
      },
      child: Text(
        text,
        key: ValueKey<String>(text),
        style: style,
        maxLines: maxLines,
      ),
    );
  }
}

/// 进场：淡入 + 从下方 [offset] px 归位。
///
/// [delay] 用来做列表逐项错开（stagger）：第 n 项给 `n * 20ms`，一屏的卡就
/// 是「依次落位」而不是「整屏同时闪一下」。
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = M.base,
    this.delay = Duration.zero,
    this.offset = 8,
    this.curve = M.standard,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;
  final double offset;
  final Curve curve;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: widget.curve);
    _start();
  }

  Future<void> _start() async {
    if (widget.delay > Duration.zero) {
      await Future<void>.delayed(widget.delay);
    }
    // 列表滚得快时，delay 还没走完这一项可能已经被回收了
    if (!mounted) return;
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Opacity(
        opacity: _anim.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _anim.value)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 按下反馈：整体缩到 [scale]，抬手回弹。
///
/// 用 [AnimatedScale] 而不是 [Transform.scale] + 自己管 controller ——
/// 后者要处理 vsync 和 dispose，收益只是省两行。
///
/// 触控区按 44×44 兜底：包的是小图标时，外面那圈空白也要能点到。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.duration = M.tap,
    this.curve = M.spring,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Duration duration;
  final Curve curve;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      // opaque：空白区也算命中，44×44 的兜底才有意义
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: AnimatedScale(
          scale: _down ? widget.scale : 1.0,
          duration: widget.duration,
          curve: widget.curve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 展开 / 收起：高度动画（顶部对齐）+ 收起时内容淡出。
///
/// 单独用 [AnimatedSize] 只能动高度，内容会在第一帧就整块消失；单独用淡出
/// 则高度是瞬间塌的。两者叠起来才是「展开/收起」该有的样子。
///
/// 收起**结束**后旧内容必须真的从树上摘掉（[AnimatedSwitcher] 过渡完会移除
/// 上一帧），否则折叠态下 `find.text(...)` 还能找到里面的文字，折叠等于没折。
class AnimatedExpand extends StatelessWidget {
  const AnimatedExpand({
    super.key,
    required this.child,
    required this.expanded,
    this.duration = M.base,
    this.curve = M.standard,
  });

  final Widget child;
  final bool expanded;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      alignment: Alignment.topCenter,
      duration: duration,
      curve: curve,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: curve,
        switchOutCurve: curve,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            // 上一帧用 Positioned 挂出去：定位过的 child 不参与 Stack 的尺寸
            // 计算，收起时高度能立刻归零，[AnimatedSize] 才会和淡出同时开始 ——
            // 否则 Stack 会被旧内容顶住，等淡出跑完才开始收缩，变成两段动画。
            for (final c in previous)
              Positioned(top: 0, left: 0, right: 0, child: c),
            ?current,
          ],
        ),
        // 两个分支必须带不同的 key，AnimatedSwitcher 才认得这是一次切换
        child: expanded
            ? KeyedSubtree(key: const ValueKey('expand-open'), child: child)
            : const SizedBox(
                key: ValueKey('expand-shut'),
                width: double.infinity,
              ),
      ),
    );
  }
}
