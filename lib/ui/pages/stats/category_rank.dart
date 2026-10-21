import 'package:flutter/material.dart';

import '../../../data/repo/stats_repo.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/icon_map.dart';

/// 排行的一行（比例已经算好，画的时候不再判断）。
class RankRow {
  const RankRow({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.cents,
    required this.ratio,
    required this.color,
  });

  final int categoryId;
  final String name;
  final String icon;
  final int cents;

  /// 相对第一名的比例（0–1，第一名恒为 1）。
  final double ratio;
  final Color color;
}

/// 分类合计 → 排行行。
///
/// 与饼图共用同一份「合计 ≤ 0 不参与」的口径；比例的分母是**第一名**而不是
/// 合计 —— 排行条要回答的是「它比第一名差多少」，不是「占总额多少」。
List<RankRow> buildRankRows({
  required List<CategoryStat> stats,
  required List<Color> chart,
}) {
  final List<CategoryStat> kept = <CategoryStat>[
    for (final CategoryStat s in stats)
      if (s.cents > 0) s,
  ];
  if (kept.isEmpty) return <RankRow>[];

  int max = 0;
  for (final CategoryStat s in kept) {
    if (s.cents > max) max = s.cents;
  }
  final int denom = max == 0 ? 1 : max;

  return <RankRow>[
    for (int i = 0; i < kept.length; i++)
      RankRow(
        categoryId: kept[i].categoryId,
        name: kept[i].name,
        icon: kept[i].icon,
        cents: kept[i].cents,
        ratio: kept[i].cents / denom,
        color: chart[i % chart.length],
      ),
  ];
}

/// 分类排行：色点 + 名字 + 金额 + 相对比例条。点一行 → 下钻到明细。
class CategoryRankList extends StatelessWidget {
  const CategoryRankList({
    super.key,
    required this.rows,
    required this.onTap,
    this.maxRows = 6,
  });

  final List<RankRow> rows;

  /// 下钻回调。**调用方必须把当前统计区间一起带过去** ——
  /// 否则「图表 3,874 → 明细另一个数」，用户会以为算错了。
  final ValueChanged<RankRow> onTap;

  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final List<RankRow> shown = rows.take(maxRows).toList();
    return Column(
      children: <Widget>[
        for (final RankRow r in shown)
          InkWell(
            key: ValueKey<String>('rank-${r.categoryId}'),
            onTap: () => onTap(r),
            borderRadius: R.rSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: r.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  Icon(IconMap.of(r.icon), size: 14, color: pal.ink3),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    child: Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.body2.copyWith(color: pal.ink),
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // 相对比例条：第一名满格，其余按比例
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: r.ratio.isNaN
                              ? 0
                              : r.ratio.clamp(0.02, 1.0),
                          child: Container(
                            key: ValueKey<String>('rank-bar-${r.categoryId}'),
                            height: 6,
                            decoration: BoxDecoration(
                              color: r.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  AmountText(cents: r.cents, tier: AmountTier.small),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
