import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/icons.dart';
import '../design/tokens.dart';

/// 分类九宫格（5 列）。记一笔面板与筛选面板共用同一个实现。
///
/// 原先它是 `record_sheet.dart` 里的私有 `_CategoryGrid`，筛选面板需要
/// 一模一样的视觉，就提到了这里 —— 两处各抄一份迟早会漂移，而设计 token
/// 应该是唯一来源。视觉与交互一个字都没改，改动只是「类换了位置」。
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.cats,
    required this.selected,
    required this.onSelect,
  });

  final List<Category> cats;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (cats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: S.xl),
        child: Text('还没有分类，请先到「我的 → 分类管理」添加', style: T.caption),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: S.sm,
          crossAxisSpacing: S.sm,
          childAspectRatio: 0.86,
        ),
        itemCount: cats.length,
        itemBuilder: (context, i) {
          final c = cats[i];
          final on = c.id == selected;
          return GestureDetector(
            // 同理：整格可点，而不是只有图标方块和文字笔画
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(c.id),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: on ? C.ink : C.bg2,
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Center(
                    child: LineIcon(
                      c.icon,
                      size: 21,
                      color: on ? C.bg : C.ink2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  c.name,
                  style: T.overline.copyWith(
                    color: on ? C.ink : C.ink2,
                    fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
