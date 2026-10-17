import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: S.xxl),
                children: [
                  _SummaryCard(),
                  if (s.monthTxns.isEmpty)
                    const EmptyHint(
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
    for (final (date, items) in s.groupedByDay) {
      final dayExpense = items
          .where((t) => t.type.isExpense)
          .fold<int>(0, (a, t) => a + t.amountCents);
      final dayIncome = items
          .where((t) => t.type.isIncome)
          .fold<int>(0, (a, t) => a + t.amountCents);

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
            onPressed: () => _search(context),
            icon: const Icon(Icons.search_rounded, size: 20, color: C.ink2),
            splashRadius: 20,
          ),
          const SizedBox(width: S.sm),
        ],
      ),
    );
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
    final hits =
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
            SheetHeader(title: '搜索「$keyword」 · ${hits.length} 条'),
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
    return SectionCard(
      margin: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  value: Fmt.money(s.monthExpenseCents),
                  emphasize: true,
                ),
              ),
              Container(width: 1, height: 34, color: C.line),
              Expanded(
                child: _Metric(
                  label: '收入',
                  value: Fmt.money(s.monthIncomeCents),
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              Text('结余', style: T.caption),
              const SizedBox(width: S.sm),
              Text(
                Fmt.money(s.monthIncomeCents - s.monthExpenseCents, sign: true),
                style: T.amountSm.copyWith(
                  color: C.ink2,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              Text('${s.monthTxnCount} 笔', style: T.caption),
            ],
          ),
          if (s.totalBudgetCents != null) ...[
            const SizedBox(height: S.lg),
            _BudgetLine(),
          ],
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
        Text(
          value,
          style: T.hero.copyWith(fontSize: emphasize ? 30 : 24),
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
              txn.type.isIncome
                  ? '+${Fmt.money(txn.amountCents)}'
                  : '-${Fmt.money(txn.amountCents)}',
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
          ' · ${Fmt.money(txn.amountCents)}',
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
