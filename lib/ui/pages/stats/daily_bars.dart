import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../data/repo/stats_repo.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// 每日柱的一格：**区间内每一天都有一格**（没数据的那天金额 0、不画柱）。
class DailyBarCell {
  const DailyBarCell({
    required this.date,
    required this.cents,
    required this.ratio,
  });

  final LocalDate date;
  final int cents;

  /// 相对区间内最大值的比例（0–1）。金额 0 时恒为 0。
  final double ratio;

  bool get isZero => cents <= 0;
}

/// 每日合计 → 柱子。`rows` 必须是**已经补齐每一天**的（`fillDailyRange`）。
///
/// 抽成纯函数是为了让「每天占一格」「零值不画柱」这两条不靠肉眼看图。
List<DailyBarCell> buildDailyCells(List<DailyTotal> rows) {
  int max = 0;
  for (final DailyTotal r in rows) {
    if (r.expenseCents > max) max = r.expenseCents;
  }
  final int denom = max == 0 ? 1 : max;
  return <DailyBarCell>[
    for (final DailyTotal r in rows)
      DailyBarCell(
        date: LocalDate.tryParse(r.date) ??
            LocalDate.fromDateTime(DateTime(1970)),
        cents: r.expenseCents,
        ratio: r.expenseCents <= 0 ? 0 : r.expenseCents / denom,
      ),
  ];
}

/// 每日支出柱。点某一天 → 下钻到明细的那一天。
///
/// 用 `CustomPainter` 而不是一堆 `Container`：一屏 31 个 `Container` 会让
/// 图表页每次重建都重排 31 个渲染对象；顺带让「零值全背景色」可以像素断言。
class DailyBars extends StatelessWidget {
  const DailyBars({
    super.key,
    required this.cells,
    required this.onPick,
    this.height = 88,
  });

  final List<DailyBarCell> cells;
  final ValueChanged<LocalDate> onPick;
  final double height;

  /// 命中：按 x 落在哪一格算（y 不参与，矮柱也点得中）。
  static int indexAt(double dx, double width, int count) {
    if (count <= 0 || width <= 0) return -1;
    final double cell = width / count;
    final int i = (dx / cell).floor();
    if (i < 0) return 0;
    if (i >= count) return count - 1;
    return i;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return SizedBox(
      key: const ValueKey<String>('daily-bars'),
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (TapUpDetails d) {
              final int i = indexAt(d.localPosition.dx, c.maxWidth, cells.length);
              if (i < 0) return;
              onPick(cells[i].date);
            },
            child: CustomPaint(
              painter: DailyBarsPainter(
                cells: cells,
                barColor: pal.accent,
                bgColor: pal.bg,
                baselineColor: pal.line,
              ),
              size: Size(c.maxWidth, height),
            ),
          );
        },
      ),
    );
  }
}

/// 每日柱的画笔。**不读 Store、paint 里不分配 List**。
class DailyBarsPainter extends CustomPainter {
  DailyBarsPainter({
    required this.cells,
    required this.barColor,
    required this.bgColor,
    required this.baselineColor,
  });

  final List<DailyBarCell> cells;
  final Color barColor;
  final Color bgColor;
  final Color baselineColor;

  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || cells.isEmpty) return;

    // 先铺底色：这样「零值那一天」的像素就是纯背景色，可以直接断言
    _paint.color = bgColor;
    canvas.drawRect(Offset.zero & size, _paint);

    final double cellWidth = size.width / cells.length;
    final double barWidth = cellWidth > 6 ? cellWidth - 2 : cellWidth;
    final double usable = size.height - 2;

    _paint.color = baselineColor;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 1, size.width, 1),
      _paint,
    );

    _paint.color = barColor;
    for (int i = 0; i < cells.length; i++) {
      final DailyBarCell c = cells[i];
      if (c.isZero) continue; // 零值不画柱（连 1px 都不给，否则看着像有账）
      final double h = c.ratio.clamp(0.0, 1.0) * usable;
      final double left = i * cellWidth + (cellWidth - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - 1 - h, barWidth, h),
          const Radius.circular(2),
        ),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(DailyBarsPainter old) =>
      old.barColor != barColor ||
      old.bgColor != bgColor ||
      old.baselineColor != baselineColor ||
      old.cells.length != cells.length ||
      (old.cells.isNotEmpty &&
          cells.isNotEmpty &&
          (old.cells.first.cents != cells.first.cents ||
              old.cells.last.cents != cells.last.cents));
}

/// 每日柱下方的横轴字（首 / 中 / 末三天，其余留白）。
class DailyAxisLabels extends StatelessWidget {
  const DailyAxisLabels({super.key, required this.cells});

  final List<DailyBarCell> cells;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    if (cells.isEmpty) return const SizedBox.shrink();
    final List<String> marks = <String>[
      '${cells.first.date.month}/${cells.first.date.day}',
      if (cells.length > 2) '${cells[cells.length ~/ 2].date.day}',
      if (cells.length > 1)
        '${cells.last.date.month}/${cells.last.date.day}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (final String m in marks)
            Text(m, style: Ts.micro.copyWith(color: pal.ink4)),
        ],
      ),
    );
  }
}
