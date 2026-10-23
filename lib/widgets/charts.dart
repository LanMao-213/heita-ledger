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
