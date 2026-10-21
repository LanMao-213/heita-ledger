import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/money.dart';
import '../../../data/models/models.dart';
import '../../../data/services/debt_grouping.dart';
import '../../../data/services/summary_service.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/list_tile_row.dart';
import '../../widgets/section_header.dart';

/// 「未填对方」这一组的标题。空名字**不丢弃**，归到这一桶里。
const String kUnnamedCounterparty = '未填对方';

/// 一个人那一行副行怎么写。
///
/// 三种情况分开说清楚：
/// - 两边都有（`isMixed`）：把两个数都写出来，净额才解释得通；
/// - 一笔而已：写笔数与应还日；
/// - 逾期：一句「逾期 N 天」，颜色交给调用方标红。
String counterpartySubtitle(
  PersonDebts person, {
  required RepaidIndex index,
  LocalDate? today,
}) {
  final int? overdue = person.overdueDays(today: today);
  if (overdue != null) return '逾期 $overdue 天 · ${person.count} 笔';
  if (person.isMixed(index)) {
    return '借出 ${Fmt.money(person.receivableCents(index))} · '
        '借入 ${Fmt.money(person.payableCents(index))}';
  }
  final LocalDate? due = person.nearestDue;
  final String dueText = due == null
      ? '未约定应还日'
      : '应还 ${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
  return '${person.count} 笔 · $dueText';
}

/// 按人汇总的一行（往来页 / 人详情页共用）。
class CounterpartyRow extends StatelessWidget {
  const CounterpartyRow({
    super.key,
    required this.person,
    required this.index,
    required this.onTap,
    this.today,
  });

  final PersonDebts person;
  final RepaidIndex index;
  final VoidCallback onTap;
  final LocalDate? today;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final bool overdue = person.isOverdue(today: today);
    final int net = person.netCents(index);
    return ListTileRow(
      key: ValueKey<String>('cp-${person.name}'),
      leadingIcon: person.name == kUnnamedCounterparty
          ? Icons.help_outline
          : Icons.person_outline,
      title: Text(
        person.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Ts.body.copyWith(color: pal.ink),
      ),
      subtitle: Text(
        counterpartySubtitle(person, index: index, today: today),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Ts.caption.copyWith(color: overdue ? pal.over : pal.ink3),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          AmountText(
            cents: net,
            yuan: true,
            tier: AmountTier.small,
            color: net >= 0 ? pal.ink : pal.ink2,
          ),
          Text(
            net >= 0 ? '净欠我' : '我净欠',
            style: Ts.micro.copyWith(color: pal.ink4),
          ),
        ],
      ),
      showDivider: true,
      onTap: onTap,
    );
  }
}

/// 已结清的一笔（整体 dimmed，金额位写「已结清」）。
class ClosedDebtRow extends StatelessWidget {
  const ClosedDebtRow({super.key, required this.debt, required this.onTap});

  final Debt debt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String who = debt.counterparty.trim().isEmpty
        ? kUnnamedCounterparty
        : debt.counterparty.trim();
    return Opacity(
      opacity: 0.55,
      child: ListTileRow(
        key: ValueKey<String>('debt-closed-${debt.id}'),
        leadingIcon: debt.isReceivable
            ? Icons.call_made_outlined
            : Icons.call_received_outlined,
        title: Text(
          '$who · ${debt.isReceivable ? '借出' : '借入'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Ts.body2.copyWith(color: pal.ink2),
        ),
        subtitle: Text(
          '${debt.date.iso} · ${Fmt.money(debt.amountCents)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Ts.caption.copyWith(color: pal.ink4),
        ),
        trailing: Text(
          '已结清',
          key: ValueKey<String>('debt-closed-badge-${debt.id}'),
          style: Ts.micro.copyWith(color: pal.ink4),
        ),
        showDivider: true,
        onTap: onTap,
      ),
    );
  }
}

/// 往来摘要卡：**只取未结清**的剩余（已结清的钱不构成「欠」）。
class DebtSummaryCard extends StatelessWidget {
  const DebtSummaryCard({
    super.key,
    required this.debts,
    required this.index,
  });

  final List<Debt> debts;
  final RepaidIndex index;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final int receivable = SummaryService.receivable(debts, index);
    final int payable = SummaryService.payable(debts, index);
    return AppCard(
      shadow: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('应收（别人欠我）', style: Ts.micro.copyWith(color: pal.ink4)),
                const SizedBox(height: 2),
                AmountText(
                  key: const ValueKey<String>('debts-summary-receivable'),
                  cents: receivable,
                  yuan: true,
                  tier: AmountTier.heroSm,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('应付（我欠别人）', style: Ts.micro.copyWith(color: pal.ink4)),
                const SizedBox(height: 2),
                AmountText(
                  key: const ValueKey<String>('debts-summary-payable'),
                  cents: payable,
                  yuan: true,
                  tier: AmountTier.heroSm,
                  color: pal.ink2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 往来页的分段标题（未结清 / 已结清）。
class DebtsSectionHeader extends StatelessWidget {
  const DebtsSectionHeader({
    super.key,
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(title: '$title · $count');
  }
}
