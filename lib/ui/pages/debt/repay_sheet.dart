import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/money.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/repo.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pickers/account_sheet.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/toast.dart';

/// 记还款的返回值。
typedef RepayInput = ({int cents, int? accountId, LocalDate date});

/// 记账还款面板。
///
/// 三条默认值（判据 4.7）：金额 = 剩余、账户 = **这笔当初的账户**、日期 = 今天。
/// 校验与数据层同一条规则：`0 < amount <= remaining`；面板拦一次，
/// `Repo.repay` 再抛一次 `ArgumentError`（脚本/以后的手动补记也要挡住）。
Future<RepayInput?> showRepaySheet(
  BuildContext context, {
  required Debt debt,
  required int remainingCents,
  LocalDate? today,
}) {
  return showModalBottomSheet<RepayInput>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _RepaySheet(
      debt: debt,
      remainingCents: remainingCents,
      today: today ?? LocalDate.today(),
    ),
  );
}

class _RepaySheet extends StatefulWidget {
  const _RepaySheet({
    required this.debt,
    required this.remainingCents,
    required this.today,
  });

  final Debt debt;
  final int remainingCents;
  final LocalDate today;

  @override
  State<_RepaySheet> createState() => _RepaySheetState();
}

class _RepaySheetState extends State<_RepaySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: Fmt.money(widget.remainingCents, trimZero: true),
  );
  late int? _accountId = widget.debt.accountId;
  late LocalDate _date = widget.today;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _parsed {
    final String raw = _amount.text.trim();
    if (raw.isEmpty) return null;
    return Fmt.parseCents(raw);
  }

  /// 面板层的拦截理由（`null` = 可以提交）。
  String? get _errorText {
    final int? cents = _parsed;
    if (cents == null || cents <= 0) return '金额要大于 0';
    if (cents > widget.remainingCents) {
      return '不能超过剩余 ${Fmt.money(widget.remainingCents)}';
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final int? picked = await showAccountSheet(
      context,
      accounts: CatalogScope.of(context).accounts,
      selectedId: _accountId,
      title: '用哪个账户',
    );
    if (picked == null || !mounted) return;
    setState(() => _accountId = picked);
  }

  void _submit() {
    final int? cents = _parsed;
    if (cents == null || _errorText != null) return;
    Navigator.of(context).pop((
      cents: cents,
      accountId: _accountId,
      date: _date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String who = widget.debt.counterparty.trim().isEmpty
        ? '未填对方'
        : widget.debt.counterparty.trim();
    final bool receivable = widget.debt.isReceivable;

    return SheetFrame(
      title: receivable ? '收回一笔' : '还一笔',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$who · 剩余 ${Fmt.money(widget.remainingCents)}',
              key: const ValueKey<String>('repay-remaining'),
              style: Ts.body2.copyWith(color: pal.ink2),
            ),
            const SizedBox(height: S.md),
            TextField(
              key: const ValueKey<String>('repay-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (String _) => setState(() {}),
              style: Ts.body.copyWith(color: pal.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.surfaceAlt,
                hintText: '金额',
                hintStyle: Ts.body2.copyWith(color: pal.ink4),
                prefixText: '¥ ',
                prefixStyle: Ts.body.copyWith(color: pal.ink3),
                errorText: _amount.text.trim().isEmpty ? null : _errorText,
                border: OutlineInputBorder(
                  borderRadius: R.rMd,
                  borderSide: BorderSide(color: pal.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: R.rMd,
                  borderSide: BorderSide(color: pal.line),
                ),
              ),
            ),
            const SizedBox(height: S.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('repay-account'),
                    onPressed: _pickAccount,
                    child: Text(
                      CatalogScope.watch(context).accountName(_accountId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: S.sm),
                OutlinedButton(
                  key: const ValueKey<String>('repay-date'),
                  onPressed: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _date.toDateTime(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null || !mounted) return;
                    setState(() => _date = LocalDate.fromDateTime(picked));
                  },
                  child: Text('${_date.month}-${_date.day}'),
                ),
              ],
            ),
            const SizedBox(height: S.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey<String>('repay-submit'),
                onPressed: _errorText == null ? _submit : null,
                child: const Text('确认'),
              ),
            ),
            const SizedBox(height: S.sm),
            Text(
              '记满剩余金额会自动把这笔往来标记为已结清。',
              style: Ts.micro.copyWith(color: pal.ink4),
            ),
          ],
        ),
      ),
    );
  }
}

/// 真的去记一笔还款：落库 + 重查 + toast。
///
/// 抽成函数是为了让「往来详情 / 人详情」两个入口共用同一段错误处理。
Future<bool> submitRepay(
  BuildContext context, {
  required Debt debt,
  required RepayInput input,
  required int cycleStartDay,
}) async {
  try {
    await Repo.repayDebt(
      target: debt,
      amountCents: input.cents,
      cycleStartDay: cycleStartDay,
      date: input.date,
    );
    if (!context.mounted) return true;
    showToast(context, '已记一笔还款');
    return true;
  } on ArgumentError catch (e) {
    if (context.mounted) {
      showToast(context, '${e.message}', error: true);
    }
    return false;
  } catch (_) {
    if (context.mounted) showToast(context, '保存失败，请重试', error: true);
    return false;
  }
}

/// 删这笔往来的确认文案：**必须写明会连带删掉几笔流水并回滚余额**。
String deleteDebtConfirmBody({required int txnCount}) =>
    '会一并删除 $txnCount 笔相关流水并回滚余额（本金与还款都算在内）。\n'
    '这一步不能撤销，账目会回到「从没借过这笔钱」的状态。';

/// 二次确认 + 删除。
Future<bool> confirmDeleteDebt(
  BuildContext context, {
  required Debt debt,
  required int txnCount,
}) async {
  final bool ok = await showConfirmDialog(
    context,
    title: '删除这笔往来？',
    body: deleteDebtConfirmBody(txnCount: txnCount),
    confirmText: '删除',
    destructive: true,
  );
  if (!ok) return false;
  await Repo.debt.deleteDebt(debt.id!);
  return true;
}
