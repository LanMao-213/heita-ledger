import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../data/ui_flags.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/detail/summary_card.dart';
import '../widgets/detail/txn_row.dart';
import '../widgets/filter_sheet.dart';
import 'period_all_page.dart';

/// 明细页（首页）：按周期看每一笔。
class DetailPage extends StatelessWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.i;

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        // 分组在这里算**一次**并复用：`groupedVisibleByDay` 每次访问都会重新
        // 建一遍 map 再排序，放进 itemBuilder 就成了「每张卡算一遍」。
        final groups = s.groupedVisibleByDay;

        return Column(
          children: [
            const _TopBar(),
            // 类型快捷筛选：留了开关（UiFlags.typeChips），后期看效果决定去留
            if (UiFlags.typeChips) const _TypeChips(),
            if (s.filtering) _FilterBar(),
            Expanded(
              // ★ 懒加载（1.5.0）：原来是 `ListView(children: [...])`，一期几百笔
              //   会一次性构建所有行 —— 1.4.4 的「明细只显示 500 条」就是为了躲它。
              //   换成 `SliverList.builder` 后只构建可视区域内的那几张日卡，
              //   滚动时才按需建下一张，摊还成本与屏高成正比，与总条数无关。
              child: CustomScrollView(
                slivers: [
                  // 不加 const：这几块直接读 Store.i，const 会被 Flutter 当成
                  // 「同一个 widget」跳过重建，筛选切换后数字会停在旧口径
                  SliverToBoxAdapter(child: SummaryCard()),
                  if (s.visibleTxns.isEmpty)
                    SliverToBoxAdapter(
                      child: s.filtering
                          ? const EmptyHint(
                              icon: 'list',
                              text: '没有符合条件的记录',
                              hint: '试试放宽条件，或点上面的「重置」',
                            )
                          : const EmptyHint(
                              icon: 'doc',
                              text: '这一期还没有记账',
                              hint: '点下面的「＋」记第一笔',
                            ),
                    )
                  else
                    SliverList.builder(
                      // 超大批量时的兜底提示仍留在末尾（见 _MoreHint）：
                      // 上限已经从 500 提到 2000，但「说不清楚少了」这个毛病不能回来
                      itemCount: groups.length + (s.txnTruncated ? 1 : 0),
                      itemBuilder: (context, i) => i >= groups.length
                          ? const _MoreHint()
                          : _dayCard(context, s, groups[i]),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: S.xxl)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 一天的卡：日期头 + 当日小计 + 当天的每一笔。
  ///
  /// 参数是「一天」而不是整个列表 —— 懒加载要求每次只产出一张卡。
  Widget _dayCard(
    BuildContext context,
    Store s,
    (String date, List<Txn> items) group,
  ) {
    final (date, items) = group;
    // 交叉归集：支出里的负数计入收入，收入里的负数计入支出
    final dayExpense = sumBySide(items, TxnType.expense);
    final dayIncome = sumBySide(items, TxnType.income);

    return Container(
          margin: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, 0),
          decoration: BoxDecoration(
            color: C.bg,
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: C.line),
            // 极淡的投影：白卡叠在白底上只靠 1px 描边，看起来还是一条长列表；
            // 一点点投影就够让它「浮」起来，不至于抢走顶部概览卡的分量
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A14161A),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // 日期是这张卡的头，放在卡里 —— 挂在卡外面的话，
              // 一屏几张卡会读成一串「小标题 + 列表」，不像卡片
              Padding(
                padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
                child: Row(
                  children: [
                    // 日期让出剩余宽度：某天既有收入又有支出、数字又长时，
                    // 三个 Text 并排会顶出屏幕（真机上表现为右侧被裁掉一截）
                    Expanded(
                      child: Text(
                        Fmt.friendly(date),
                        style: T.caption.copyWith(
                          color: C.ink2,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (dayIncome > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: S.sm),
                        child: Text(
                          '收入 ${Fmt.money(dayIncome)}',
                          style: T.caption.copyWith(color: C.ink2),
                        ),
                      ),
                    if (dayExpense > 0)
                      Text('支出 ${Fmt.money(dayExpense)}', style: T.caption),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: C.line),
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: C.line,
                    indent: 56,
                  ),
                TxnRow(txn: items[i]),
              ],
            ],
          ),
        );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Padding(
      padding: const EdgeInsets.only(top: S.sm),
      child: Row(
        children: [
          const SizedBox(width: S.xl),
          Text(s.currentLedger?.name ?? '账本', style: T.title),
          const SizedBox(width: S.sm),
          if (s.ledgers.length > 1)
            GestureDetector(
              onTap: () => _pickLedger(context),
              child: const Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: C.ink3,
              ),
            ),
          const Spacer(),
          IconButton(
            onPressed: () => _openFilter(context),
            tooltip: '筛选',
            icon: Icon(
              Icons.tune_rounded,
              size: 20,
              color: s.filtering ? C.ink : C.ink2,
            ),
            splashRadius: 20,
          ),
          IconButton(
            onPressed: () => _search(context),
            icon: const Icon(Icons.search_rounded, size: 20, color: C.ink2),
            splashRadius: 20,
          ),
          const SizedBox(width: S.sm),
        ],
      ),
    );
  }

  Future<void> _openFilter(BuildContext context) async {
    final s = Store.i;
    final f = await showFilterSheet(context, s.filter);
    if (f == null) return;
    try {
      await s.applyFilter(f);
    } catch (_) {
      if (context.mounted) showToast(context, '筛选失败，请重试');
    }
  }

  Future<void> _pickLedger(BuildContext context) async {
    final s = Store.i;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(title: '切换账本'),
            for (final l in s.ledgers)
              SettingRow(
                icon: l.icon,
                title: l.name,
                trailing: l.id == s.ledgerId
                    ? const Icon(Icons.check_rounded, size: 20, color: C.ink)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  // 切过去的账本可能欠着好几期周期账单，补记是 switchLedger 做的，
                  // 这里只负责说出来
                  final added = await s.switchLedger(l.id);
                  if (added > 0 && context.mounted) {
                    showToast(context, '已补记 $added 笔周期账单');
                  }
                },
              ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }

  Future<void> _search(BuildContext context) async {
    final s = Store.i;
    final keyword = await showSearch<String>(
      context: context,
      delegate: _SearchDelegate(),
    );
    if (keyword == null || keyword.trim().isEmpty) return;
    final (hits, truncated) = await Repo.searchTxns(
      ledgerId: s.ledgerId,
      keyword: keyword,
    );
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx2, controller) => Column(
          children: [
            SheetHeader(
              title: '搜索「$keyword」 · ${hits.length}${truncated ? '+' : ''} 条',
            ),
            Expanded(
              child: hits.isEmpty
                  ? const EmptyHint(text: '没有找到匹配的记录')
                  : ListView.builder(
                      controller: controller,
                      itemCount: hits.length,
                      itemBuilder: (c, i) =>
                          TxnRow(txn: hits[i], showDate: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchDelegate extends SearchDelegate<String> {
  /// 搜索范围 1.4.4 起扩到分类名、账户名、金额 —— 输入框里得先说清，
  /// 否则用户还是只会往备注上试
  @override
  String get searchFieldLabel => '备注、分类、账户、金额';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, ''),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox.shrink();

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: InputBorder.none,
      hintStyle: TextStyle(color: C.ink4),
    ),
  );
}

/// 顶部类型快捷筛选：全部 / 支出 / 收入 / 转账。
///
/// 只改 `TxnFilter.type`，用户已经设好的分类、金额区间、时间段原样保留
/// （`TxnFilter.withType`），否则点一下「支出」就把别的条件清掉了。
class _TypeChips extends StatelessWidget {
  const _TypeChips();

  static const _items = <(TxnType?, String)>[
    (null, '全部'),
    (TxnType.expense, '支出'),
    (TxnType.income, '收入'),
    (TxnType.transfer, '转账'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final cur = s.filter.type;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: 2),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(width: S.sm),
        itemBuilder: (context, i) {
          final (type, label) = _items[i];
          final on = cur == type;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final f = s.filter.withType(type);
              if (f.isEmpty) {
                s.clearFilter();
              } else {
                s.applyFilter(f);
              }
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: on ? C.ink : C.bg2,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: on ? C.bg : C.ink2,
                  fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 明细被上限截断时，列表末尾的说明 + 「看全部」入口。
///
/// 做成整条可点，而不是只在文字里放个链接：这一行的唯一用途就是跳转，
/// 手指点哪儿都该管用。
class _MoreHint extends StatelessWidget {
  const _MoreHint();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.card),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PeriodAllPage()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 14),
          decoration: BoxDecoration(
            color: C.bg2,
            borderRadius: BorderRadius.circular(R.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '仅显示最近 ${Store.txnPageLimit} 条'
                  '${s.txnCount > Store.txnPageLimit ? ' · 本期共 ${s.txnCount} 笔' : ''}',
                  style: T.caption.copyWith(color: C.ink2),
                ),
              ),
              Text(
                '查看本期全部',
                style: T.caption.copyWith(
                  color: C.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: C.ink2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选条件条：常驻在顶部，随时能看清当前条件并一键清空
class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final f = s.filter;
    final chips = <String>[
      if (f.type != null) f.type!.label,
      if (f.categoryId != null) s.categoryOf(f.categoryId)?.name ?? '已删除分类',
      if (f.accountId != null) s.accountOf(f.accountId)?.name ?? '已删除账户',
      if (f.amountLabel != null) f.amountLabel!,
      if (f.dateLabel != null) f.dateLabel!,
      if (s.filterTruncated) '仅显示前 ${Repo.searchLimit} 条',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(S.xl, 0, S.sm, S.sm),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: S.sm),
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: C.bg2,
                          borderRadius: BorderRadius.circular(R.sm),
                        ),
                        child: Text(
                          c,
                          style: T.caption.copyWith(
                            color: C.ink2,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => s.clearFilter(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: S.sm,
                vertical: 4,
              ),
              child: Text(
                '重置',
                style: T.caption.copyWith(
                  color: C.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
