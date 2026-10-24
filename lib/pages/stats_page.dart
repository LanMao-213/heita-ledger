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

  /// 点排行里的某个分类 → 明细页只留这个分类。
  ///
  /// 两个细节：
  /// - 排行榜按**根分类**聚合（`COALESCE(parent_id, id)`），所以这里筛的是根，
  ///   筛选侧用 `_catScope` 连带子分类一起命中 —— 点「餐饮」能看到正餐/外卖/聚餐。
  /// - 带上统计页当前的区间。统计页可以是「按月」也可以是「按本期」，
  ///   不带上就会出现「图表显示 3,874，点进去明细却是另一个数」。
  Future<void> _openCategory(CatStat stat) async {
    final s = Store.i;
    s.switchTab(0);
    await s.applyFilter(
      TxnFilter(
        type: _type,
        categoryId: stat.categoryId,
        dateFrom: s.statFrom.isEmpty ? null : s.statFrom,
        dateTo: s.statTo.isEmpty ? null : s.statTo,
      ),
    );
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

    // 图例最多 5 行；超过就把尾部合并成「其余 N 类」——
    // 环形上有几个色块，图例里就必须有几个名字，否则用户找不到第 6 块是谁。
    final legend = <({String name, int cents, Color color})>[];
    const legendCap = 5;
    if (stats.length <= legendCap) {
      for (var i = 0; i < stats.length; i++) {
        legend.add((name: stats[i].name, cents: stats[i].totalCents, color: monoSlot(i)));
      }
    } else {
      for (var i = 0; i < legendCap - 1; i++) {
        legend.add((name: stats[i].name, cents: stats[i].totalCents, color: monoSlot(i)));
      }
      final rest = stats.skip(legendCap - 1);
      legend.add((
        name: '其余 ${rest.length} 类',
        cents: rest.fold<int>(0, (a, e) => a + e.totalCents),
        color: monoSlot(legendCap - 1),
      ));
    }

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: S.xxl),
          children: [
            // 「本期 / 本月」原来独占内容区第一行（约 44dp），
            // 而页头右侧一直空着。它是**口径切换**，属于这一页的标题层，
            // 提到页头右侧之后，省掉一整行，区间条也上升了一层。
            PageHeader(title: '图表', actions: _BasisSwitch()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.lg),
              child: s.statBasis == StatBasis.period
                  ? CycleBar(
                      from: s.statFrom,
                      to: s.statTo,
                      onPrev: () => s.shiftStat(-1),
                      onNext: () => s.shiftStat(1),
                      // 点「10-15 至 11-14」也能弹日历：两条路都通
                      onTapLabel: () => showCalendarAndGo(context),
                      // 双击回到今天所在的期
                      onReset: s.backToCurrentStat,
                    )
                  : MonthBar(
                      month: s.month,
                      onPrev: () => s.shiftStat(-1),
                      onNext: () => s.shiftStat(1),
                      onTapLabel: () =>
                          showCalendarAndGo(context, byMonth: true),
                      // 双击回到本月
                      onReset: s.backToCurrentStat,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: S.lg,
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
                child: Row(
                  children: [
                    Donut(
                      size: 128,
                      thickness: 15,
                      slices: [
                        for (final e in legend)
                          (value: e.cents, color: e.color),
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
                            // 刻意 20：环形直径只有 128，hero(34) 会把
                            // 圆心撑满、和环相撞；20 是「卡片内次级大数字」
                            // 的唯一可取档，别当成漂移收掉。
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
                          // 一句话结论：不读图也知道哪一块最大。
                          // 这一行原来是「共 5 个分类」—— 分类数不是用户要的结论。
                          Text(
                            stats.isEmpty
                                ? ''
                                : '${stats.first.name}占 '
                                    '${(stats.first.totalCents / (total == 0 ? 1 : total) * 100).round()}%，'
                                    '最大的一块',
                            style: T.body2.copyWith(
                              color: C.ink,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: S.sm),
                          // 图例给**金额**而不是百分比：百分比说「占多少」，
                          // 金额说「多少钱」，后者才是记账的人要的。
                          for (final e in legend)
                            Padding(
                              padding: const EdgeInsets.only(bottom: S.sm),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: e.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: S.sm),
                                  Expanded(
                                    child: Text(
                                      e.name,
                                      style: T.caption.copyWith(color: C.ink2),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(Fmt.money(e.cents), style: T.amountSm),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_type.isExpense) ...[
                const SectionTitle('每日支出'),
                SectionCard(child: _DailyTrend(onDayTap: _openDay)),
              ],

              // 「分类排行」原来按金额再排一遍，与上面图例是同一份数据换
              // 一种画法，读起来是「我已经知道了」。换成**按笔数**：
              // 具体金额看上面，这里回答「我总在哪随手花钱」。
              if (stats.length > 1) ...[
                const SectionTitle('记得最多'),
                SectionCard(
                  padding: const EdgeInsets.symmetric(vertical: S.sm),
                  child: Column(
                    children: [
                      for (final st in ([...stats]
                            ..sort((a, b) => b.count.compareTo(a.count)))
                          .take(3))
                        _FreqRow(
                          // 稳定 key：测试要点「某个分类」这一行，
                          // 靠文本找会撞上图例里同名的分类
                          key: ValueKey('freq-${st.categoryId}'),
                          stat: st,
                          onTap: () => _openCategory(st),
                        ),
                    ],
                  ),
                ),
              ],
            ],

            // 下面两块和「支出/收入」切换无关，放在最后
            SectionTitle(s.statBasis == StatBasis.period ? '近 6 期' : '近 6 个月'),
            SectionCard(
              child: s.statTrend.isEmpty
                  ? SizedBox(
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
          // 左右 16 归到 S.lg；上下 6 是胶囊自身的内缩，不是节奏间距，保留原值
          padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 6),
          decoration: BoxDecoration(
            color: on ? C.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(R.pill),
            // 未选中用 line2：底色与页面底只差 1.05:1，line(1.05) 完全看不出
            // 胶囊的边界，选中/未选中就只剩「有无实心」这一条线索
            border: Border.all(color: on ? C.ink : C.line2),
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

/// 「记得最多」的一行：图标 + 名字 + 笔数 + 金额。
///
/// 点一下同样是「明细页只看这个分类」—— 和原排行卡保持同一个手感，
/// 换了维度不等于丢了入口。
class _FreqRow extends StatelessWidget {
  const _FreqRow({super.key, required this.stat, required this.onTap});

  final CatStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: 9),
        child: Row(
          children: [
            LineIcon(stat.icon, size: 19, color: C.ink2),
            const SizedBox(width: S.md),
            Expanded(
              child: Text(
                stat.name,
                style: T.body,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('${stat.count} 笔', style: T.amountSm),
            const SizedBox(width: S.md),
            SizedBox(
              width: 78,
              child: Text(
                Fmt.money(stat.totalCents),
                textAlign: TextAlign.right,
                style: T.caption,
              ),
            ),
          ],
        ),
      ),
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
            // ⚠️ 必须用 C.ink4 —— 柱子在下面画的就是这个色。图例是用户
            // 「按色找柱」的唯一依据，图例色块和柱子不同色，等于给了错的
            // 索引（1.4.21 之前这里写的是 C.ink3，比柱子深一档）。
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
                      style: T.overline.copyWith(letterSpacing: 0),
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
          borderRadius: BorderRadius.circular(R.xs),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: T.overline.copyWith(letterSpacing: 0)),
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
      // 列表卡：行自己补左右 16，卡片只留上下 8
      padding: const EdgeInsets.symmetric(vertical: S.sm),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: S.lg,
              vertical: S.sm,
            ),
            child: Row(
              children: [
                Text('合计', style: T.caption),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Fmt.money(s.netWorthWithDebtCents),
                      style: T.amountXs,
                    ),
                    // 与「我的」页同一口径：账户余额 + 应收 − 应付
                    if (s.receivableCents > 0 || s.payableCents > 0)
                      Text(
                        '含应收 ${Fmt.money(s.receivableCents)} · 应付 ${Fmt.money(s.payableCents)}',
                        style: T.caption.copyWith(color: C.ink3),
                      ),
                  ],
                ),
              ],
            ),
          ),
          for (final a in s.accounts)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: C.line)),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: S.lg,
                vertical: S.sm + 2,
              ),
              child: Row(
                children: [
                  LineIcon(a.icon, size: 17, color: C.ink3),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(
                      a.name,
                      style: T.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    Fmt.money(a.balanceCents),
                    style: T.amountXs.copyWith(
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
