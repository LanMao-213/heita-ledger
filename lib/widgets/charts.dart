import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/tokens.dart';

/// 环形图。切片颜色按金额从大到小套灰阶 —— 越深越主要，
/// 这样即使全是黑白灰也能一眼看出主次。
class Donut extends StatelessWidget {
  const Donut({
    super.key,
    required this.slices,
    this.size = 132,
    this.thickness = 15,
    this.center,
  });

  final List<({int value, Color color})> slices;
  final double size;
  final double thickness;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(slices: slices, thickness: thickness),
          ),
          ?center,
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.thickness});

  final List<({int value, Color color})> slices;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (a, b) => a + b.value);
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - thickness) / 2,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..isAntiAlias = true;

    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = C.bg2);
      return;
    }

    // 从 12 点方向开始顺时针铺开
    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = s.value / total * math.pi * 2;
      // 相邻切片之间留一点缝，避免同色相邻时糊成一片
      final gap = slices.length > 1 ? math.min(0.02, sweep * 0.08) : 0.0;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.0001),
        false,
        paint..color = s.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.thickness != thickness ||
      old.slices.length != slices.length ||
      !_same(old.slices, slices);

  static bool _same(
    List<({int value, Color color})> a,
    List<({int value, Color color})> b,
  ) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value || a[i].color != b[i].color) return false;
    }
    return true;
  }
}

/// 每日支出柱状图。当月没有数据的日子留空，保持 x 轴连续。
class DailyBars extends StatelessWidget {
  const DailyBars({
    super.key,
    required this.dayCount,
    required this.values,
    this.height = 76,
    this.highlightDay,
    this.onDayTap,
  });

  final int dayCount;
  final Map<int, int> values;
  final double height;
  final int? highlightDay;

  /// 点了第几天（1 起）。给了回调才接手势，否则保持纯展示。
  final ValueChanged<int>? onDayTap;

  @override
  Widget build(BuildContext context) {
    final chart = SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarsPainter(
          dayCount: dayCount,
          values: values,
          highlightDay: highlightDay,
        ),
        size: Size.infinite,
      ),
    );
    if (onDayTap == null) return chart;

    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            if (dayCount <= 0 || c.maxWidth <= 0) return;
            final slot = c.maxWidth / dayCount;
            final day = (d.localPosition.dx / slot).floor() + 1;
            if (day >= 1 && day <= dayCount) onDayTap!(day);
          },
          child: chart,
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.dayCount,
    required this.values,
    this.highlightDay,
  });

  final int dayCount;
  final Map<int, int> values;
  final int? highlightDay;

  @override
  void paint(Canvas canvas, Size size) {
    if (dayCount <= 0) return;

    final maxV = values.values.fold<int>(0, (a, b) => b > a ? b : a);
    final slot = size.width / dayCount;
    final barW = math.max(2.0, math.min(9.0, slot * 0.52));

    for (var d = 1; d <= dayCount; d++) {
      final v = values[d] ?? 0;
      final cx = slot * (d - 0.5);
      final isToday = d == highlightDay;

      if (v <= 0) {
        // 无支出的日子画一个极淡的底座，保持节奏感
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW / 2, size.height - 3, barW, 3),
            Radius.circular(barW / 2),
          ),
          Paint()..color = C.line,
        );
        continue;
      }
      final h = maxV <= 0 ? 3.0 : math.max(4.0, v / maxV * size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - barW / 2, size.height - h, barW, h),
          Radius.circular(barW / 2),
        ),
        Paint()..color = isToday ? C.ink : C.ink3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.dayCount != dayCount ||
      old.highlightDay != highlightDay ||
      !_sameMap(old.values, values);

  static bool _sameMap(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

/// 分类占比横向排行（明细页用）
class CatRankRow extends StatelessWidget {
  const CatRankRow({
    super.key,
    required this.stat,
    required this.ratio,
    required this.color,
    this.onTap,
  });

  final CatStat stat;
  final double ratio;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: S.md),
            SizedBox(
              width: 56,
              child: Text(
                stat.name,
                style: T.body2.copyWith(color: C.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: S.sm),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: C.bg2,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: S.md),
            Text(
              Fmt.money(stat.totalCents),
              style: T.amountXs,
            ),
          ],
        ),
      ),
    );
  }
}

/// 「预算 vs 实际」对比条：一行一个分类，共用同一根轨道。
///
/// ## 为什么不用两根柱
/// 预算和已用是**同一笔钱的两个刻度**，并排两根柱要靠图例才分得清；
/// 画在一根轨道上，「填到哪、还剩多少、超出去多少」是直接看出来的 ——
/// 不需要图例，也不需要读数字。
///
/// ## 颜色的三条硬约束（来自项目红线）
/// - 只用黑白灰 + 红；
/// - **红只表示超支**，不作装饰 —— 所以正常进度一律用 [C.ink]，
///   只有 `spent > budget` 的那一段才染色；
/// - 未填满的部分是轨道底色 [C.bg2]，不是另一种彩色。
class BudgetCompareBars extends StatelessWidget {
  const BudgetCompareBars({
    super.key,
    required this.rows,
    this.maxRows = 6,
    this.rowHeight = 30,
  });

  /// 只传**设了预算**的分类（`budgetCents > 0`）。
  /// 没设预算的分类没有"对比"可言，塞进来只会让轨道恒满。
  final List<({String name, int spentCents, int budgetCents})> rows;

  final int maxRows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final usable = rows.where((r) => r.budgetCents > 0).toList()
      ..sort((a, b) => (b.spentCents / b.budgetCents)
          .compareTo(a.spentCents / a.budgetCents));
    final shown = usable.take(maxRows).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    // 全局归一化：所有轨道用同一个分母，横向才可比。
    // 分母取「预算」与「已用」的最大值 —— 超支的分类不会画出轨道外。
    var scale = 1;
    for (final r in shown) {
      if (r.budgetCents > scale) scale = r.budgetCents;
      if (r.spentCents > scale) scale = r.spentCents;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in shown)
          SizedBox(
            height: rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.lg),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      r.name,
                      style: T.caption.copyWith(color: C.ink2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  Expanded(child: _track(r, scale)),
                  const SizedBox(width: S.sm),
                  _amountText(r),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _track(
    ({String name, int spentCents, int budgetCents}) r,
    int scale,
  ) {
    final over = r.spentCents > r.budgetCents;
    return Semantics(
      label: '${r.name} 已用 ${Fmt.money(r.spentCents)}，'
          '预算 ${Fmt.money(r.budgetCents)}${over ? '，已超支' : ''}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 8,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final budgetW = w * (r.budgetCents / scale).clamp(0.0, 1.0);
              final spentW = w * (r.spentCents / scale).clamp(0.0, 1.0);
              return Stack(
                children: [
                  // 轨道底 = **预算的长度**（不是整行宽）。
                  // 画满整行的话，「预算到哪儿」这条信息就丢了：
                  // 用户看到一条通到底的浅灰，不知道还剩多少额度没用。
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    // 预算再小也留 2px：否则「设过预算」看起来等于「没设」
                    width: math.max(budgetW, 2),
                    child: ColoredBox(color: C.bg2),
                  ),
                  Positioned.fill(
                    left: 0,
                    right: w - math.min(spentW, budgetW),
                    child: ColoredBox(color: C.ink),
                  ),
                  if (over)
                    Positioned(
                      left: budgetW,
                      top: 0,
                      bottom: 0,
                      width: spentW - budgetW,
                      child: ColoredBox(color: C.over),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _amountText(({String name, int spentCents, int budgetCents}) r) {
    final over = r.spentCents > r.budgetCents;
    return Text(
      '${Fmt.money(r.spentCents)} / ${Fmt.money(r.budgetCents)}',
      style: T.amountXs.copyWith(color: over ? C.over : C.ink2),
    );
  }
}

/// 多月趋势折线：**没有数据的月份断开**，不画成 0。
///
/// ## 为什么必须断开
/// 把"这个月没记账"画成 0，等于告诉用户"这个月一分没花" ——
/// 这两个是完全不同的事实，而用户看趋势图时不会去核对每个月。
/// 少记一个月就掉到谷底，是对数据的编造。
///
/// 标签用 Widget 画（不用 canvas 的 TextPainter）：测试环境的默认字体是
/// Ahem（全是方块），canvas 画字在截图里不可读，Widget 走正常渲染栈。
class MonthTrendLine extends StatelessWidget {
  const MonthTrendLine({
    super.key,
    required this.points,
    this.height = 84,
    this.color,
  });

  /// [value] 为 null = 这个月**没有数据**（断线，不是 0）。
  final List<({String label, int? value})> points;

  final double height;
  final Color? color;

  bool get _hasAny => points.any((p) => p.value != null);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty || !_hasAny) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('这段时间没有记录', style: T.caption.copyWith(color: C.ink4)),
        ),
      );
    }

    final line = color ?? C.ink;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(points: points, color: line),
          ),
        ),
        const SizedBox(height: S.sm),
        Row(
          children: [
            for (final p in points)
              Expanded(
                child: Text(
                  p.label,
                  textAlign: TextAlign.center,
                  style: T.overline.copyWith(letterSpacing: 0, color: C.ink3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.color});

  final List<({String label, int? value})> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 全域兜底：一个点、全空、全 0，都不能算出 NaN 坐标
    var maxV = 0;
    for (final p in points) {
      final v = p.value;
      if (v != null && v > maxV) maxV = v;
    }
    if (maxV <= 0) return;

    const padTop = 10.0;
    const padBottom = 2.0;
    final usableH = (size.height - padTop - padBottom).clamp(1.0, size.height);

    double xOf(int i) => points.length == 1
        ? size.width / 2
        : i * size.width / (points.length - 1);
    double yOf(int v) => padTop + usableH * (1 - v / maxV);

    final axis = Paint()
      ..color = C.line
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - padBottom),
      Offset(size.width, size.height - padBottom),
      axis,
    );

    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final dot = Paint()..color = color;

    Offset? prev;
    for (var i = 0; i < points.length; i++) {
      final v = points[i].value;
      if (v == null) {
        prev = null; // 空月：断线
        continue;
      }
      final cur = Offset(xOf(i), yOf(v));
      if (prev != null) canvas.drawLine(prev, cur, stroke);
      canvas.drawCircle(cur, 3, dot);
      prev = cur;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) {
    if (old.color != color || old.points.length != points.length) return true;
    for (var i = 0; i < points.length; i++) {
      if (old.points[i].value != points[i].value ||
          old.points[i].label != points[i].label) {
        return true;
      }
    }
    return false;
  }
}
