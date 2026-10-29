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
      DateTime.parse(s.stats.from).add(Duration(days: day - 1)),
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
  Future<void> _openCategory(int categoryId) async {
    final s = Store.i;
    s.switchTab(0);
    await s.applyFilter(
      TxnFilter(
        type: _type,
        categoryId: categoryId,
        dateFrom: s.stats.from.isEmpty ? null : s.stats.from,
        dateTo: s.stats.to.isEmpty ? null : s.stats.to,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    // 金额允许为负（净额记账），某分类合计可能 ≤0 —— 饼图和排行榜画不出负扇区，
    // 这类分类直接不参与，明细里仍然照常显示
    final stats = (_type.isExpense ? s.stats.expenseStats : s.stats.incomeStats)
        .where((e) => e.totalCents > 0)
        .toList();
    final total = _type.isExpense ? s.stats.expenseCents : s.stats.incomeCents;

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

    // 「预算 vs 实际」只认**设过额度**的分类：没额度的没有对比对象，
    // 塞进来只会让轨道恒满。这里按 categoryId 索引，供下面那张合并后的
    // 「各分类消费统计」同一行内展示预算进度。
    final budgetOf = <int, BudgetStat>{
      for (final b in s.budgetStats)
        if (b.budgetCents > 0) b.categoryId: b,
    };

    // 合并后的行：**按金额降序**（已拍板）。笔数退为次要信息，占比与预算进度
    // 同列展示。三处口径必须一起读：
    // - 金额/占比：本页区间内的分类聚合（`stats`，已按金额降序）；
    // - 预算：`budgetStats`（按一级分类聚合，含全部子分类的支出）；
    // - 笔数：`stats` 里的 `count`。
    //
    // 设了预算、但这段区间里一分没花的分类也要出现，否则原来「预算 vs 实际」
    // 里那条 0% 的信息会凭空消失。
    final catRows = <_CatRowData>[
      for (final st in stats)
        _CatRowData(
          categoryId: st.categoryId,
          name: st.name,
          icon: st.icon,
          cents: st.totalCents,
          count: st.count,
          budget: budgetOf[st.categoryId],
        ),
      for (final b in s.budgetStats)
        if (b.budgetCents > 0 && !stats.any((e) => e.categoryId == b.categoryId))
          _CatRowData(
            categoryId: b.categoryId,
            name: b.name,
            icon: b.icon,
            // 这一段区间里确实没有支出 —— 不是「没查到」，是真的 0
            cents: 0,
            count: 0,
            budget: b,
          ),
    ]..sort((a, b) => b.cents.compareTo(a.cents));

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: S.xxl),
          children: [
            // 「本期 / 本月」原来独占内容区第一行（约 44dp），
            // 而页头右侧一直空着。它是**口径切换**，属于这一页的标题层，
            // 提到页头右侧之后，省掉一整行，区间条也上升了一层。
            PageHeader(
              title: '图表',
              leading: const MenuButton(),
              actions: _BasisSwitch(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.lg),
              child: s.stats.byPeriod
                  ? CycleBar(
                      from: s.stats.from,
                      to: s.stats.to,
                      onPrev: () => s.shiftStat(-1),
                      onNext: () => s.shiftStat(1),
                      // 点「10-15 至 11-14」也能弹日历：两条路都通
                      onTapLabel: () => showCalendarAndGo(context),
                      // 双击回到今天所在的期
                      onReset: s.backToCurrentStat,
                    )
                  : MonthBar(
                      month: s.stats.month,
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
                text: s.stats.byPeriod ? '本期还没有数据' : '本月还没有数据',
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
                                    '${Fmt.percent(stats.first.totalCents / (total == 0 ? 1 : total))}，'
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

              // ★ 1.5.2：原来这里是两张卡 —— 「记得最多」（按笔数）+ 「预算 vs
              // 实际」（按金额）。同一批分类换两种画法各占一块，读起来是
              // 「我已经知道了」。合并成一张**按金额降序**的表（口径已拍板），
              // 笔数降为次要信息，占比与预算进度同列展示。
              if (catRows.isNotEmpty) ...[
                SectionTitle(_type.isExpense ? '各分类消费统计' : '各分类收入统计'),
                SectionCard(
                  padding: const EdgeInsets.symmetric(vertical: S.sm),
                  child: Column(
                    children: [
                      for (final r in catRows)
                        _CatStatRow(
                          // 稳定 key：测试要点「某个分类」这一行，
                          // 靠文本找会撞上图例里同名的分类
                          key: ValueKey('freq-${r.categoryId}'),
                          row: r,
                          totalCents: total,
                          onTap: () => _openCategory(r.categoryId),
                        ),
                    ],
                  ),
                ),
              ],
            ],

            // 下面两块和「支出/收入」切换无关，放在最后
            SectionTitle(s.stats.byPeriod ? '近 6 期' : '近 6 个月'),
            SectionCard(
              child: s.stats.trend.isEmpty
                  ? SizedBox(
                      height: 90,
                      child: Center(child: Text('还没有历史数据', style: T.caption)),
                    )
                  : _MonthlyTrend(rows: s.stats.trend),
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
      final on = s.stats.basis == b;
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

/// 「各分类消费统计」的一行数据。
///
/// 为什么不直接拼一个 record：这一行要同时承载**三套口径**（分类聚合的金额/笔数、
/// 预算表的额度/已用、以及占比要用的区间合计），用没有名字的 positional record
/// 传进去，读代码时得回头数第几个字段是什么。给字段起名字更便宜。
class _CatRowData {
  const _CatRowData({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.cents,
    required this.count,
    this.budget,
  });

  final int categoryId;
  final String name;
  final String icon;

  /// 本区间的金额（分）。可能是 0（只有预算、这段区间没花）
  final int cents;

  /// 本区间的笔数
  final int count;

  /// 该分类这一期的预算（没设就是 null）
  final BudgetStat? budget;
}

/// 「各分类消费统计」的一行：图标 + 名字 + 笔数 + 金额，下面一条进度条。
///
/// 进度条的分母**随有没有预算而变化**：
/// - 有预算 → 画的是「预算用掉多少」，超支转红（`Bar` 是全应用唯一用红色的地方）；
/// - 没预算 → 画的是「占本区间总额多少」，那是这一行唯一能比的基准。
///
/// 第二行固定三段：**占比（左）· 进度条 · 预算或超支（右）**。占比放在左端
/// 而不是右端，是因为它每一行都有；预算只有设过额度的那几行才有，缺谁都不能
/// 让另一半跟着左右横跳。
class _CatStatRow extends StatelessWidget {
  const _CatStatRow({
    super.key,
    required this.row,
    required this.totalCents,
    required this.onTap,
  });

  final _CatRowData row;

  /// 本区间的合计（占比的分母）。0 时占比按 0 处理，不做除零。
  final int totalCents;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final budget = row.budget;
    final share = totalCents <= 0 ? 0.0 : row.cents / totalCents;
    final over = budget?.over ?? false;
    final ratio = budget == null ? share : budget.ratio;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: 9),
        child: Column(
          children: [
            Row(
              children: [
                LineIcon(row.icon, size: 19, color: C.ink2),
                const SizedBox(width: S.md),
                Expanded(
                  child: Text(
                    row.name,
                    style: T.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 笔数是**次要信息**：先看金额，再看「这一类我记了几次」
                Text('${row.count} 笔', style: T.amountSm),
                const SizedBox(width: S.md),
                SizedBox(
                  width: 86,
                  child: Text(
                    Fmt.money(row.cents),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caption.copyWith(color: over ? C.over : C.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // 占比在**左**、预算在**右**，中间那条进度条随预算有无换分母。
                // 三者的宽度都定死（数据位数不可控），只有进度条吃弹性 ——
                // 金额位数一变就换行/溢出的那类问题，在这里靠"谁让谁"解决，
                // 不靠调字号。
                SizedBox(
                  width: 54,
                  child: Text(
                    '占 ${Fmt.percent(share)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caption.copyWith(color: C.ink3),
                  ),
                ),
                Expanded(child: Bar(ratio: ratio, over: over, height: 4)),
                if (budget != null) ...[
                  const SizedBox(width: S.sm),
                  SizedBox(
                    width: 84,
                    child: Text(
                      over
                          ? '超 ${Fmt.money(budget.overCents, trimZero: true)}'
                          : '预算 ${Fmt.money(budget.budgetCents, trimZero: true)}',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.caption.copyWith(
                        color: over ? C.over : C.ink3,
                      ),
                    ),
                  ),
                ],
              ],
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
    final from = DateTime.parse(s.stats.from);
    final to = DateTime.parse(s.stats.to);
    final dayCount = to.difference(from).inDays + 1;
    final values = <int, int>{};
    for (final r in s.stats.daily) {
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
            Text(s.stats.from.substring(5), style: T.caption),
            // 中间这段是唯一可变长的：日期是定长，而「单日最高 + 金额」会随
            // 金额位数一路变宽。给它弹性 + 单行收口，两端日期才守得住位置。
            Expanded(
              child: Text(
                '单日最高 ${Fmt.money(maxV)}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.caption,
              ),
            ),
            Text(s.stats.to.substring(5), style: T.caption),
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
///
/// 「折线」是 P2 新增的第二副面孔：柱子天生把「没记账」画成 0 高，
/// 看上去就是「这个月一分没花」。折线会把 0 收 0 支的月份**断开**，
/// 让"没有数据"和"花了 0"在图上不是同一个东西。
///
/// ★ 切换方式（2026-10-28 用户要求）：右上角原来并排两枚「柱状 / 折线」胶囊，
/// 现在**整张卡片就是开关**，点一下换一种。去掉胶囊不只是「碍眼」：两枚胶囊
/// 各只有 44×24 的落点，还得先看清哪个是当前态；整卡点击面大了二十倍，手指
/// 落在图上任何地方都算数。代价是「能切换」不再自解释，所以在图下面留一句
/// 「点卡片切到 X」—— 这句话本身就是那个被删掉的按钮。
class _MonthlyTrend extends StatefulWidget {
  const _MonthlyTrend({required this.rows});

  /// 月视图的 key 是 `2026-10`，周期视图是 `2026-10-15`
  final List<(String label, int expense, int income)> rows;

  @override
  State<_MonthlyTrend> createState() => _MonthlyTrendState();
}

class _MonthlyTrendState extends State<_MonthlyTrend> {
  /// false = 柱状（默认，沿用既有观感）；true = 折线（能看出断月）
  bool _line = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    var maxV = 1;
    for (final r in rows) {
      if (r.$2 > maxV) maxV = r.$2;
      if (r.$3 > maxV) maxV = r.$3;
    }
    const barH = 86.0;

    return Semantics(
      // 整卡可点，读屏要能说清「点一下会发生什么」，否则只剩一个没有名字的
      // 按钮区域（原来两枚胶囊自带文字，删掉后必须补上这条语义）
      button: true,
      label: _line ? '趋势图：折线。点按切换为柱状' : '趋势图：柱状。点按切换为折线',
      child: GestureDetector(
        // 1.6.0：可见的「点卡片切到柱状/折线」提示被去掉之后，测试与读屏
        // 都需要一个稳定的抓手，这里给整卡一个 key。
        key: const ValueKey('stats_trend_card'),
        // opaque：图里大片的空白（柱子上方、折线下方）也要能点
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _line = !_line),
        child: Column(
          children: [
            Row(
              children: [
                _legend('支出', C.ink),
                if (!_line) ...[
                  const SizedBox(width: S.lg),
                  // ⚠️ 必须用 C.ink4 —— 柱子在下面画的就是这个色。图例是用户
                  // 「按色找柱」的唯一依据，图例色块和柱子不同色，等于给了错的
                  // 索引（1.4.21 之前这里写的是 C.ink3，比柱子深一档）。
                  _legend('收入', C.ink4),
                ],
              ],
            ),
            const SizedBox(height: S.md),
            if (_line)
              MonthTrendLine(
                points: [
                  for (final r in rows)
                    (
                      label: _labelOf(r.$1),
                      // 收、支都是 0 = 这个月一条记录都没有 → 断开。
                      // 账本里"整月一笔没记"和"整月花了 0 元"在数据上无法区分，
                      // 但前者是常见事实，且把前者画成 0 会误导趋势判断。
                      value: (r.$2 == 0 && r.$3 == 0) ? null : r.$2,
                    ),
                ],
              )
            else
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
                            _labelOf(r.$1),
                            style: T.overline.copyWith(letterSpacing: 0),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            // 1.6.0 按用户要求去掉「点卡片切到柱状/折线」这行常驻提示：
            // 它每张图下面都挂一句，而且词还跟着状态来回变（柱状/折线），
            // 喧宾夺主。可点性由上面 Semantics 的 label 兜住，读屏仍读得出来；
            // 视觉上不再提示 —— 这张卡是「看数据」的，不是「教你用」的。
            //
            // 只有折线模式的断月说明留着：那是**数据本身的含义**，不是操作提示。
            if (_line) ...[
              const SizedBox(height: S.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '0 收 0 支的月份断开 —— 多半是整月没记账',
                  style: T.caption.copyWith(color: C.ink4),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _labelOf(String key) =>
      key.length == 7 ? '${int.parse(key.substring(5))}月' : key.substring(5);

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
