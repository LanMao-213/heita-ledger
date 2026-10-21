import 'package:flutter/material.dart';

import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../icon_map.dart';

/// 双轮盘的**数据与状态**（纯逻辑，可脱 UI 单测）。
///
/// 三条硬规则（M12-F04）：
/// 1. 左轮**必选**（一级分类不能为空）；
/// 2. 右轮首项**永远是「不细分」**（对应 `category_id` 指向一级）；
/// 3. 左轮一变，右轮**重建**并回到「不细分」；传入已选子分类时右轮停在它上面。
class CategoryWheelData {
  CategoryWheelData(
    this.tree,
    this.type, {
    int? topId,
    int? subId,
  }) {
    _tops = tree.topsOf(type, includeArchived: true);
    _topIndex = _indexOfTop(topId);
    _subIndex = _indexOfSub(subId);
  }

  final CategoryTree tree;
  final TxnType type;

  late final List<Category> _tops;
  late int _topIndex;
  late int _subIndex;

  List<Category> get tops => _tops;

  int get topIndex => _topIndex;

  /// 右轮选项：`[null(不细分), ...子分类]`。第 0 项永远是 `null`。
  List<Category?> get subItems {
    final Category? top = currentTop;
    if (top?.id == null) return const <Category?>[null];
    return <Category?>[null, ...tree.childrenOf(top!.id)];
  }

  int get subIndex => _subIndex;

  Category? get currentTop =>
      _topIndex >= 0 && _topIndex < _tops.length ? _tops[_topIndex] : null;

  int? get selectedTopId => currentTop?.id;

  int? get selectedSubId {
    final List<Category?> items = subItems;
    if (_subIndex <= 0 || _subIndex >= items.length) return null;
    return items[_subIndex]?.id;
  }

  /// 左轮选择：右轮**重置到「不细分」**（换了大类，旧的子分类不再成立）。
  CategoryWheelData selectTop(int index) {
    _topIndex = index.clamp(0, _tops.isEmpty ? 0 : _tops.length - 1);
    _subIndex = 0;
    return this;
  }

  CategoryWheelData selectSub(int index) {
    final int max = subItems.length - 1;
    _subIndex = max <= 0 ? 0 : index.clamp(0, max);
    return this;
  }

  int _indexOfTop(int? id) {
    if (_tops.isEmpty) return 0;
    if (id == null) return 0;
    final int i = _tops.indexWhere((Category c) => c.id == id);
    return i < 0 ? 0 : i;
  }

  int _indexOfSub(int? id) {
    if (id == null) return 0;
    final List<Category?> items = subItems;
    final int i = items.indexWhere((Category? c) => c?.id == id);
    return i < 0 ? 0 : i;
  }
}

/// 双轮盘控件：左「大类」右「细分」。
///
/// 视觉：两列等宽，中间一条 `line` 分隔；选中行由 `inkWash` 遮罩标出
/// （`ListWheelScrollView` 的 `selectionOverlay`）。行高 36，可视 5 行。
class CategoryWheels extends StatelessWidget {
  const CategoryWheels({
    super.key,
    required this.tree,
    required this.type,
    required this.initialTopId,
    required this.initialSubId,
    required this.onChanged,
    this.height = 180,
  });

  final CategoryTree tree;
  final TxnType type;
  final int? initialTopId;
  final int? initialSubId;
  final void Function(int? topId, int? subId) onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final CategoryWheelData data = CategoryWheelData(
      tree,
      type,
      topId: initialTopId,
      subId: initialSubId,
    );

    return SizedBox(
      height: height,
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    IgnorePointer(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: pal.inkWash,
                          borderRadius: R.rSm,
                        ),
                      ),
                    ),
                    ListWheelScrollView.useDelegate(
                  key: const ValueKey<String>('wheel-top'),
                        itemExtent: 36,
                        diameterRatio: 1.6,
                        perspective: 0.003,
                        physics: const FixedExtentScrollPhysics(),
                        controller: FixedExtentScrollController(
                          initialItem: data.topIndex,
                        ),
                        onSelectedItemChanged: (int i) {
                          setState(() {
                            data.selectTop(i);
                            onChanged(data.selectedTopId, data.selectedSubId);
                          });
                        },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: data.tops.length,
                        builder: (BuildContext context, int i) => _WheelRow(
                          text: data.tops[i].name,
                          icon: data.tops[i].icon,
                          selected: i == data.topIndex,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 120, color: pal.line),
              Expanded(
                flex: 2,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    IgnorePointer(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: pal.inkWash,
                          borderRadius: R.rSm,
                        ),
                      ),
                    ),
                    ListWheelScrollView.useDelegate(
                  key: const ValueKey<String>('wheel-sub'),
                        itemExtent: 36,
                        diameterRatio: 1.6,
                        perspective: 0.003,
                        physics: const FixedExtentScrollPhysics(),
                        controller: FixedExtentScrollController(
                          initialItem: data.subIndex,
                        ),
                        onSelectedItemChanged: (int i) {
                          setState(() {
                            data.selectSub(i);
                            onChanged(data.selectedTopId, data.selectedSubId);
                          });
                        },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: data.subItems.length,
                        builder: (BuildContext context, int i) {
                          final Category? sub = data.subItems[i];
                          return _WheelRow(
                            text: sub?.name ?? '不细分',
                            icon: sub?.icon,
                            selected: i == data.subIndex,
                            muted: sub == null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WheelRow extends StatelessWidget {
  const _WheelRow({
    required this.text,
    required this.selected,
    this.icon,
    this.muted = false,
  });

  final String text;
  final bool selected;
  final String? icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(IconMap.of(icon), size: 15, color: pal.ink3),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Ts.body2.copyWith(
              color: selected ? pal.ink : (muted ? pal.ink4 : pal.ink2),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
