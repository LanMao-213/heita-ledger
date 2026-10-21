import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/services/debt_grouping.dart';
import '../../../stores/catalog_store.dart';
import '../../../stores/plan_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/list_tile_row.dart';
import '../../widgets/section_header.dart';
import 'counterparty_list.dart';
import 'debt_detail_sheet.dart';

/// 往来页（从计划页的往来摘要卡 / 我的页进来）。
///
/// 三块：摘要卡（只算未结清）→ 按人汇总的未结清 → 已结清一笔一行。
/// 「按人」是这一页的核心：用户问的是「谁欠我多少」，不是「第 7 笔记了多少」。
class DebtsPage extends StatefulWidget {
  const DebtsPage({super.key});

  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends State<DebtsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final PlanStore plan = PlanScope.of(context);
    await plan.reload();
    if (!mounted) return;
    await CatalogScope.of(context).reloadMoney();
  }

  Future<void> _openGroup(PersonDebts person) async {
    final single = person.single;
    if (single != null) {
      await _openDetail(single);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) => _CounterpartyPage(personName: person.name),
      ),
    );
    await _refresh();
  }

  Future<void> _openDetail(Debt debt) async {
    await showDebtDetailSheet(context, debtId: debt.id!);
    // 面板里的还款 / 结清 / 删除都可能改数据：不问「变没变」，直接重查
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final PlanStore plan = PlanScope.watch(context);
    final List<Debt> open = plan.debts;
    final List<Debt> closed = plan.closedDebts;
    final RepaidIndex index = plan.repaidIndex;
    final bool allEmpty = open.isEmpty && closed.isEmpty;
    final List<PersonDebts> groups = groupDebtsByCounterparty(
      open,
      repaid: index,
    );

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        elevation: 0,
        title: Text('往来', style: Ts.section.copyWith(color: pal.ink)),
        iconTheme: IconThemeData(color: pal.ink),
      ),
      body: allEmpty
          ? const EmptyState(
              key: ValueKey<String>('debts-empty'),
              icon: Icons.swap_horiz,
              title: '还没有往来',
              hint: '记一笔时选「借出 / 借入」，这里就会显示谁欠你、你欠谁。',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: S.xxxl),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, 0),
                  child: DebtSummaryCard(debts: open, index: index),
                ),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(S.page, S.lg, S.page, 0),
                    child: Text(
                      '没有未结清的往来。',
                      key: const ValueKey<String>('debts-open-empty'),
                      style: Ts.caption.copyWith(color: pal.ink3),
                    ),
                  )
                else ...<Widget>[
                  DebtsSectionHeader(title: '未结清', count: groups.length),
                  for (final PersonDebts p in groups)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.page),
                      child: CounterpartyRow(
                        person: p,
                        index: index,
                        onTap: () => _openGroup(p),
                      ),
                    ),
                ],
                if (closed.isNotEmpty) ...<Widget>[
                  DebtsSectionHeader(title: '已结清', count: closed.length),
                  for (final Debt d in closed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.page),
                      child: ClosedDebtRow(debt: d, onTap: () => _openDetail(d)),
                    ),
                ],
              ],
            ),
    );
  }
}

/// 某个人的往来列表（多笔时才走这一层；单笔直接进详情）。
class _CounterpartyPage extends StatefulWidget {
  const _CounterpartyPage({required this.personName});

  final String personName;

  @override
  State<_CounterpartyPage> createState() => _CounterpartyPageState();
}

class _CounterpartyPageState extends State<_CounterpartyPage> {
  Future<void> _open(Debt debt) async {
    // 先抓住两个 Store：跨 await 之后再摸 context 是要挨骂的
    final PlanStore plan = PlanScope.of(context);
    final CatalogStore catalog = CatalogScope.of(context);
    await showDebtDetailSheet(context, debtId: debt.id!);
    if (!mounted) return;
    await plan.reload();
    await catalog.reloadMoney();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final PlanStore plan = PlanScope.watch(context);
    final List<Debt> mine = <Debt>[
      for (final Debt d in plan.debts)
        if (!d.isClosed &&
            (d.counterparty.trim().isEmpty
                ? kUnnamedCounterparty
                : d.counterparty.trim()) ==
            widget.personName)
          d,
    ];

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        elevation: 0,
        title: Text(
          widget.personName,
          key: const ValueKey<String>('debt-person-title'),
          style: Ts.section.copyWith(color: pal.ink),
        ),
        iconTheme: IconThemeData(color: pal.ink),
      ),
      body: ListView(
        children: <Widget>[
          SectionHeader(title: '未结清 · ${mine.length}'),
          for (final Debt d in mine)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.page),
              child: ListTileRow(
                key: ValueKey<String>('debt-row-${d.id}'),
                leadingIcon: d.isReceivable
                    ? Icons.call_made_outlined
                    : Icons.call_received_outlined,
                title: Text(
                  '${d.isReceivable ? '借出' : '借入'} · ${d.date.iso}',
                  style: Ts.body2.copyWith(color: pal.ink),
                ),
                subtitle: Text(
                  d.dueDate == null
                      ? '未约定应还日'
                      : '应还 ${d.dueDate!.iso}',
                  style: Ts.caption.copyWith(color: pal.ink3),
                ),
                trailing: Text(
                  '¥${(d.amountCents / 100).toStringAsFixed(2)}',
                  style: Ts.amountSm.copyWith(color: pal.ink),
                ),
                showDivider: true,
                onTap: () => _open(d),
              ),
            ),
        ],
      ),
    );
  }
}

/// 供外部（计划页 / 我的页）打开往来页。
Future<void> openDebtsPage(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (BuildContext _) => const DebtsPage()),
);

/// 「往来」入口的副行文案（页面外也要说清「谁欠我 / 我欠谁」）。
String debtsEntrySubtitle({required int receivable, required int payable}) {
  if (receivable == 0 && payable == 0) return '还没有往来';
  return '应收 ${(receivable / 100).toStringAsFixed(2)} · '
      '应付 ${(payable / 100).toStringAsFixed(2)}';
}

/// 逾期共几笔（入口行上给一个红点数字）。
int overdueCount(List<Debt> debts, {LocalDate? today}) => debts
    .where((Debt d) => d.overdueDays(today: today) != null)
    .length;
