import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 一枚可选 chip（类型 / 时间段 / 分类一级）。
class ChipTabItem<T> {
  const ChipTabItem(this.value, this.label);

  final T value;
  final String label;
}

/// 一排单选 chip（模式、类型、时间段都用它）。
///
/// 选中态用 `accent` 底 + `onAccent` 字；未选中用 `surfaceAlt` 底 + `ink2` 字。
/// **不做多选**：多选的地方（分类筛选）用两级 chips 自己管。
class ChipTabs<T> extends StatelessWidget {
  const ChipTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: S.page),
  });

  final List<ChipTabItem<T>> items;
  final T? selected;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: <Widget>[
          for (final ChipTabItem<T> item in items) ...<Widget>[
            _Chip(
              label: item.label,
              selected: item.value == selected,
              onTap: () => onChanged(item.value),
              pal: pal,
            ),
            const SizedBox(width: S.sm),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.pal,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppPalette pal;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey<String>('chip-$label'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32, minWidth: S.touch),
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? pal.accent : pal.surfaceAlt,
          borderRadius: R.rPill,
          border: Border.all(color: selected ? pal.accent : pal.line),
        ),
        child: Center(
          child: Text(
            label,
            style: Ts.caption.copyWith(
              color: selected ? pal.onAccent : pal.ink2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
