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
    Haptics.warn();
    if (context.mounted) showToast(context, '已删除');
  }
}
