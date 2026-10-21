import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';

/// 细进度条（预算条 / 目标进度）。
///
/// `ratio` **不截断**（超支时 > 1），条内自己 clamp 到 1；超支时整条变 `over` 色。
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.ratio,
    this.height = 6,
    this.color,
    this.overCents = 0,
  });

  /// 0–1 之外的值会被 clamp 显示，但 [isOver] 仍能看出来。
  final double ratio;

  final double height;

  /// 指定颜色（默认 `accent`；超支自动用 `over`）。
  final Color? color;

  /// 超支金额 > 0 → 用警示色。
  final int overCents;

  bool get isOver => overCents > 0 || ratio > 1;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final double value = ratio.isNaN ? 0 : ratio.clamp(0.0, 1.0);
    final Color fill = color ?? (isOver ? pal.over : pal.accent);

    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: pal.surfaceAlt)),
            FractionallySizedBox(
              widthFactor: value,
              child: ColoredBox(color: fill),
            ),
          ],
        ),
      ),
    );
  }
}
