import 'package:flutter/material.dart';

import '../../../data/repo/stats_repo.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// 近 6 段双柱：每段两根（支出实心 `accent`、收入 `ink4`），**共用同一条基线**。
///
/// 判据 3.4：零值不画柱、支出实心、共用基线、逐段数据由**1 条合并查询**取得
/// （查询那一条在 `StatsRepo.trendTotals` 里，这里只负责画）。
class TrendBars extends StatelessWidget {
  const TrendBars({
    super.key,
    required this.segments,
    this.height = 96,
  });

  final List<TrendSegment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    if (segments.isEmpty) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        SizedBox(
          key: const ValueKey<String>('trend-bars'),
          height: height,
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints c) => CustomPaint(
              painter: TrendBarsPainter(
                segments: segments,
                expenseColor: pal.accent,
                incomeColor: pal.ink4,
                bgColor: pal.bg,
                baselineColor: pal.line,
              ),
              size: Size(c.maxWidth, height),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            for (final TrendSegment s in segments)
              Expanded(
                child: Text(
                  s.label,
                  textAlign: TextAlign.center,
                  style: Ts.micro.copyWith(color: pal.ink4),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 双柱画笔。**不读 Store、paint 里不分配 List**。
class TrendBarsPainter extends CustomPainter {
  TrendBarsPainter({
    required this.segments,
    required this.expenseColor,
    required this.incomeColor,
    required this.bgColor,
    required this.baselineColor,
  });

  final List<TrendSegment> segments;
  final Color expenseColor;
  final Color incomeColor;
  final Color bgColor;
  final Color baselineColor;

  final Paint _paint = Paint();

  /// 段内最大值（两根柱共用一个刻度，否则收入柱会把支出柱压成一条线）。
  int get maxCents {
    int max = 0;
    for (final TrendSegment s in segments) {
      if (s.expenseCents > max) max = s.expenseCents;
      if (s.incomeCents > max) max = s.incomeCents;
    }
    return max;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || segments.isEmpty) return;

    _paint.color = bgColor;
    canvas.drawRect(Offset.zero & size, _paint);

    final double groupWidth = size.width / segments.length;
    final double barWidth = groupWidth > 8 ? (groupWidth - 6) / 2 : groupWidth / 2;
    final double usable = size.height - 2;
    final int max = maxCents;
    final int denom = max == 0 ? 1 : max;

    for (int i = 0; i < segments.length; i++) {
      final TrendSegment s = segments[i];
      final double left = i * groupWidth + (groupWidth - barWidth * 2) / 2;

      // 支出（左，实心 accent）
      if (s.expenseCents > 0) {
        final double h = s.expenseCents / denom * usable;
        _paint.color = expenseColor;
        canvas.drawRect(
          Rect.fromLTWH(left, size.height - 1 - h, barWidth, h),
          _paint,
        );
      }
      // 收入（右，ink4）
      if (s.incomeCents > 0) {
        final double h = s.incomeCents / denom * usable;
        _paint.color = incomeColor;
        canvas.drawRect(
          Rect.fromLTWH(left + barWidth + 1, size.height - 1 - h, barWidth, h),
          _paint,
        );
      }
    }

    // 共用基线（最后画，压在两根柱的底边上，谁高谁低都对齐在 y = height - 1）
    _paint.color = baselineColor;
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), _paint);
  }

  @override
  bool shouldRepaint(TrendBarsPainter old) =>
      old.expenseColor != expenseColor ||
      old.incomeColor != incomeColor ||
      old.bgColor != bgColor ||
      old.baselineColor != baselineColor ||
      old.segments.length != segments.length ||
      (old.segments.isNotEmpty &&
          segments.isNotEmpty &&
          (old.segments.last.expenseCents != segments.last.expenseCents ||
              old.segments.last.incomeCents != segments.last.incomeCents));
}

/// 图例：支出 / 收入两枚色块。
class TrendLegend extends StatelessWidget {
  const TrendLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Ts.micro.copyWith(color: pal.ink3)),
      ],
    );
    return Row(
      children: <Widget>[
        item(pal.accent, '支出'),
        const SizedBox(width: S.md),
        item(pal.ink4, '收入'),
      ],
    );
  }
}
