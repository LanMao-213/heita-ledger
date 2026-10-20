import 'package:flutter/material.dart';

import '../data/cycle.dart';
import '../data/models.dart';
import '../data/ui_flags.dart';
import '../design/icons.dart';
import '../design/tokens.dart';

/// 白底描边卡片 —— 原型里 `.sec` 的对应实现
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.lg),
    this.margin = const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.sm),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: C.bg,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: child,
    );
  }
}

/// 分组标题
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.sm),
      child: Row(
        children: [
          Text(text, style: T.section),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 细进度条。超支时自动切成红色 —— 这是全应用**唯一**用红色的地方。
class Bar extends StatelessWidget {
  const Bar({
    super.key,
    required this.ratio,
    this.over = false,
    this.height = 5,
    this.color,
  });

  final double ratio;
  final bool over;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final v = ratio.isFinite ? ratio.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: const Color(0xFFEEF0F2)),
            FractionallySizedBox(
              widthFactor: v,
              child: Container(color: color ?? (over ? C.over : C.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 支出 / 收入 切换
class SegTabs extends StatelessWidget {
  const SegTabs({
    super.key,
    required this.value,
    required this.onChanged,
    this.left = '支出',
    this.right = '收入',
  });

  final TxnType value;
  final ValueChanged<TxnType> onChanged;
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, TxnType t) {
      final on = value == t;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? C.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: on ? C.bg : C.ink2,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        children: [item(left, TxnType.expense), item(right, TxnType.income)],
      ),
    );
  }
}

/// 月份选择栏
/// 周期条：「10-15 至 11-14」，**左右轻扫**翻一期，**双击**回到今天所在的期。
///
/// 与 [MonthBar] 并存，用途严格分开：
/// - 明细页 / 计划页看**期**（周期归集后的唯一口径）
/// - 统计页按用户切换在两者间换，幅度文案也不同（近 6 期 / 近 6 个月）
///
/// 标签显示两个具体日期而不是「10 月」—— 一期跨越两个月时，月份文案会骗人。
class CycleBar extends StatelessWidget {
  const CycleBar({
    super.key,
    required this.from,
    required this.to,
    required this.onPrev,
    required this.onNext,
    this.onTapLabel,
    this.onReset,
    this.onDark = false,
    this.trailing,
  });

  final String from;
  final String to;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTapLabel;

  /// 双击区间文案 → 回到今天所在的期
  final VoidCallback? onReset;

  /// 放在深色卡里时用（首页 hero）
  final bool onDark;

  /// 右侧附加按钮（首页放「日历」入口）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = onDark ? C.bg : C.ink;
    return SwipeFlip(
      onPrev: onPrev,
      onNext: onNext,
      onTap: onTapLabel,
      onDoubleTap: onReset,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 标签比月份条长（「10-15 至 11-14」），窄屏或带右侧按钮时会被挤爆：
          // 交给 Flexible + FittedBox 收字号，宁可小一点也不要黄黑条。
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  cycleLabel(from, to),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: label,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// 左右轻扫换页（换期 / 换月）。
///
/// 箭头去掉之后翻页只剩手势，所以这块要处理好两件事：
/// - **判定**：快速划一下按速度，慢慢拖按位移 —— 只看速度的话，手慢的人
///   拖了半屏也翻不动；只看位移的话，轻轻一弹就跳两页。
/// - **不误触**：阈值定在「明显想翻」的量级（速度 260 px/s 或位移 48 px），
///   手指抖一下不会把页面翻走。
///
/// 点按仍走 [onTap]（日历入口），双击走 [onDoubleTap]（回到当前）。
///
/// ⚠️ 同时注册 tap 与 doubleTap 的代价：单击要等一个双击判定窗口
/// （`kDoubleTapTimeout`，300ms）才会触发。日历确实会晚 0.3 秒弹出，
/// 这是「一个地方挂两种点击」的固有成本，不是卡顿。
///
/// ⚠️ [enabled] 为 false 时**不注册**横向识别器（不是注册了再 return）。
/// 这条差别很实在：明细页外面是 `PageView`，横向手势是它切 Tab 用的。
/// 注册了却不处理，等于在这一块挖掉「横滑切 Tab」；不注册，手势才会
/// 老老实实落到外层去。所以「筛选态下不翻期」必须靠不注册实现。
class SwipeFlip extends StatefulWidget {
  const SwipeFlip({
    super.key,
    required this.onPrev,
    required this.onNext,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.enabled = true,
  });

  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTap;

  /// 双击回到「当前」：手上翻了好几期之后，不用一期一期点回去
  final VoidCallback? onDoubleTap;

  /// 关掉横向翻页（点击手势不受影响）
  final bool enabled;

  final Widget child;

  @override
  State<SwipeFlip> createState() => _SwipeFlipState();
}

class _SwipeFlipState extends State<SwipeFlip> {
  static const _velocityThreshold = 260.0; // px/s
  static const _distanceThreshold = 48.0; // px

  double _dx = 0;

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final turned = v.abs() >= _velocityThreshold
        ? v
        : (_dx.abs() >= _distanceThreshold ? _dx * 10 : 0);
    _dx = 0;
    if (turned > 0) {
      widget.onPrev(); // 右滑 → 上一期
    } else if (turned < 0) {
      widget.onNext(); // 左滑 → 下一期
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onHorizontalDragStart: widget.enabled ? (_) => _dx = 0 : null,
      onHorizontalDragUpdate: widget.enabled ? (d) => _dx += d.delta.dx : null,
      onHorizontalDragEnd: widget.enabled ? _end : null,
      onHorizontalDragCancel: widget.enabled ? () => _dx = 0 : null,
      child: widget.child,
    );
  }
}

/// 「当前是哪一期」的标签：「10-15 → 11-14」，点它开日历挑日期。
///
/// 不加外框、不带日历图标 —— 它就在概览卡里，外面再套一层胶囊会把
/// 「一张卡里的一个数字」变成「卡里又长出来一个控件」。日历入口靠可点性
/// 本身表达，不必再画一遍。
///
/// ⚠️ 这个标签**自己不管翻期**：明细页的横滑挂在外层的概览卡上
/// （见 `DetailPage` 里的 `SwipeFlip`，方案 B —— 只热上部，列表正文
/// 仍然横滑切 Tab）。所以这里只有 onTap。
class PeriodChip extends StatelessWidget {
  const PeriodChip({
    super.key,
    required this.from,
    required this.to,
    required this.onTap,
    this.onDark = false,
  });

  final String from;
  final String to;
  final VoidCallback onTap;

  /// 放在深色卡里时用
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? C.bg : C.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  cycleLabel(from, to),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MonthBar extends StatelessWidget {
  const MonthBar({
    super.key,
    required this.month,
    required this.onPrev,
    required this.onNext,
    this.onTapLabel,
    this.onReset,
    this.onDark = false,
    this.trailing,
  });

  final String month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTapLabel;

  /// 双击月份文案 → 回到本月
  final VoidCallback? onReset;

  /// 放在深色卡里时用（首页 hero）：文字与箭头的对比度要跟着换
  final bool onDark;

  /// 右侧附加按钮（首页放「日历」入口）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = onDark ? C.bg : C.ink;
    return SwipeFlip(
      onPrev: onPrev,
      onNext: onNext,
      onTap: onTapLabel,
      onDoubleTap: onReset,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Fmt.monthLabel(month),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: label,
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// 空状态
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    this.icon = 'doc',
    required this.text,
    this.hint,
    this.padding = const EdgeInsets.symmetric(vertical: 34),
  });

  final String icon;
  final String text;
  final String? hint;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          LineIcon(icon, size: 40, color: C.ink4),
          const SizedBox(height: S.md),
          Text(text, style: T.body2),
          // 第二行是「下一步该干嘛」。留了开关（UiFlags.emptyHints），
          // 后期看效果决定要不要常驻
          if (hint != null && UiFlags.emptyHints) ...[
            const SizedBox(height: S.xs),
            Text(hint!, style: T.caption),
          ],
        ],
      ),
    );
  }
}

/// 「我的」页与设置页共用的列表行
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final String icon;
  final String title;
  final String? subtitle;

  /// 图标左侧的附加控件。目前只给分类管理页放拖拽手柄用 ——
  /// 有它的时候左边距收窄，避免手柄 + 图标挤在一起。
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? C.over : C.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(leading == null ? S.lg : S.xs, 14, S.lg, 14),
        child: Row(
          children: [
            ?leading,
            LineIcon(icon, size: 20, color: danger ? C.over : C.ink2),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: T.body.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: T.caption),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 20, color: C.ink4),
          ],
        ),
      ),
    );
  }
}

/// 底部弹出面板的把手 + 标题
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: S.md),
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: C.line2,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
          child: Row(
            children: [
              Text(title, style: T.title),
              const Spacer(),
              ?action,
            ],
          ),
        ),
      ],
    );
  }
}

/// 提示条
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: C.bg, fontSize: 13.5),
        ),
        backgroundColor: C.ink.withValues(alpha: 0.92),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(S.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
}
