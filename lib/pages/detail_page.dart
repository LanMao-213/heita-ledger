import 'package:flutter/material.dart';

import '../data/cycle.dart';
import '../data/models.dart';
import '../data/pacing.dart';
import '../data/repo.dart';
import '../data/ui_flags.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/calendar_picker.dart';
import '../widgets/common.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/record_sheet.dart';

/// 明细页（首页）：按周期看每一笔。
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
            // 类型快捷筛选：留了开关（UiFlags.typeChips），后期看效果决定去留
            if (UiFlags.typeChips) const _TypeChips(),
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
                            text: '这一期还没有记账',
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

      out.add(
        Container(
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
                _TxnRow(txn: items[i]),
              ],
            ],
          ),
        ),
      );
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
                          _TxnRow(txn: hits[i], showDate: true),
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

/// 首页概览卡。
///
/// 浅灰底（`C.bg2`）+ 描边，和下方白底明细卡正好反过来：
/// 一个「压下去」的汇总区，配一组「浮上来」的记录卡。之前是纯黑 hero，
/// 在满屏黑白灰里太重，一进页面眼睛只能看到这块黑。
/// 概览卡的抬头：「本期支出 · 10.01 – 10.31」，整行可点，点了弹日历。
///
/// 日期从独立一行降成标签的注脚，是这张卡从「标题 + 数字」变成
/// 「一个数字 + 它的限定条件」的关键 —— 第一眼只剩金额。
class _PeriodHead extends StatelessWidget {
  const _PeriodHead({
    required this.from,
    required this.to,
    required this.onTap,
  });

  final String from;
  final String to;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            const Text(
              '本期支出',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: C.ink2,
                height: 1.2,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('·', style: TextStyle(fontSize: 13, color: C.ink4)),
            ),
            Flexible(
              child: Text(
                periodLabel(from, to),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: C.ink3,
                  letterSpacing: 0.1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    // 筛选态下这张卡整体换口径：周期换成结果摘要，数字改成筛选结果合计，
    // 预算进度条收起（预算按本期，跟跨期筛选没有关系）
    final filtering = s.filtering;
    final expense = filtering ? s.filteredExpenseCents : s.expenseCents;
    final income = filtering ? s.filteredIncomeCents : s.incomeCents;
    // 笔数也用聚合里的真实值：列表可能被截到 500 条，但「共几笔」不该跟着少算
    final count = filtering ? s.filterCount : s.txnCount;

    // 次要文字的灰度：浅底上不能再用「白字压暗」，那是深色卡的做法
    final dim = C.ink2;
    final faint = C.ink3;
    final budget = s.totalBudgetCents;

    // 预算节奏只在「按本期看」时算：跨期筛选的合计和一期预算不是一回事
    final pacing = !filtering && budget != null
        ? Pacing.ofRange(
            from: s.cycleFrom,
            to: s.cycleTo,
            totalCents: budget,
            usedCents: s.expenseCents,
          )
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.xs),
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.lg),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶上不再有一条独立的日期：日期只是「本期支出」的注脚，
          // 和标签排在同一行，层级自然低一档
          if (filtering) ...[
            const _FilterHead(),
            const SizedBox(height: S.md),
            Text('筛选支出', style: TextStyle(fontSize: 12, color: faint)),
          ] else
            _PeriodHead(
              from: s.cycleFrom,
              to: s.cycleTo,
              onTap: () => showCalendarAndGo(context),
            ),
          const SizedBox(height: 2),
          // 金额到六位数时用 FittedBox 收一点，保证永远单行
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Fmt.money(expense),
              maxLines: 1,
              style: T.hero.copyWith(fontSize: 34),
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _HeroStat(label: '收入', value: Fmt.money(income)),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: _HeroStat(
                  label: filtering ? '收支差' : '结余',
                  value: Fmt.money(income - expense, sign: true),
                ),
              ),
              const SizedBox(width: S.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '$count 笔',
                  style: TextStyle(fontSize: 12, color: faint),
                ),
              ),
            ],
          ),
          if (pacing != null) ...[
            const SizedBox(height: S.lg),
            const Divider(height: 1, color: C.line),
            const SizedBox(height: S.md),
            Row(
              children: [
                Text(
                  '本期预算 ${Fmt.money(s.expenseCents)} / '
                  '${Fmt.money(budget!)}',
                  style: TextStyle(fontSize: 12, color: dim),
                ),
                const Spacer(),
                Text(
                  s.overBudget
                      ? '超支 ${Fmt.money(s.overBudgetCents)}'
                      : '剩 ${Fmt.money(s.budgetLeftCents)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: s.overBudget ? C.over : C.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pacing.usedRatio.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: C.line2,
                valueColor: AlwaysStoppedAnimation(
                  s.overBudget ? C.over : C.ink,
                ),
              ),
            ),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text(
                  '还剩 ${pacing.remainDays} 天',
                  style: TextStyle(fontSize: 11.5, color: faint),
                ),
                const Spacer(),
                Text(
                  '每天可花 ${Fmt.money(pacing.canSpendPerDayCents)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: C.ink,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 概览卡里的一格小数字（收入 / 结余）
class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: C.ink3)),
        const SizedBox(height: 2),
        // 金额可能很长（收入五位数 + 结余带符号），等比缩一点保证单行
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: T.amountSm.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
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

/// 筛选态下替代周期条的那行：说清「这是筛选结果，共几笔，覆盖哪段时间」
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
                child: LineIcon(cat?.icon ?? 'more', size: 19, color: C.ink),
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
