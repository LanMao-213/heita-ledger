import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/calendar_picker.dart';
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

  /// 点趋势图某天 → 明细页只看那天。
  ///
  /// 直接复用筛选那套（TxnFilter + applyFilter），不另造一条「按日查看」的通路，
  /// 这样条件条、清空、与搜索共存等行为都跟手动筛选完全一致。
  Future<void> _openDay(int day) async {
    final s = Store.i;
    // day 是「区间内第几天」，不是「几号」—— 周期可以跨月，按 1 号起算会错
    final date = Fmt.date(
      DateTime.parse(s.statFrom).add(Duration(days: day - 1)),
    );
    // 先切页再查库：切页是即时的，查询要走一次 SQL，先切能少一拍空等
    s.switchTab(0);
    await s.applyFilter(TxnFilter(dateFrom: date, dateTo: date));
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    // 金额允许为负（净额记账），某分类合计可能 ≤0 —— 饼图和排行榜画不出负扇区，
    // 这类分类直接不参与，明细里仍然照常显示
    final stats = (_type.isExpense ? s.statExpenseStats : s.statIncomeStats)
        .where((e) => e.totalCents > 0)
        .toList();
    final total = _type.isExpense ? s.statExpenseCents : s.statIncomeCents;
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
              child: _BasisSwitch(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.xl),
              child: s.statBasis == StatBasis.period
                  ? CycleBar(
                      from: s.statFrom,
                      to: s.statTo,
                      onPrev: () => s.shiftStat(-1),
                      onNext: () => s.shiftStat(1),
                      // 点「10-15 → 11-14」也能弹日历：两条路都通
                      onTapLabel: () => showCalendarAndGo(context),
                    )
                  : MonthBar(
                      month: s.month,
                      onPrev: () => s.shiftStat(-1),
                      onNext: () => s.shiftStat(1),
                      onTapLabel: () =>
                          showCalendarAndGo(context, byMonth: true),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: S.xl,
                vertical: S.sm,
              ),
              child: SegTabs(
                value: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
            ),

            if (stats.isEmpty)
              EmptyHint(
                icon: 'pie',
                text: s.statBasis == StatBasis.period ? '本期还没有数据' : '本月还没有数据',
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
                                style: T.body2.copyWith(
                                  color: C.ink,
                                  fontWeight: FontWeight.w500,
                                ),
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
                                          style: T.caption.copyWith(
                                            color: C.ink2,
                                          ),
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
                SectionCard(child: _DailyTrend(onDayTap: _openDay)),
              ],
            ],

            // 下面两块和「支出/收入」切换无关，放在最后
            SectionTitle(s.statBasis == StatBasis.period ? '近 6 期' : '近 6 个月'),
            SectionCard(
              child: s.statTrend.isEmpty
                  ? const SizedBox(
                      height: 90,
                      child: Center(child: Text('还没有历史数据', style: T.caption)),
                    )
                  : _MonthlyTrend(rows: s.statTrend),
            ),

            const SectionTitle('账户资产'),
            _AccountsCard(),
          ],
        );
      },
    );
  }
}

/// 「本期 / 本月」切换。
///
/// 两个口径的数字本来就会不同：账单日 15 时，10-10 的工资算本期（10-15 起）
/// 还是算 10 月，答案不一样。给按钮就是让用户自己选看哪一种，别偷偷替他决定。
class _BasisSwitch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = Store.i;

    Widget item(StatBasis b, String label) {
      final on = s.statBasis == b;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => s.setStatBasis(b),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: on ? C.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? C.ink : C.line),
          ),
          child: Text(
            label,
            style: T.caption.copyWith(
              color: on ? C.bg : C.ink2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        item(StatBasis.period, '本期'),
        const SizedBox(width: S.sm),
        item(StatBasis.month, '本月'),
      ],
    );
  }
}

class _DailyTrend extends StatelessWidget {
  const _DailyTrend({required this.onDayTap});

  final ValueChanged<int> onDayTap;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final from = DateTime.parse(s.statFrom);
    final to = DateTime.parse(s.statTo);
    final dayCount = to.difference(from).inDays + 1;
    final values = <int, int>{};
    for (final r in s.statDailyTotals) {
      final idx = DateTime.parse(r.$1).difference(from).inDays + 1;
      if (idx >= 1 && idx <= dayCount) values[idx] = r.$2;
    }
    final todayStr = Fmt.today();
    final todayIdx = DateTime.parse(todayStr).difference(from).inDays + 1;
    final today = (todayIdx >= 1 && todayIdx <= dayCount) ? todayIdx : null;
    final maxV = values.values.isEmpty
        ? 0
        : values.values.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DailyBars(
          dayCount: dayCount,
          values: values,
          highlightDay: today,
          onDayTap: (d) {
            // 点空白天没必要跳过去看一个空列表
            final v = values[d] ?? 0;
            if (v <= 0) {
              showToast(context, '这天没有支出');
              return;
            }
            onDayTap(d);
          },
        ),
        const SizedBox(height: S.sm),
        Row(
          children: [
            Text(s.statFrom.substring(5), style: T.caption),
            const Spacer(),
            Text('单日最高 ${Fmt.money(maxV)}', style: T.caption),
            const Spacer(),
            Text(s.statTo.substring(5), style: T.caption),
          ],
        ),
      ],
    );
  }
}

/// 近 6 个月：每月两根柱（支出实心 / 收入浅灰），共用同一根基准线。
///
/// 只用一个颜色会让两组数分不清，用彩色又违反「黑白灰」——
/// 所以按明度分工：支出是主角，用 ink；收入是配角，用 ink4。
class _MonthlyTrend extends StatelessWidget {
  const _MonthlyTrend({required this.rows});

  /// 月视图的 key 是 `2026-10`，周期视图是 `2026-10-15`
  final List<(String label, int expense, int income)> rows;

  @override
  Widget build(BuildContext context) {
    var maxV = 1;
    for (final r in rows) {
      if (r.$2 > maxV) maxV = r.$2;
      if (r.$3 > maxV) maxV = r.$3;
    }
    const barH = 86.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend('支出', C.ink),
            const SizedBox(width: S.lg),
            _legend('收入', C.ink4),
          ],
        ),
        const SizedBox(height: S.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final r in rows)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _bar(r.$2, maxV, barH, C.ink),
                        const SizedBox(width: 3),
                        _bar(r.$3, maxV, barH, C.ink4),
                      ],
                    ),
                    const SizedBox(height: S.sm),
                    Text(
                      r.$1.length == 7
                          ? '${int.parse(r.$1.substring(5))}月'
                          : r.$1.substring(5),
                      style: T.caption.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: T.caption.copyWith(fontSize: 11.5)),
    ],
  );

  /// 零值不画柱：留 2px 会让人以为「那个月花了点钱」。
  Widget _bar(int value, int maxV, double barH, Color color) {
    final h = value <= 0 ? 0.0 : value / maxV * barH;
    return Container(
      width: 11,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    );
  }
}

/// 账户资产：合计 + 每个账户一行余额。
///
/// 账户余额本来只在「我的」里能看到，而统计页才是用户关心「我现在有多少钱」的地方。
class _AccountsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: S.xs),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
            child: Row(
              children: [
                Text('合计', style: T.caption),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Fmt.money(s.netWorthWithDebtCents),
                      style: T.amountSm.copyWith(fontSize: 14),
                    ),
                    // 与「我的」页同一口径：账户余额 + 应收 − 应付
                    if (s.receivableCents > 0 || s.payableCents > 0)
                      Text(
                        '含应收 ${Fmt.money(s.receivableCents)} · 应付 ${Fmt.money(s.payableCents)}',
                        style: T.caption.copyWith(color: C.ink4),
                      ),
                  ],
                ),
              ],
            ),
          ),
          for (final a in s.accounts)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: C.line)),
              ),
              padding: const EdgeInsets.fromLTRB(
                S.md,
                S.sm + 2,
                S.md,
                S.sm + 2,
              ),
              child: Row(
                children: [
                  LineIcon(a.icon, size: 17, color: C.ink3),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(
                      a.name,
                      style: T.body.copyWith(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    Fmt.money(a.balanceCents),
                    style: T.amountSm.copyWith(
                      fontSize: 13.5,
                      color: a.balanceCents < 0 ? C.over : C.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
