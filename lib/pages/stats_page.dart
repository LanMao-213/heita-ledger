import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

/// 图表页：环形占比 + 分类排行 + 每日趋势。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  TxnType _type = TxnType.expense;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    // 金额允许为负（净额记账），某分类合计可能 ≤0 —— 饼图和排行榜画不出负扇区，
    // 这类分类直接不参与，明细里仍然照常显示
    final stats = (_type.isExpense ? s.expenseStats : s.incomeStats)
        .where((e) => e.totalCents > 0)
        .toList();
    final total = _type.isExpense ? s.monthExpenseCents : s.monthIncomeCents;
    final maxV = stats.isEmpty
        ? 1
        : stats.map((e) => e.totalCents).reduce((a, b) => a > b ? a : b);

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: S.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: S.md),
              child: MonthBar(
                month: s.month,
                onPrev: () => s.shiftMonth(-1),
                onNext: () => s.shiftMonth(1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.sm),
              child: SegTabs(
                value: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
            ),

            if (stats.isEmpty)
              const EmptyHint(
                icon: 'pie',
                text: '本月还没有数据',
                hint: '记几笔之后这里会出现占比图',
              )
            else ...[
              SectionCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Donut(
                          size: 128,
                          thickness: 15,
                          slices: [
                            for (var i = 0; i < stats.length; i++)
                              (value: stats[i].totalCents, color: monoSlot(i)),
                          ],
                          center: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _type.isExpense ? '支出' : '收入',
                                style: T.caption,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                Fmt.compact(total),
                                style: T.hero.copyWith(fontSize: 20),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: S.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '共 ${stats.length} 个分类',
                                style: T.body2.copyWith(color: C.ink, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: S.sm),
                              for (var i = 0; i < stats.length && i < 5; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 7),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: monoSlot(i),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: S.sm),
                                      Expanded(
                                        child: Text(
                                          stats[i].name,
                                          style: T.caption.copyWith(color: C.ink2),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '${(stats[i].totalCents / (total == 0 ? 1 : total) * 100).toStringAsFixed(0)}%',
                                        style: T.caption,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SectionTitle('分类排行'),
              SectionCard(
                padding: const EdgeInsets.symmetric(vertical: S.sm),
                child: Column(
                  children: [
                    for (var i = 0; i < stats.length; i++)
                      CatRankRow(
                        stat: stats[i],
                        ratio: stats[i].totalCents / maxV,
                        color: monoSlot(i),
                      ),
                  ],
                ),
              ),

              if (_type.isExpense) ...[
                const SectionTitle('每日支出'),
                const SectionCard(child: _DailyTrend()),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _DailyTrend extends StatelessWidget {
  const _DailyTrend();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final values = <int, int>{};
    for (final r in s.dailyTotals) {
      final d = int.tryParse(r.$1.split('-').last);
      if (d != null) values[d] = r.$2;
    }
    final p = s.month.split('-');
    final dayCount = Fmt.daysInMonth(int.parse(p[0]), int.parse(p[1]));
    final today = s.monthIsCurrent ? DateTime.now().day : null;
    final maxV =
        values.values.isEmpty ? 0 : values.values.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DailyBars(dayCount: dayCount, values: values, highlightDay: today),
        const SizedBox(height: S.sm),
        Row(
          children: [
            Text('1日', style: T.caption),
            const Spacer(),
            Text('单日最高 ${Fmt.money(maxV)}', style: T.caption),
            const Spacer(),
            Text('$dayCount日', style: T.caption),
          ],
        ),
      ],
    );
  }
}
