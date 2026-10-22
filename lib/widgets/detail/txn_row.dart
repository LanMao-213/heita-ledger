import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/haptics.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../pages/debts_page.dart';
import '../../store.dart';
import '../common.dart';
import '../record_sheet.dart';

/// 单条交易。点按进入编辑，长按删除。
class TxnRow extends StatelessWidget {
  const TxnRow({super.key, required this.txn, this.showDate = false});

  final Txn txn;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final cat = s.categoryOf(txn.categoryId);
    // 借出/借入：这笔属于某笔往来，标题、图标、金额颜色都不走「分类 + 收支」那套
    final debt = s.debtOf(txn.debtId);
    // 子分类要带上一级，否则明细里只看到「正餐」，不知道它属于餐饮
    final parent = s.parentOf(cat);
    final acc = s.accountOf(txn.accountId);

    // 标题**永远**是分类名：两级分类之后，分类才是结构信息，备注只是补充。
    // 旧版本把备注当标题（因为名目就存在备注里），那笔账的「是什么」和
    // 「补充说明」被混成了一栏，统计上也就查不到「午饭一共花了多少」。
    // 借贷流水没有分类，标题换成「借出 · 张三」——一眼看出这是借钱不是花钱。
    final title = debt != null
        ? '${debt.direction.label} · ${debt.counterparty}'
        : (cat?.name ?? '未分类');
    final subParts = <String>[
      // 借贷最要紧的是「什么时候该还」，排在副行第一位
      if (debt != null && debt.dueDate != null) '应还 ${Fmt.md(debt.dueDate!)}',
      if (debt == null && parent != null) parent.name,
      // 出发地/目的地、对象、名称 —— 记了就得看得见，否则录完就再也找不到
      if (txn.detailSummary.isNotEmpty) txn.detailSummary,
      if (txn.note.isNotEmpty) txn.note,
      if (showDate) Fmt.md(txn.date),
      if (acc != null) acc.name,
    ];

    return FadeSlideIn(
      // 记一笔/删一笔之后整段列表是重建的：没有这一下，新增和删除都是
      // 「凭空出现 / 凭空消失」，看不出是哪一行变了。
      child: InkWell(
        // 借贷流水不能当普通支出编辑：改金额会和债务记录对不上。
        // 点它直接看往来详情，记还款也在那一页。
        onTap: debt != null
            ? () => showDebtDetail(context, debt)
            : () => showRecordSheet(context, editing: txn),
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
                    // 借出=钱出去、借入=钱进来
                    debt != null
                        ? (debt.direction.isMoneyOut ? 'upload' : 'download')
                        : (cat?.icon ?? 'more'),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: T.body.copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 「周期账单」是它自己记的，不是用户点的。1.4.4 起补记会
                        // 在回到前台时就发生，列表里凭空多出几笔不标一下，
                        // 第一反应会是「我没记过这笔」。
                        if (debt == null && txn.recurringId != null) ...[
                          const SizedBox(width: 6),
                          const _AutoTag(),
                        ],
                      ],
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
                  // 借贷用中性灰：它既不是消费也不是收入，用支出红会让
                  // 「这个月花了多少」在视觉上被一笔借款顶掉
                  color: debt != null
                      ? C.ink3
                      : (txn.type.isIncome ? C.ink2 : C.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔记录？', style: T.section),
        // 与列表同一口径：标题是分类名，备注只作补充。
        // 旧版拿备注当标题，出现的是「删除这笔记录？午饭」，看不出删的是哪一类。
        content: Text(
          '${Store.i.categoryOf(txn.categoryId)?.name ?? '未分类'}'
          ' · ${Fmt.money(txn.signedCents, sign: true)}'
          '${txn.note.isEmpty ? '' : '\n${txn.note}'}',
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
    Haptics.warn();
    if (context.mounted) showToast(context, '已删除');
  }
}

/// 「周期」小标签：这笔是周期账单自动生成的，不是用户自己点的。
///
/// 刻意做得很轻 —— 它只是「说明来源」的辅助信息，不该抢分类名和金额的注意力，
/// 所以用最浅的文字色 + 和正文对齐的基线，而不是做成醒目的 chip。
class _AutoTag extends StatelessWidget {
  const _AutoTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '周期',
        style: TextStyle(fontSize: 9.5, height: 1.35, color: C.ink3),
      ),
    );
  }
}
