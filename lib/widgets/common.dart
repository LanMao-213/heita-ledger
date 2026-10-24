import 'package:flutter/material.dart';

import '../data/cycle.dart';
import '../data/models.dart';
import '../data/ui_flags.dart';
import '../design/icons.dart';
import '../design/tokens.dart';

/// 卡片 —— 原型里 `.sec` 的对应实现。
///
/// 1.5.0 重做：从「白底 + 1px 描边」改成「白面 + 柔和投影 + 连续圆角」。
/// 旧做法的问题见 [C.cardBg] 的注释 —— 底与卡只差 1.06:1，边界只能靠描边撑，
/// 而 1.29:1 的描边又几乎看不见，整屏退化成「被细线切开的白板」。
/// 现在卡片靠 [E.low] 的柔和投影浮起来，[C.line] 只留给真正要「切断」的地方。
///
/// `sunken: true` 出「压下去」的那一档（概览卡、输入底），用 [C.heroBg] 且不加投影
/// —— 旧版 [C.heroBg] 全库只用了 1 次，「汇总压下、记录浮上」的层级等于没落地。
///
/// ## 内边距约定（只有三档，别再写别的数字）
///
/// - **内容卡（默认）**：`const EdgeInsets.all(S.lg)` = 四边 16。
///   绝大多数卡走这一档，**不要覆盖**。
/// - **列表卡**：`const EdgeInsets.symmetric(vertical: S.sm)` = 上下 8、左右 0。
///   卡内是若干行、行之间有分隔线、线要通到卡的左右边，所以卡自己不能有左右
///   内边距；行内部自己补 `horizontal: S.lg`，左右才和别的内容卡对齐。
/// - **空态 / 占位卡**：`const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.xxl)`
///   = 左右 16、上下 24。空态没有内容撑高度，靠上下留白把它撑成一块「还没有
///   内容」的面，而不是一条细条。
///
/// ⚠️ 禁止再出现 `EdgeInsets.all(S.md)`、`vertical: 10`、`horizontal: S.md`
/// 这类不成体系的值：旧代码里三套卡三套边距（20/8、16/8、16/12/4），
/// 卡与卡左右对不齐，整屏被切成一堆错位的矩形 —— 这正是这轮要收掉的东西。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.lg),
    // 左右从 20 收到 16：与明细日卡（16）对齐。旧版三套卡片三套边距
    // （20/8、16/8、16/12/4），屏幕被切成一堆对不齐的矩形。
    this.margin = const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.sm),
    this.sunken = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// true = 压下去的面（[C.heroBg]，无投影）；false = 浮起来的卡（[C.cardBg]，有投影）
  final bool sunken;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: ShapeDecoration(
        color: sunken ? C.heroBg : C.cardBg,
        shadows: sunken ? E.none : E.low,
        shape: Shape.squircle(R.card),
      ),
      child: child,
    );
  }
}

/// 分组标题
///
/// ## 留白节奏（与 [SectionCard] 的 margin 相加才是用户看到的间距）
///
/// [SectionCard] 的外边距是 `symmetric(horizontal: S.lg, vertical: S.sm)`（上下各 8），
/// 标题的 padding 要和它相加才等于屏幕上的实际距离：
///
/// | 关系 | 实际值 | 推导 |
/// |---|---|---|
/// | 标题 → 它领导的卡 | 12 | bottom 用 S.xs(4) + 卡的 margin 8 |
/// | 组内 卡 ↔ 卡 | 16 | 8 + 8 |
/// | 卡 → 下一个标题（组间距） | 32 | 卡的 margin 8 + top 用 S.xxl(24) |
///
/// **12 < 16 < 32 是刻意排出来的递进**：标题必须比组内间距更**贴住**它领导的
/// 那一组，用户才读得出「这个标题是下面这几张卡的」；组与组之间拉到项间距的
/// 2 倍，一屏才有粗细两种停顿，而不是一路均匀排下去。
///
/// 旧值是 20 / 16 / 28：标题离自己那一组（20）比组内两项之间（16）还远，
/// 标题看起来不属于它下面的组；而组间距（28）只比项间距大 1.75 倍，层级太弱
/// —— 「界面僵硬」在留白上就是这个：全是差不多的间距，没有呼吸感。
///
/// ⚠️ 改这里的上下 padding 等于改全库的分组节奏：动之前先把上面那张表的
/// 三个数重新算一遍。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 左右与 SectionCard 对齐到 16。上 24 = 与上一张卡的 margin 8 拼成 32 的
      // 组间距；下 4 = 拼成 12，比组内卡间距（16）更紧，标题才像「属于」下面那组。
      // 推导见类注释里的三行节奏表。
      padding: const EdgeInsets.fromLTRB(S.lg, S.xxl, S.lg, S.xs),
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
            // 轨道底：浅色版是 #EEF0F2，黑塔版是暗石棕（见 C.handle）
            Container(color: C.handle),
            FractionallySizedBox(
              widthFactor: v,
              // 未超支时用强调色：黑白灰版 accent == ink（视觉不变），
              // 黑塔版 accent == 咒法橙 —— 进度条是这版唯一大面积上色的地方
              child: Container(color: color ?? (over ? C.over : C.accent)),
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
            duration: M.fast,
            curve: M.standard,
            height: 34,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: on ? C.cardBg : Colors.transparent,
              shadows: on ? E.low : E.none,
              shape: Shape.squircle(R.sm),
            ),
            // 文字颜色也要跟着动，否则底色滑过去了、字色是硬切的
            child: AnimatedDefaultTextStyle(
              duration: M.fast,
              curve: M.standard,
              style: T.body.copyWith(
                fontWeight: FontWeight.w600,
                color: on ? C.ink : C.ink2,
              ),
              child: Text(label),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: C.bg2,
        shape: Shape.squircle(R.md),
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
  });

  final String from;
  final String to;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTapLabel;

  /// 双击区间文案 → 回到今天所在的期
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return SwipeFlip(
      onPrev: onPrev,
      onNext: onNext,
      onTap: onTapLabel,
      onDoubleTap: onReset,
      // Center + Row(min)：让「10月1日 – 10月31日」和日历图案作为一个整体居中，
      // 而不是各自被 Row 的剩余空间拉开。
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 窄屏或跨年长文案会被挤爆：交给 Flexible + FittedBox 收字号，
            // 宁可小一点也不要黄黑条。
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(longRangeLabel(from, to), maxLines: 1, style: T.titleSm),
                ),
              ),
            ),
            // 日历图案贴在标签右边：表达「点这里能挑日期」，
            // 而不是和标签并列的另一个入口。
            if (onTapLabel != null) ...[
              const SizedBox(width: S.xs),
              LineIcon('calendar', size: 18, color: C.ink3),
            ],
          ],
        ),
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

class MonthBar extends StatelessWidget {
  const MonthBar({
    super.key,
    required this.month,
    required this.onPrev,
    required this.onNext,
    this.onTapLabel,
    this.onReset,
  });

  final String month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTapLabel;

  /// 双击月份文案 → 回到本月
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return SwipeFlip(
      onPrev: onPrev,
      onNext: onNext,
      onTap: onTapLabel,
      onDoubleTap: onReset,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(Fmt.monthLabel(month), maxLines: 1, style: T.titleSm),
                ),
              ),
            ),
            if (onTapLabel != null) ...[
              const SizedBox(width: S.xs),
              LineIcon('calendar', size: 18, color: C.ink3),
            ],
          ],
        ),
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
          LineIcon(icon, size: 40, color: C.ink3),
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
    this.showChevron = true,
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

  /// 行尾那颗 ›。设置页里它表示「进入下一页」，在**动作菜单**里没有下一页，
  /// 画出来会让人以为点完还要再跳一层 —— 那些地方传 false。
  final bool showChevron;

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
            else if (onTap != null && showChevron)
              LineIcon('chevron_right', size: 20, color: C.ink3),
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
          style: T.body2.copyWith(color: C.bg),
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

/// 四个主 tab 共用的页头。
///
/// 改这一版之前，四页顶部是四种形态：明细是「账本名 + 筛选/搜索」、
/// 图表页**直接以分段控件开头**、计划页**连标题都没有**（第一行就是区间条）、
/// 我的页是 50px 品牌标志。同一个 App 的四页，内容起点各不相同。
///
/// 高度取 48 而不是 44：明细页右侧并排两个 `IconButton`，Material 的
/// 最小点击区就是 48，压到 44 会裁掉触控范围。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.leading,
    this.titleSuffix,
    this.actions,
  });

  final String title;

  /// 标题左侧（我的页的品牌标志）
  final Widget? leading;

  /// 标题紧右侧（明细页的账本切换箭头）
  final Widget? titleSuffix;

  /// 右侧动作（筛选 / 搜索 / 本期-本月切换）
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: S.lg),
          if (leading != null) ...[leading!, const SizedBox(width: S.sm)],
          Expanded(
            child: Row(
              children: [
                // 账本名是用户自己起的，可能很长：让它自己省略，
                // 不要把右侧的按钮挤出去
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.title,
                  ),
                ),
                ?titleSuffix,
              ],
            ),
          ),
          ?actions,
          // 右侧留 12 而不是 8：分段胶囊这类没有自带内边距的动作，
          // 贴到 8 会紧得像被屏幕切掉一角
          const SizedBox(width: S.md),
        ],
      ),
    );
  }
}
