import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/period.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/repo.dart';
import '../../../data/repo/txn_query.dart';
import '../../../data/services/pacing_service.dart';
import '../../../stores/book_store.dart';
import '../../../stores/catalog_store.dart';
import '../../../stores/plan_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/pickers/calendar_sheet.dart';
import '../../widgets/swipe_flip.dart';
import '../../widgets/toast.dart';
import '../debt/debt_detail_sheet.dart';
import '../record/record_sheet.dart';
import 'day_group_list.dart';
import 'filter_sheet.dart';
import 'search_sheet.dart';
import 'summary_card.dart';
import 'txn_row.dart';

/// 明细页（tab 0）。「看 / 改 / 删 / 翻期 / 筛 / 搜」都在这里。
///
/// 列表用 `SliverList.builder`：5,000 笔时只建可视区的日卡（原版一次性
/// build 全部行，滚到月中就开始掉帧）。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with AutomaticKeepAliveClientMixin<DetailPage> {
  final ScrollController _scroll = ScrollController();
  bool _pendingMore = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// 距底 400px 取下一页（取回不足一页 → Store 自己把 hasMore 置假）。
  ///
  /// ★ 滚动回调发生在**布局阶段**，这里绝不能同步改 Store（会在 build 期间
  ///   notify → 框架断言 → 帧循环停不下来）。一律推到帧后执行。
  void _onScroll() => _maybeMore();

  /// 「该不该补一页」的唯一判断，两个入口共用：
  /// - 滚动时（[_onScroll]）；
  /// - 首屏没填满时（滚动事件永远不会来，得靠帧后自查，否则列表只有 12 行
  ///   却明明还有几千条，用户以为账本丢了数据）。
  void _maybeMore() {
    if (!mounted || _pendingMore || !_scroll.hasClients) return;
    final BookStore book = BookScope.of(context);
    if (!book.hasMore || book.isLoadingMore || book.isFiltering) return;
    final double remain =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remain > 400) return;
    _pendingMore = true;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _pendingMore = false;
      if (!mounted) return;
      BookScope.of(context).loadMore();
    });
  }

  Future<void> _openFilter() async {
    final BookStore book = BookScope.of(context);
    final TxnQuery? next = await showFilterSheet(
      context,
      initial: book.query,
      cycleStartDay: book.cycleStartDay,
    );
    if (next == null) return;
    await _applyFilter(next);
  }

  Future<void> _applyFilter(TxnQuery query) async {
    try {
      await BookScope.of(context).applyFilter(query);
    } catch (_) {
      // 查询失败不动 Store（applyFilter 内部已回滚），只提示
      if (mounted) showToast(context, '筛选失败，请重试', error: true);
    }
  }

  Future<void> _openSearch() async {
    final BookStore book = BookScope.of(context);
    final CatalogStore catalog = CatalogScope.of(context);
    final String? keyword = await showSearchSheet(
      context,
      ledgerId: book.ledgerId,
      categoryOf: catalog.displayName,
      accountOf: catalog.accountName,
    );
    if (keyword == null || keyword.trim().isEmpty) return;
    await _applyFilter(TxnQuery(keyword: keyword.trim()));
  }

  Future<void> _onTapTxn(Txn t) async {
    if (t.debtId != null) {
      // 借贷行：进往来详情（用户点它想看「还欠多少」，不是改金额）。
      // 还款流水也走这条路 —— **没有「编辑还款」**：还款金额录错了要删掉重记，
      // 允许改会让「已还」在别的页面算出不同的数（M05-F07）。
      final PlanStore plan = PlanScope.of(context);
      await showDebtDetailSheet(context, debtId: t.debtId!);
      if (!mounted) return;
      await BookScope.of(context).afterTxnChange();
      await plan.reload();
      if (mounted) await CatalogScope.of(context).reloadMoney();
      return;
    }
    final RecordOutcome? outcome = await showRecordSheet(context, editing: t);
    if (outcome == null || !mounted) return;
    await BookScope.of(context).afterTxnChange();
    if (mounted) showToast(context, '已保存');
  }

  Future<void> _onLongPressTxn(Txn t) async {
    final String label = t.debtId != null
        ? (t.type.isIncome ? '借入' : '借出')
        : CatalogScope.of(context).tree.displayName(t.categoryId);
    final bool ok = await showConfirmDialog(
      context,
      title: '删除这笔？',
      body: deleteConfirmBody(t, categoryLabel: label),
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    // 先把 Store 抓住：跨 await 之后再用 context 拿作用域是要挨骂的
    final BookStore book = BookScope.of(context);
    try {
      await Repo.deleteTxn(t);
      await book.afterTxnChange();
      if (mounted) showToast(context, '已删除');
    } catch (_) {
      if (mounted) showToast(context, '删除失败，请重试', error: true);
    }
  }

  void _flip(int delta) {
    final BookStore book = BookScope.of(context);
    if (book.isFiltering) return;
    book.moveCycle(delta);
    book.reloadCycle();
  }

  void _backToToday() {
    final BookStore book = BookScope.of(context);
    book.resetCycleToToday();
    book.reloadCycle();
  }

  Future<void> _pickPeriod() async {
    final BookStore book = BookScope.of(context);
    final LocalDate? picked = await showCalendarSheet(
      context,
      initial: book.cycle.from,
    );
    if (picked == null || !mounted) return;
    await book.jumpTo(Period.cycleRange(picked, book.cycleStartDay));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AppPalette pal = context.pal;
    final BookStore book = BookScope.watch(context);
    final CatalogStore catalog = CatalogScope.watch(context);
    final PlanStore plan = PlanScope.watch(context);

    final List<DayGroup> groups = groupByDay(book.items);
    // 扁平表：日卡头 1 行 + 该日 N 行流水，喂给 SliverList.builder
    final List<Object> entries = <Object>[
      for (final DayGroup g in groups) ...<Object>[g, ...g.items],
    ];

    final int? budgetTotal = plan.budget.totalBudgetCents;
    final Pacing pacing = Pacing.ofRange(
      period: book.cycle,
      totalCents: budgetTotal,
      usedCents: book.totals.expenseCents,
    );

    // 首屏没填满时不会有滚动事件，帧后自查一次（见 [_maybeMore]）
    if (book.hasMore && !book.isFiltering) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) => _maybeMore());
    }

    return ColoredBox(
      color: pal.bg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scroll,
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: SwipeFlip(
                // 筛选态不注册横向识别器：手势让给外层 PageView 切 tab
                enabled: !book.isFiltering,
                onPrev: () => _flip(-1),
                onNext: () => _flip(1),
                onToday: _backToToday,
                onPick: _pickPeriod,
                child: SummaryCard(
                  periodLabel: book.cycle.dotLabel,
                  totals: book.totals,
                  filtering: book.isFiltering,
                  keyword: book.query.keyword,
                  budgetTotalCents: budgetTotal,
                  budgetUsedCents: book.totals.expenseCents,
                  canSpendPerDayCents: pacing.canSpendPerDayCents,
                  remainDays: pacing.remainDays,
                  overCents: pacing.overCents,
                  ledgerName: catalog.ledgerName,
                  onFilter: _openFilter,
                  onSearch: _openSearch,
                ),
              ),
            ),
            if (book.isFiltering)
              SliverToBoxAdapter(
                child: FilterChipsBar(
                  query: book.query,
                  onClear: () => _applyFilter(const TxnQuery()),
                ),
              ),
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (BuildContext ctx, int i) {
                final Object entry = entries[i];
                if (entry is DayGroup) return DayHeader(group: entry);
                final Txn t = entry as Txn;
                return TxnRow(
                  txn: t,
                  categoryLabel: catalog.displayName(t.categoryId),
                  accountLabel: catalog.accountName(t.accountId),
                  debtLabel: debtRowTitle(t),
                  dueLabel: plan.dueLabelOf(t.debtId),
                  onTap: () => _onTapTxn(t),
                  onLongPress: () => _onLongPressTxn(t),
                );
              },
            ),
            SliverToBoxAdapter(
              child: book.items.isEmpty
                  ? SizedBox(
                      height: 240,
                      child: EmptyState(
                        icon: book.isFiltering
                            ? Icons.search_off
                            : Icons.receipt_long_outlined,
                        title: emptyTitle(filtering: book.isFiltering),
                        hint: book.isFiltering
                            ? '换个关键词或放宽条件试试。'
                            : '点中间的「＋」记一笔，或左右滑动看看别的期。',
                      ),
                    )
                  : ListStatusRow(
                      loaded: book.items.length,
                      total: book.totals.count,
                      loading: book.isLoadingMore,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 借贷行标题：「借出 · 张三」。
String debtRowTitle(Txn t) {
  final String dir = t.type.isIncome ? '借入' : '借出';
  final String who = (t.person ?? '').trim();
  return who.isEmpty ? dir : '$dir · $who';
}

/// 筛选条件条：第一枚 chip **明写「全部历史」**（口径 3.7）。
class FilterChipsBar extends StatelessWidget {
  const FilterChipsBar({super.key, required this.query, required this.onClear});

  final TxnQuery query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final List<String> parts = <String>[
      '全部历史',
      if (query.type != null) query.type!.label,
      if ((query.keyword ?? '').isNotEmpty) '「${query.keyword}」',
      if (query.from != null && query.to != null)
        '${query.from!.month}/${query.from!.day}–${query.to!.month}/${query.to!.day}',
      if (query.minCents != null || query.maxCents != null) '金额区间',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.page, 0, S.page, S.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              parts.join(' · '),
              key: const ValueKey<String>('filter-chips'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ts.caption.copyWith(color: pal.ink2),
            ),
          ),
          TextButton(
            key: const ValueKey<String>('filter-clear'),
            onPressed: onClear,
            child: Text('清除', style: Ts.caption.copyWith(color: pal.ink)),
          ),
        ],
      ),
    );
  }
}

/// 空态文案（两套）。抽成函数方便测试直接断言，不必渲染。
String emptyTitle({required bool filtering}) =>
    filtering ? '没有符合条件的记录' : '这一期还没有账目';
