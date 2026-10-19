import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';

/// 往来页：借出（应收）/ 借入（应付）的完整台账。
///
/// 入口在「计划」页顶部的摘要卡。这里只做三件事：看清谁欠谁多少、
/// 什么时候该还、点进去记一笔还款。
class DebtsPage extends StatelessWidget {
  const DebtsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // 和分类管理/模板页同一个返回箭头，不加这个系统会给一个平台默认的
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
        title: const Text('往来', style: T.section),
        centerTitle: false,
      ),
      body: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          final open = s.debts.where((d) => !d.isClosed).toList();
          final closed = s.debts.where((d) => d.isClosed).toList();
          final receivable = open
              .where((d) => d.direction.isReceivable)
              .fold<int>(0, (a, d) => a + d.remainingCents);
          final payable = open
              .where((d) => !d.direction.isReceivable)
              .fold<int>(0, (a, d) => a + d.remainingCents);

          return ListView(
            padding: const EdgeInsets.only(bottom: S.xxl),
            children: [
              _SummaryCard(
                receivable: receivable,
                payable: payable,
                openCount: open.length,
              ),
              if (open.isEmpty && closed.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: S.xl),
                  child: EmptyHint(
                    icon: 'coin',
                    text: '还没有往来',
                    hint: '记一笔时选「借出」或「借入」，这里会按人汇总谁欠谁多少',
                  ),
                ),
              if (open.isNotEmpty) ...[
                const SectionTitle('未结清'),
                for (final d in open) _DebtRow(debt: d),
              ],
              if (closed.isNotEmpty) ...[
                const SectionTitle('已结清'),
                for (final d in closed) _DebtRow(debt: d, dimmed: true),
              ],
              const SizedBox(height: S.lg),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.receivable,
    required this.payable,
    required this.openCount,
  });

  final int receivable;
  final int payable;
  final int openCount;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          Expanded(
            child: _Figure(label: '应收（别人欠我）', cents: receivable),
          ),
          Container(width: 1, height: 34, color: C.line),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: S.md),
              child: _Figure(label: '应付（我欠别人）', cents: payable),
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.cents});

  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.caption),
        const SizedBox(height: 4),
        Text(
          Fmt.money(cents),
          style: T.amount.copyWith(fontSize: 22, color: C.ink),
        ),
      ],
    );
  }
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.debt, this.dimmed = false});

  final Debt debt;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final overdue = debt.overdueDays;
    final due = debt.dueDate;
    final sub = <String>[
      if (overdue != null)
        '逾期 $overdue 天'
      else if (due != null)
        '应还 ${Fmt.md(due)}'
      else
        '未约定还款日',
      if (debt.note.isNotEmpty) debt.note,
    ].join(' · ');

    return GestureDetector(
      onTap: () => showDebtDetail(context, debt),
      child: Container(
        margin: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.sm),
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: C.line),
        ),
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
                  debt.direction.isMoneyOut ? 'upload' : 'download',
                  size: 19,
                  color: dimmed ? C.ink3 : C.ink,
                ),
              ),
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${debt.counterparty} · ${debt.direction.label}',
                    style: T.body.copyWith(
                      color: dimmed ? C.ink3 : C.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    style: T.caption.copyWith(
                      color: overdue != null ? C.over : C.ink3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: S.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  dimmed ? '已结清' : Fmt.money(debt.remainingCents),
                  style: T.amount.copyWith(
                    fontSize: 16,
                    color: dimmed ? C.ink3 : C.ink,
                  ),
                ),
                if (!dimmed && debt.repaidCents > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '已还 ${Fmt.money(debt.repaidCents)}',
                    style: T.caption.copyWith(color: C.ink4),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 往来详情：本金、已还、剩余、应还日，底部两个动作。
Future<void> showDebtDetail(BuildContext context, Debt debt) {
  final s = Store.i;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.bg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
    ),
    builder: (ctx) => AnimatedBuilder(
      animation: s,
      builder: (ctx, _) {
        // 面板开着时可能刚记完还款，重新取一次最新状态
        final d = s.debtOf(debt.id) ?? debt;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${d.counterparty} · ${d.direction.label}',
                      style: T.section,
                    ),
                    const Spacer(),
                    if (d.isClosed)
                      Text('已结清', style: T.caption.copyWith(color: C.ink3)),
                  ],
                ),
                const SizedBox(height: S.md),
                _kv('本金', Fmt.money(d.amountCents)),
                _kv('已还', Fmt.money(d.repaidCents)),
                _kv('剩余', Fmt.money(d.remainingCents)),
                _kv(
                  '应还日',
                  d.dueDate == null
                      ? '未约定'
                      : '${Fmt.md(d.dueDate!)}'
                            '${d.overdueDays != null ? '（逾期 ${d.overdueDays} 天）' : ''}',
                ),
                if (d.note.isNotEmpty) _kv('备注', d.note),
                const SizedBox(height: S.lg),
                if (!d.isClosed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: C.ink,
                        foregroundColor: C.bg,
                        minimumSize: const Size(0, 46),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        showRepaySheet(context, d);
                      },
                      child: const Text('记一笔还款'),
                    ),
                  ),
                const SizedBox(height: S.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: C.ink2,
                      side: const BorderSide(color: C.line2),
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () async {
                      await Repo.setDebtClosed(d.id, closed: !d.isClosed);
                      await s.afterTxnChange();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(d.isClosed ? '撤销结清' : '标记已结清'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _kv(String k, String v) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 64, child: Text(k, style: T.caption)),
      Expanded(child: Text(v, style: T.body)),
    ],
  ),
);

/// 记还款：金额（默认剩余）、账户、日期。
Future<void> showRepaySheet(BuildContext context, Debt debt) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.bg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
    ),
    builder: (_) => _RepaySheet(debt: debt),
  );
}

class _RepaySheet extends StatefulWidget {
  const _RepaySheet({required this.debt});

  final Debt debt;

  @override
  State<_RepaySheet> createState() => _RepaySheetState();
}

class _RepaySheetState extends State<_RepaySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: _yuan(widget.debt.remainingCents),
  );
  late int? _accountId = Store.i.accounts.isEmpty
      ? null
      : Store.i.accounts.first.id;
  late String _date = Fmt.today();
  bool _saving = false;
  String? _error;

  /// 分 → 输入框里的元，去掉多余的 .00
  static String _yuan(int cents) {
    final s = (cents / 100).toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final yuan = double.tryParse(_amount.text.trim());
    if (yuan == null || yuan <= 0) {
      setState(() => _error = '请输入大于 0 的金额');
      return;
    }
    final cents = (yuan * 100).round();
    if (cents > widget.debt.remainingCents) {
      setState(() => _error = '不能超过剩余 ${Fmt.money(widget.debt.remainingCents)}');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = '请选择账户');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Repo.repayDebt(
        debt: widget.debt,
        amountCents: cents,
        accountId: _accountId!,
        date: _date,
      );
      await Store.i.afterTxnChange();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
      locale: const Locale('zh', 'CN'),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = Fmt.date(picked));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: S.lg,
        right: S.lg,
        top: S.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + S.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('记一笔还款 · ${widget.debt.counterparty}', style: T.section),
          const SizedBox(height: 4),
          Text(
            '剩余 ${Fmt.money(widget.debt.remainingCents)}',
            style: T.caption,
          ),
          const SizedBox(height: S.md),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: T.amount.copyWith(fontSize: 26),
            decoration: const InputDecoration(
              prefixText: '¥ ',
              isDense: true,
              border: UnderlineInputBorder(),
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.ink2,
                    side: const BorderSide(color: C.line2),
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: _pickDate,
                  child: Text(Fmt.friendly(_date)),
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.ink2,
                    side: const BorderSide(color: C.line2),
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () async {
                    final accounts = Store.i.accounts;
                    if (accounts.isEmpty) return;
                    final idx = accounts.indexWhere((a) => a.id == _accountId);
                    final next = accounts[(idx + 1) % accounts.length];
                    setState(() => _accountId = next.id);
                  },
                  child: Text(
                    Store.i.accountOf(_accountId)?.name ?? '选账户',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: S.sm),
            Text(_error!, style: T.caption.copyWith(color: C.over)),
          ],
          const SizedBox(height: S.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: C.ink,
                foregroundColor: C.bg,
                minimumSize: const Size(0, 48),
              ),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '确认'),
            ),
          ),
        ],
      ),
    );
  }
}
