import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/repo/stats_repo.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// 饼图的一个扇区（几何 + 颜色都算好了，画的时候不再做判断）。
class PieSlice {
  const PieSlice({
    required this.categoryId,
    required this.name,
    required this.cents,
    required this.percent,
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
  });

  final int categoryId;
  final String name;

  /// **绝对值**（支出里的负数退款不该变成负扇区）。
  final int cents;

  /// 0–1（合计为 0 时按分母 1 算，得到 0 而不是 NaN）。
  final double percent;

  /// 弧度，0 在 12 点方向（-π/2），顺时针。
  final double startAngle;
  final double sweepAngle;

  final Color color;

  /// 扇区中线角度（像素断言取色用：半径中点 + 中线角度 = 这个扇区）。
  double get midAngle => startAngle + sweepAngle / 2;
}

/// 饼图起始角：12 点方向。**唯一的定义处**，画和测都读它。
const double kPieStartAngle = -math.pi / 2;

/// 分类合计 → 扇区。
///
/// 四条口径（判据 3.1）：
/// 1. 合计 ≤ 0 的分类**不参与**（退款退成负数的不该占一格）；
/// 2. 分母 = Σ参与者的合计；`total == 0` 时**分母按 1**（不产生 NaN）；
/// 3. 扇区角之和 == 2π（有数据时；误差只来自 double 累加）；
/// 4. 颜色按顺序取 [AppPalette.chart]，超出就回卷 —— 两套配色的色阶都是从深到浅。
List<PieSlice> buildPieSlices({
  required List<CategoryStat> stats,
  required List<Color> chart,
}) {
  final List<CategoryStat> kept = <CategoryStat>[
    for (final CategoryStat s in stats)
      if (s.cents > 0) s,
  ];
  if (kept.isEmpty) return <PieSlice>[];

  int total = 0;
  for (final CategoryStat s in kept) {
    total += s.cents;
  }
  final int denom = total == 0 ? 1 : total;

  final List<PieSlice> out = <PieSlice>[];
  double cursor = kPieStartAngle;
  for (int i = 0; i < kept.length; i++) {
    final CategoryStat s = kept[i];
    final double sweep = 2 * math.pi * s.cents / denom;
    out.add(
      PieSlice(
        categoryId: s.categoryId,
        name: s.name,
        cents: s.cents,
        percent: s.cents / denom,
        startAngle: cursor,
        sweepAngle: sweep,
        color: chart[i % chart.length],
      ),
    );
    cursor += sweep;
  }
  return out;
}

/// 饼图（环形）。尺寸由调用方定，**自己不读任何 Store**。
class PieChart extends StatelessWidget {
  const PieChart({
    super.key,
    required this.slices,
    this.size = 148,
    this.thickness = 22,
    this.centerTop,
    this.centerBottom,
  });

  final List<PieSlice> slices;
  final double size;
  final double thickness;

  /// 圆心上的两行字（一般是「支出」+ 合计）。
  final String? centerTop;
  final String? centerBottom;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: PiePainter(
          slices: slices,
          thickness: thickness,
          trackColor: pal.surfaceAlt,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (centerTop != null)
                Text(
                  centerTop!,
                  style: Ts.micro.copyWith(color: pal.ink3),
                ),
              if (centerBottom != null)
                Text(
                  centerBottom!,
                  style: Ts.section.copyWith(color: pal.ink),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 环形饼的画笔。**纯几何**：不读 Store、不在 paint 里分配新的 List。
class PiePainter extends CustomPainter {
  PiePainter({
    required this.slices,
    required this.thickness,
    required this.trackColor,
  });

  final List<PieSlice> slices;
  final double thickness;
  final Color trackColor;

  final Paint _paint = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // 尺寸为 0 时直接返回：否则 ray = 负数/0，后面除出 NaN，整块画布变空白
    if (size.width <= 0 || size.height <= 0) return;

    final double r = (math.min(size.width, size.height) - thickness) / 2;
    if (r <= 0) return;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Rect rect = Rect.fromCircle(center: center, radius: r);

    _paint
      ..strokeWidth = thickness
      ..color = trackColor;
    canvas.drawArc(rect, 0, 2 * math.pi, false, _paint);

    for (final PieSlice s in slices) {
      if (s.sweepAngle <= 0) continue;
      _paint.color = s.color;
      canvas.drawArc(rect, s.startAngle, s.sweepAngle, false, _paint);
    }
  }

  @override
  bool shouldRepaint(PiePainter old) =>
      old.thickness != thickness ||
      old.trackColor != trackColor ||
      old.slices.length != slices.length ||
      (old.slices.isNotEmpty &&
          slices.isNotEmpty &&
          (old.slices.first.cents != slices.first.cents ||
              old.slices.last.cents != slices.last.cents));
}

/// 统计骨架：**没算过的时候画它，绝不画「本期还没有数据」**（I20）。
///
/// 原版栽在这里：首帧同步算统计，算之前先渲染空态，于是每次进图表页都闪一下
/// 「本期还没有数据」，用户以为数据丢了。
class PieSkeleton extends StatelessWidget {
  const PieSkeleton({super.key, this.size = 148, this.thickness = 22});

  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return SizedBox(
      key: const ValueKey<String>('pie-skeleton'),
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SkeletonPainter(thickness: thickness, color: pal.surfaceAlt),
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  const _SkeletonPainter({required this.thickness, required this.color});

  final double thickness;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final double r = (math.min(size.width, size.height) - thickness) / 2;
    if (r <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: r,
      ),
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      old.thickness != thickness || old.color != color;
}

/// 图例：色点 + 名字 + 金额 + 占比。最多两列（`Wrap`）。
class PieLegend extends StatelessWidget {
  const PieLegend({super.key, required this.slices, this.maxRows = 6});

  final List<PieSlice> slices;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final List<PieSlice> shown = slices.take(maxRows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final PieSlice s in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ts.caption.copyWith(color: pal.ink2),
                  ),
                ),
                Text(
                  '${(s.percent * 100).toStringAsFixed(1)}%',
                  key: ValueKey<String>('legend-pct-${s.categoryId}'),
                  style: Ts.micro.copyWith(color: pal.ink3),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
