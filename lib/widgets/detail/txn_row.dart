import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/haptics.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
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
    // 子分类要带上一级，否则明细里只看到「正餐」，不知道它属于餐饮
    final parent = s.parentOf(cat);
    final acc = s.accountOf(txn.accountId);

    // 标题**永远**是分类名：两级分类之后，分类才是结构信息，备注只是补充。
    // 旧版本把备注当标题（因为名目就存在备注里），那笔账的「是什么」和
    // 「补充说明」被混成了一栏，统计上也就查不到「午饭一共花了多少」。
    final title = cat?.name ?? '未分类';
    final subParts = <String>[
      if (parent != null) parent.name,
      // 出发地/目的地、对象、名称 —— 记了就得看得见，否则录完就再也找不到
      if (txn.detailSummary.isNotEmpty) txn.detailSummary,
      if (txn.note.isNotEmpty) txn.note,
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
