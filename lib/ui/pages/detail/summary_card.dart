import 'package:flutter/material.dart';

import '../../../data/models/models.dart';
import '../../../data/services/summary_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/icon_map.dart';
import '../../widgets/progress_bar.dart';

/// 概览卡：本期三格（收入 / 结余 / 笔数）+ 预算条 + 节奏行 + 三手势翻期。
///
/// ★ 两个口径绝不能混（§3.1 / §3.7）：
/// - 三格的数字来自**聚合**（`RangeTotals`），不是列表项相加 —— 列表有 50 条上限；
/// - 筛选态换整套口径：标题变「筛选结果 / 全部时间」，三格变
///   「筛选支出 / 筛选收入 / 收支差」，且**预算条整块不渲染**
///   （筛选是跨全史的，预算只对本期有意义，混在一起会给出错的钱数）。
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.periodLabel,
    required this.totals,
    required this.filtering,
    this.keyword,
    this.budgetTotalCents,
    this.budgetUsedCents = 0,
    this.canSpendPerDayCents = 0,
    this.remainDays = 0,
    this.overCents = 0,
    this.onPrev,
    this.onNext,
    this.onToday,
    this.onPick,
    this.onFilter,
    this.onSearch,
    this.ledgerName = '',
  });

  /// 期文案（`10.01 至 10.31`）。筛选态显示「全部时间」。
  final String periodLabel;

  final RangeTotals totals;
  final bool filtering;

  /// 筛选态时显示在标题里的关键词（可能为 null）。
  final String? keyword;

  final int? budgetTotalCents;
  final int budgetUsedCents;
  final int canSpendPerDayCents;
  final int remainDays;
  final int overCents;

  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onToday;
  final VoidCallback? onPick;
  final VoidCallback? onFilter;
  final VoidCallback? onSearch;
  final String ledgerName;

  bool get hasBudget => budgetTotalCents != null;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final BudgetStats stats = SummaryService.budgetStats(
      totalCents: budgetTotalCents,
      usedCents: budgetUsedCents,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.md),
      padding: const EdgeInsets.fromLTRB(S.card, S.md, S.card, S.card),
      decoration: BoxDecoration(
        color: pal.heroBg,
        borderRadius: R.rCard,
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  filtering ? '筛选结果' : (ledgerName.isEmpty ? '本期' : ledgerName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ts.caption.copyWith(color: pal.ink3),
                ),
              ),
              if (onFilter != null)
                _IconAction(
                  icon: Icons.tune,
                  tooltip: '筛选',
                  onTap: onFilter!,
                  active: filtering,
                ),
              if (onSearch != null)
                _IconAction(
                  icon: Icons.search,
                  tooltip: '搜索',
                  onTap: onSearch!,
                ),
            ],
          ),
          const SizedBox(height: S.xs),
          // 期文案 —— 三手势都挂在这一行上（SwipeFlip）
          Text(
            filtering ? '全部时间' : periodLabel,
            key: const ValueKey<String>('summary-period-label'),
            style: Ts.caption.copyWith(color: pal.ink2),
          ),
          const SizedBox(height: S.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _Cell(
                  label: filtering ? '筛选支出' : '支出',
                  cents: filtering ? totals.expenseCents : totals.expenseCents,
                  hero: !filtering,
                ),
              ),
              Expanded(
                child: _Cell(
                  label: filtering ? '筛选收入' : '结余',
                  cents: filtering ? totals.incomeCents : totals.netCents,
                  hero: false,
                ),
              ),
              Expanded(
                child: _Cell(
                  label: filtering ? '收支差' : '笔数',
                  cents: totals.netCents,
                  count: totals.count,
                  hero: false,
                ),
              ),
            ],
          ),
          // 预算条：**筛选态整块不渲染**
          if (!filtering && hasBudget) ...<Widget>[
            const SizedBox(height: S.md),
            ProgressBar(
              ratio: stats.usedRatio,
              overCents: stats.overCents,
              height: 6,
            ),
            const SizedBox(height: S.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    overCents > 0
                        ? '已超 ${_yuan(overCents)}'
                        : '还剩 ${_yuan(stats.leftCents)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ts.caption.copyWith(
                      color: overCents > 0 ? pal.over : pal.ink2,
                    ),
                  ),
                ),
                Text(
                  remainDays > 0
                      ? '每天可花 ${_yuan(canSpendPerDayCents)}'
                      : '本期已结束',
                  style: Ts.caption.copyWith(color: pal.ink3),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _yuan(int cents) {
    final int v = cents.abs();
    final String s = '${
      (v ~/ 100).toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      )
    }.${(v % 100).toString().padLeft(2, '0')}';
    return '${cents < 0 ? '-' : ''}¥$s';
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.cents,
    this.hero = false,
    this.count,
  });

  final String label;
  final int cents;
  final bool hero;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Ts.badge.copyWith(color: pal.ink3)),
        const SizedBox(height: 2),
        // 六位数金额必须单行：FittedBox 缩放而不是换行/溢出
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: count != null
              ? Text(
                  '${count!}',
                  style: (hero ? Ts.hero : Ts.heroSm).copyWith(color: pal.ink),
                )
              : AmountText(
                  cents: cents,
                  sign: false,
                  style: hero ? Ts.hero : Ts.heroSm,
                  color: pal.ink,
                ),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return IconButton(
      key: ValueKey<String>('summary-action-$tooltip'),
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18, color: active ? pal.navActive : pal.ink3),
    );
  }
}

/// 明细行里「借出 · 张三」这类标题要用到的图标（放在这里避免循环引用）。
IconData debtIcon() => IconMap.of('gift');
