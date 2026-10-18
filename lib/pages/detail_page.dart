import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/record_sheet.dart';

/// 明细页（首页）：按月看每一笔。
class DetailPage extends StatelessWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.i;

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return Column(
          children: [
            const _TopBar(),
            if (s.filtering) _FilterBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: S.xxl),
                children: [
                  // 不加 const：这几块直接读 Store.i，const 会被 Flutter 当成
                  // 「同一个 widget」跳过重建，筛选切换后数字会停在旧口径
                  _SummaryCard(),
                  if (s.visibleTxns.isEmpty)
                    s.filtering
                        ? const EmptyHint(
                            icon: 'list',
                            text: '没有符合条件的记录',
                            hint: '试试放宽条件，或点上面的「重置」',
                          )
                        : const EmptyHint(
                            icon: 'doc',
                            text: '这个月还没有记账',
                            hint: '点下面的「＋」记第一笔',
                          )
                  else
                    ..._dayGroups(context, s),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _dayGroups(BuildContext context, Store s) {
    final out = <Widget>[];
    for (final (date, items) in s.groupedVisibleByDay) {
      // 交叉归集：支出里的负数计入收入，收入里的负数计入支出
      final dayExpense = sumBySide(items, TxnType.expense);
      final dayIncome = sumBySide(items, TxnType.income);

      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.sm),
        child: Row(
          children: [
            Text(Fmt.friendly(date), style: T.caption),
            const Spacer(),
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
      ));

      out.add(SectionCard(
        padding: const EdgeInsets.symmetric(vertical: S.xs),
        margin: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 0),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, thickness: 1, color: C.line, indent: 56),
              _TxnRow(txn: items[i]),
            ],
          ],
        ),
      ));
    }
    return out;
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
          Text(
            s.currentLedger?.name ?? '账本',
            style: T.title,
          ),
          const SizedBox(width: S.sm),
          if (s.ledgers.length > 1)
            GestureDetector(
              onTap: () => _pickLedger(context),
              child: const Icon(Icons.expand_more_rounded, size: 18, color: C.ink3),
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
                  await s.switchLedger(l.id);
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
    final (hits, truncated) =
        await Repo.searchTxns(ledgerId: s.ledgerId, keyword: keyword);
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
                      itemBuilder: (c, i) => _TxnRow(txn: hits[i], showDate: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchDelegate extends SearchDelegate<String> {
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    // 筛选态下这张卡整体换口径：月份条换成结果摘要，数字改成筛选结果合计，
    // 预算进度条收起（预算按月，跟跨月筛选没有关系）
    final filtering = s.filtering;
    final expense = filtering ? s.filteredExpenseCents : s.monthExpenseCents;
    final income = filtering ? s.filteredIncomeCents : s.monthIncomeCents;
    // 笔数也用聚合里的真实值：列表可能被截到 500 条，但「共几笔」不该跟着少算
    final count = filtering ? s.filterCount : s.monthTxnCount;

    return SectionCard(
      margin: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (filtering)
            _FilterHead()
          else
            MonthBar(
              month: s.month,
              onPrev: () => s.shiftMonth(-1),
              onNext: () => s.shiftMonth(1),
            ),
          const SizedBox(height: S.md),
          const Divider(height: 1, color: C.line),
          const SizedBox(height: S.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _Metric(
                  label: '支出',
                  value: Fmt.money(expense),
                  emphasize: true,
                ),
              ),
              Container(width: 1, height: 34, color: C.line),
              Expanded(
                child: _Metric(
                  label: '收入',
                  value: Fmt.money(income),
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              Text(filtering ? '收支差' : '结余', style: T.caption),
              const SizedBox(width: S.sm),
              Text(
                Fmt.money(income - expense, sign: true),
                style: T.amountSm.copyWith(
                  color: C.ink2,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              Text('$count 笔', style: T.caption),
            ],
          ),
          if (!filtering && s.totalBudgetCents != null) ...[
            const SizedBox(height: S.lg),
            _BudgetLine(),
          ],
        ],
      ),
    );
  }
}

/// 筛选态下替代月份条的那行：说清「这是筛选结果，共几笔，覆盖哪段时间」
class _FilterHead extends StatelessWidget {
  const _FilterHead();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Row(
      children: [
        const Text('筛选结果', style: T.section),
        const Spacer(),
        Flexible(
          child: Text(
            s.filter.dateLabel ?? '全部时间',
            style: T.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
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
              padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 4),
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

class _BudgetLine extends StatelessWidget {
  const _BudgetLine();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final budget = s.totalBudgetCents!;
    final used = budget <= 0 ? 0.0 : s.monthExpenseCents / budget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('本月预算', style: T.caption),
            const SizedBox(width: S.sm),
            Text(
              '${Fmt.money(s.monthExpenseCents)} / ${Fmt.money(budget)}',
              style: T.amountSm.copyWith(fontSize: 13),
            ),
            const Spacer(),
            if (s.overBudget)
              Text(
                '超支 ${Fmt.money(s.overBudgetCents)}',
                style: T.caption.copyWith(
                  color: C.over,
                  fontWeight: FontWeight.w500,
                ),
              )
            else
              Text(
                '剩余 ${Fmt.money(s.budgetLeftCents)}',
                style: T.caption,
              ),
          ],
        ),
        const SizedBox(height: S.sm),
        Bar(ratio: used, over: s.overBudget),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.align = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final bool emphasize;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: T.caption),
        const SizedBox(height: 4),
        // 金额到五位数（比如房租 1,953,500.00）会超出半张卡片的宽度，
        // 原来会折成「1,953,500.」+「00」两行 —— 用 FittedBox 等比缩一点，
        // 始终单行显示。数字短时 scaleDown 不会放大，字号不变。
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align == CrossAxisAlignment.end
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: T.hero.copyWith(fontSize: emphasize ? 30 : 24),
          ),
        ),
      ],
    );
  }
}

/// 单条交易。点按进入编辑，长按删除。
class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.txn, this.showDate = false});

  final Txn txn;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final cat = s.categoryOf(txn.categoryId);
    final acc = s.accountOf(txn.accountId);

    final title = txn.note.isNotEmpty ? txn.note : (cat?.name ?? '未分类');
    final subParts = <String>[
      if (cat != null && txn.note.isNotEmpty) cat.name,
      if (showDate) Fmt.md(txn.date),
      if (acc != null) acc.name,
    ];

    return InkWell(
      onTap: () => showRecordSheet(context, editing: txn),
      onLongPress: () => _confirmDelete(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: C.bg2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: LineIcon(
                  cat?.icon ?? 'more',
                  size: 19,
                  color: C.ink,
                ),
              ),
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: T.body.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subParts.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subParts.join(' · '),
                      style: T.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: S.sm),
            Text(
              // 用 signedCents：支出为负、收入为正。金额本身为负（净额，如代购
              // 对方多给的钱）时符号自然翻转，不会出现「--20.00」
              Fmt.money(txn.signedCents, sign: true),
              style: T.amount.copyWith(
                color: txn.type.isIncome ? C.ink2 : C.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔记录？', style: T.section),
        content: Text(
          '${txn.note.isNotEmpty ? txn.note : (Store.i.categoryOf(txn.categoryId)?.name ?? '未分类')}'
          ' · ${Fmt.money(txn.signedCents, sign: true)}',
          style: T.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: C.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: C.over)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Store.i.deleteTxn(txn);
    if (context.mounted) showToast(context, '已删除');
  }
}
