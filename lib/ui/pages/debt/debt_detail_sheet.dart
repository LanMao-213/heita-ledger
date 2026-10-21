import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/repo.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/toast.dart';
import 'repay_sheet.dart';

/// 往来详情（只读 + 三个动作：还款 / 结清 / 删除）。
///
/// 为什么是面板而不是新页面：用户是「点一行看看这笔欠多久了」，
/// 看完就要接着记还款，弹面板不用来回导航。
///
/// 返回值：`true` = 数据变过（调用方要重查）。
Future<bool> showDebtDetailSheet(
  BuildContext context, {
  required int debtId,
  LocalDate? today,
}) async {
  final bool? changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) =>
        _DebtDetailSheet(debtId: debtId, today: today ?? LocalDate.today()),
  );
  return changed ?? false;
}

class _DebtDetailSheet extends StatefulWidget {
  const _DebtDetailSheet({required this.debtId, required this.today});

  final int debtId;
  final LocalDate today;

  @override
  State<_DebtDetailSheet> createState() => _DebtDetailSheetState();
}

class _DebtDetailSheetState extends State<_DebtDetailSheet> {
  Debt? _debt;
  RepaidIndex _index = RepaidIndex.empty;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Debt? d = await Repo.debt.byId(widget.debtId);
    if (!mounted || d == null) return;
    final RepaidIndex index = RepaidIndex.fromTxns(
      await Repo.txn.byDebt(widget.debtId),
    );
    if (!mounted) return;
    setState(() {
      _debt = d;
      _index = index;
    });
  }

  Future<void> _repay() async {
    final Debt debt = _debt!;
    final int remaining = debt.remainingCents(_index);
    final RepayInput? input = await showRepaySheet(
      context,
      debt: debt,
      remainingCents: remaining,
      today: widget.today,
    );
    if (input == null || !mounted) return;
    final int cycleStartDay = BookScope.of(context).cycleStartDay;
    setState(() => _busy = true);
    final bool ok = await submitRepay(
      context,
      debt: debt,
      input: input,
      cycleStartDay: cycleStartDay,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _changed = _changed || ok;
    });
    if (ok) await _load();
  }

  /// 标记结清 / 撤销结清：**只改 `closed_at`**，不动流水与余额。
  Future<void> _toggleClosed() async {
    final Debt debt = _debt!;
    final bool close = !debt.isClosed;
    setState(() => _busy = true);
    await Repo.debt.setClosed(debt.id!, close);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _changed = true;
    });
    showToast(context, close ? '已标记结清' : '已撤销结清');
    await _load();
  }

  Future<void> _delete() async {
    final Debt debt = _debt!;
    final int count = (await Repo.txn.byDebt(debt.id!)).length;
    if (!mounted) return;
    final bool ok = await showConfirmDialog(
      context,
      title: '删除这笔往来？',
      body: deleteDebtConfirmBody(txnCount: count),
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await Repo.deleteDebt(debt.id!);
    if (!mounted) return;
    Navigator.of(context).pop(true);
    showToast(context, '已删除往来');
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final Debt? debt = _debt;
    if (debt == null) {
      return const SheetFrame(
        title: '往来详情',
        child: SizedBox(height: 120, child: Center(child: Text('载入中…'))),
      );
    }

    final int repaid = _index.repaidForId(
      debt.id!,
      receivable: debt.isReceivable,
    );
    final int remaining = debt.remainingCents(_index);
    final int? overdue = debt.overdueDays(today: widget.today);
    final String who = debt.counterparty.trim().isEmpty
        ? '未填对方'
        : debt.counterparty.trim();

    return SheetFrame(
      title: '往来详情',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$who · ${debt.isReceivable ? '借出' : '借入'}',
              key: const ValueKey<String>('debt-detail-title'),
              style: Ts.section.copyWith(color: pal.ink),
            ),
            const SizedBox(height: S.md),
            _KvRow(
              label: '本金',
              child: AmountText(
                key: const ValueKey<String>('debt-kv-principal'),
                cents: debt.amountCents,
                yuan: true,
                tier: AmountTier.small,
              ),
            ),
            _KvRow(
              label: debt.isReceivable ? '已收回' : '已还',
              child: AmountText(
                key: const ValueKey<String>('debt-kv-repaid'),
                cents: repaid,
                yuan: true,
                tier: AmountTier.small,
                color: pal.ink2,
              ),
            ),
            _KvRow(
              label: '剩余',
              child: AmountText(
                key: const ValueKey<String>('debt-kv-remaining'),
                cents: remaining,
                yuan: true,
                tier: AmountTier.small,
                color: debt.isClosed ? pal.ink3 : pal.ink,
              ),
            ),
            _KvRow(
              label: '应还日',
              child: Text(
                debt.dueDate == null
                    ? '未约定'
                    : '${debt.dueDate!.iso}'
                          '${overdue == null ? '' : ' · 逾期 $overdue 天'}',
                key: const ValueKey<String>('debt-kv-due'),
                style: Ts.body2.copyWith(
                  color: overdue == null ? pal.ink2 : pal.over,
                ),
              ),
            ),
            if (debt.note.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: S.sm),
              Text(
                debt.note.trim(),
                key: const ValueKey<String>('debt-detail-note'),
                style: Ts.caption.copyWith(color: pal.ink3),
              ),
            ],
            if (debt.isClosed) ...<Widget>[
              const SizedBox(height: S.sm),
              Text(
                '已结清',
                key: const ValueKey<String>('debt-detail-closed'),
                style: Ts.caption.copyWith(color: pal.ink3),
              ),
            ],
            const SizedBox(height: S.lg),
            if (!debt.isClosed)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('debt-repay'),
                  onPressed: _busy ? null : _repay,
                  child: const Text('记一笔还款'),
                ),
              ),
            const SizedBox(height: S.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey<String>('debt-toggle-closed'),
                onPressed: _busy ? null : _toggleClosed,
                child: Text(debt.isClosed ? '撤销结清' : '标记已结清'),
              ),
            ),
            const SizedBox(height: S.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const ValueKey<String>('debt-delete'),
                onPressed: _busy ? null : _delete,
                child: Text(
                  '删除这笔往来',
                  style: Ts.caption.copyWith(color: pal.over),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(label, style: Ts.caption.copyWith(color: pal.ink3)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
