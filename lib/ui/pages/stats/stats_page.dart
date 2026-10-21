import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/period.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/stats_repo.dart';
import '../../../data/repo/txn_query.dart';
import '../../../stores/book_store.dart';
import '../../../stores/catalog_store.dart';
import '../../../stores/plan_store.dart';
import '../../../stores/shell_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chip_tabs.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/pickers/calendar_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/swipe_flip.dart';
import 'category_rank.dart';
import 'daily_bars.dart';
import 'net_worth_card.dart';
import 'pie_chart.dart';
import 'trend_bars.dart';

/// 图表页（tab 1 / 底栏槽位 1）。
///
/// 四张自绘图 + 账户资产，全部**自己画**（不引第三方图表库：依赖越少，
/// 被某个包 breaking change 拖死的概率越小）。
///
/// 三条容易做错的：
/// 1. 首帧 `loaded == false` 画**骨架**，不许画「本期还没有数据」（I20）；
/// 2. 口径切换（本期/本月）只动 `PlanStore` 自己的统计游标，
///    **绝不动 `BookStore.cycle`** —— 否则切一下口径明细页的期就被改了；
/// 3. 下钻到明细一律**带上当前统计区间**，否则「图表 3,874 → 明细另一个数」。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.autoRefresh = true});

  /// 进页面自动去算统计。默认开；测「骨架态」时关掉，
  /// 否则一次 `pump` 就可能把 DB 查完，骨架一闪而过，用例变成掷骰子。
  final bool autoRefresh;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage>
    with AutomaticKeepAliveClientMixin<StatsPage> {
  /// 饼图 / 排行看哪一侧。
  TxnType _chartType = TxnType.expense;

  bool _refreshing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 首帧之后去算。**绝不在 build / initState 里同步查库**（I20）。
    if (widget.autoRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) => _refresh());
    }
  }

  void _refresh() {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    PlanScope.of(context)
        .refreshStats()
        .whenComplete(() => _refreshing = false);
  }

  void _flip(int delta) {
    PlanScope.of(context).flipStats(delta);
    _refresh();
  }

  void _backToToday() {
    PlanScope.of(context).resetStatsToToday();
    _refresh();
  }

  Future<void> _pickRange() async {
    final PlanStore plan = PlanScope.of(context);
    final LocalDate? picked = await showCalendarSheet(
      context,
      initial: plan.statsPeriod.from,
    );
    if (picked == null || !mounted) return;
    plan.jumpStatsTo(picked);
    _refresh();
  }

  /// 下钻到明细：**必须带上当前统计区间**（判据 3.3）。
  ///
  /// 点某一天时区间就是那一天（`from == to`），点排行某一行时是整段区间。
  Future<void> _drill({LocalDate? day, int? categoryId}) async {
    final PlanStore plan = PlanScope.of(context);
    final BookStore book = BookScope.of(context);
    final ShellStore shell = ShellScope.of(context);
    final Period range = plan.statsPeriod;
    final TxnQuery query = day != null
        ? TxnQuery(from: day, to: day)
        : TxnQuery(categoryId: categoryId, from: range.from, to: range.to);
    await book.applyFilter(query);
    if (!mounted) return;
    shell.switchTab(ShellStore.tabDetail);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AppPalette pal = context.pal;
    final PlanStore plan = PlanScope.watch(context);
    final CatalogStore catalog = CatalogScope.watch(context);

    final StatSnapshot snap = plan.stats;
    // 脏了就在帧后补算（不在 build 里查库）
    if (plan.statsStale && widget.autoRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) => _refresh());
    }

    final List<CategoryStat> stats = _chartType == TxnType.expense
        ? snap.expenseCats
        : snap.incomeCats;
    final List<PieSlice> slices = buildPieSlices(stats: stats, chart: pal.chart);
    final List<RankRow> ranks = buildRankRows(stats: stats, chart: pal.chart);
    final List<DailyBarCell> cells = buildDailyCells(snap.daily);
    final int typeTotal = _chartType == TxnType.expense
        ? snap.expenseCents
        : snap.incomeCents;

    return ColoredBox(
      color: pal.bg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: SwipeFlip(
                onPrev: () => _flip(-1),
                onNext: () => _flip(1),
                onToday: _backToToday,
                onPick: _pickRange,
                child: _RangeBar(period: snap.period, scope: plan.statsScope),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: S.sm),
                child: ChipTabs<StatsScope>(
                  items: <ChipTabItem<StatsScope>>[
                    for (final StatsScope s in StatsScope.values)
                      ChipTabItem<StatsScope>(s, s.label),
                  ],
                  selected: plan.statsScope,
                  onChanged: (StatsScope s) {
                    plan.switchStatsScope(s);
                    _refresh();
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: S.sm),
                child: ChipTabs<TxnType>(
                  items: const <ChipTabItem<TxnType>>[
                    ChipTabItem<TxnType>(TxnType.expense, '支出'),
                    ChipTabItem<TxnType>(TxnType.income, '收入'),
                  ],
                  selected: _chartType,
                  onChanged: (TxnType t) => setState(() => _chartType = t),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.page, S.md, S.page, 0),
                child: AppCard(
                  padding: const EdgeInsets.all(S.card),
                  child: !snap.loaded
                      // 没算过 → 骨架（**不是**空态文案）
                      ? const _SkeletonBlock()
                      : snap.isEmpty
                      ? const SizedBox(
                          height: 200,
                          child: EmptyState(
                            icon: Icons.pie_chart_outline,
                            title: '本期还没有数据',
                            hint: '记一笔之后这里会有饼图、排行和每日柱。',
                          ),
                        )
                      : _PieBlock(
                          slices: slices,
                          totalCents: typeTotal,
                          label: _chartType == TxnType.expense ? '支出' : '收入',
                        ),
                ),
              ),
            ),
            if (snap.loaded && ranks.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(child: SectionHeader(title: '分类排行')),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.page),
                  child: CategoryRankList(
                    rows: ranks,
                    onTap: (RankRow r) => _drill(categoryId: r.categoryId),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SectionHeader(title: '每日支出')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.page),
                child: snap.loaded
                    ? Column(
                        children: <Widget>[
                          DailyBars(
                            cells: cells,
                            onPick: (LocalDate d) => _drill(day: d),
                          ),
                          DailyAxisLabels(cells: cells),
                        ],
                      )
                    : const SizedBox(height: 88),
              ),
            ),
            const SliverToBoxAdapter(
              child: SectionHeader(title: '近 6 期', trailing: TrendLegend()),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.page),
                child: TrendBars(segments: snap.trend),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.page, S.lg, S.page, S.xl),
                child: NetWorthCard(
                  assetsCents: snap.accountAssetsCents,
                  accountsCount: catalog.accounts.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区间条：日期范围 + 口径（三手势都挂在 `SwipeFlip` 上）。
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.period, required this.scope});

  final Period period;
  final StatsScope scope;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.page, S.md, S.page, S.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(scope.label, style: Ts.micro.copyWith(color: pal.ink3)),
                const SizedBox(height: 2),
                Text(
                  period.dotLabel,
                  key: const ValueKey<String>('stats-period'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ts.section.copyWith(color: pal.ink),
                ),
              ],
            ),
          ),
          Text(period.shortLabel, style: Ts.micro.copyWith(color: pal.ink4)),
        ],
      ),
    );
  }
}

/// 饼图 + 图例 + 合计。
class _PieBlock extends StatelessWidget {
  const _PieBlock({
    required this.slices,
    required this.totalCents,
    required this.label,
  });

  final List<PieSlice> slices;
  final int totalCents;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        PieChart(slices: slices, size: 132, thickness: 20, centerTop: label),
        const SizedBox(width: S.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AmountText(
                key: const ValueKey<String>('stats-total'),
                cents: totalCents,
                yuan: true,
                tier: AmountTier.heroSm,
              ),
              const SizedBox(height: S.sm),
              PieLegend(slices: slices, maxRows: 5),
            ],
          ),
        ),
      ],
    );
  }
}

/// 骨架块：饼图位置画一圈灰环 + 几条灰条。
class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock();

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Row(
      children: <Widget>[
        const PieSkeleton(size: 132, thickness: 20),
        const SizedBox(width: S.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.sm),
                  child: Container(
                    height: 10,
                    width: i == 2 ? 80 : double.infinity,
                    decoration: BoxDecoration(
                      color: pal.surfaceAlt,
                      borderRadius: R.rPill,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
