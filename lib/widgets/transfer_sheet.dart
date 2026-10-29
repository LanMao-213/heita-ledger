import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import 'common.dart';
import 'menu.dart';

/// 打开「账户转账」面板。
///
/// ★ 转账**不是**记一笔的第五档。记一笔面板的四档（支出 / 收入 / 借出 / 借入）
///   都在回答「这一笔算收入还是支出」，而转账两者都不是：钱只是从一个口袋
///   挪到另一个口袋，统计里一分钱都不该出现（`sumBySide` 里转账两侧都不参与）。
///   给它一个独立入口，`_RecordMode` 那套「收支 + 借贷」的分支就不用再扩一档。
Future<void> showTransferSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const TransferSheet(),
  );
}

/// 账户转账面板：从哪个账户 → 到哪个账户、金额、日期、备注。
///
/// 形态照 `debts_page.dart` 的还款面板来（`SheetShell` + 金额输入 +
/// 日期/账户两颗按钮 + 底部确认），两处的「填一笔钱」在观感上要是同一个东西。
class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key});

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  late int? _fromId = _initialFromId();
  late int? _toId = _initialToId();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _date = Fmt.today();
  bool _saving = false;
  String? _error;

  /// 转出账户的初值：优先用「默认支出账户」（用户九成的钱从那儿出），
  /// 没有才落到列表第一个。
  int? _initialFromId() {
    final s = Store.i;
    final preferred = s.defaultExpenseAccountId;
    if (preferred != null && s.accountOf(preferred) != null) return preferred;
    return s.accounts.isEmpty ? null : s.accounts.first.id;
  }

  /// 转入账户的初值：第一个**不是**转出账户的账户 —— 默认两端相同的话，
  /// 用户一进来看到的就是一个必然报错的表单。
  int? _initialToId() {
    for (final a in Store.i.accounts) {
      if (a.id != _fromId) return a.id;
    }
    return Store.i.accounts.isEmpty ? null : Store.i.accounts.first.id;
  }

  @override
  void initState() {
    super.initState();
    // 金额一改，下面那句「转出后余额」的提示要跟着变
    _amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amount
      ..removeListener(_onAmountChanged)
      ..dispose();
    _note.dispose();
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  /// 解析出来的金额（分）。空串 / 非法 / 非正数统一按 0 处理，保存时拦。
  int get _cents {
    final v = Fmt.parseCents(_amount.text);
    return v > 0 ? v : 0;
  }

  /// 转出之后的来源账户余额（负数 = 透支）。
  ///
  /// **不拦**：活期账户真的能透支（信用卡、绑定的余额宝自动垫付），
  /// 拦住等于告诉用户「你的账不是这样」——账本应该记录事实，不是纠正事实。
  /// 但余额不足这件事必须说出来，所以下面给一句提示，让用户自己判断。
  int? get _fromBalanceAfter {
    final from = Store.i.accountOf(_fromId);
    if (from == null || _cents <= 0) return null;
    return from.balanceCents - _cents;
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

  Future<void> _pickAccount({required bool from}) async {
    final accounts = Store.i.accounts;
    if (accounts.isEmpty) return;
    final current = from ? _fromId : _toId;
    final picked = await showPickSheet<int>(
      context: context,
      title: from ? '从哪个账户转出' : '转到哪个账户',
      subtitle: '余额会分别增减，收支统计不受影响',
      options: [
        for (final a in accounts)
          PickOption(
            value: a.id,
            icon: a.icon,
            title: a.name,
            subtitle: Fmt.yuan(a.balanceCents),
          ),
      ],
      current: current,
    );
    if (picked == null || !mounted) return;
    // ⚠️ 刻意**不**在两端撞车时自动把另一端挪开。
    // 那样看起来更"聪明"，实际上是在用户没看的地方改掉另一个字段：他选了
    // 「转入 = 现金」，结果「转出」自己从微信跳走了，而他以为只是改了一端。
    // 撞车就在保存时明确报错（见 `_save`），让用户自己决定改哪一端。
    setState(() {
      if (from) {
        _fromId = picked;
      } else {
        _toId = picked;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final from = _fromId;
    final to = _toId;
    if (from == null || to == null) {
      setState(() => _error = '请选择转出与转入账户');
      return;
    }
    if (from == to) {
      setState(() => _error = '转出和转入不能是同一个账户');
      return;
    }
    final cents = _cents;
    if (cents <= 0) {
      setState(() => _error = '请输入大于 0 的金额');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final s = Store.i;
    try {
      // 走 Store.addTxn（内部就是 `Repo.insertTxn`）：它同时刷新余额、明细
      // 与统计，并把视角搬到这笔所在的期 —— 只写库不刷新的话，用户会看到
      // 「转账成功了，余额却没变」。
      await s.addTxn(
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.transfer,
          amountCents: cents,
          date: _date,
          accountId: from,
          toAccountId: to,
          note: _note.text.trim(),
        ),
      );
      if (!mounted) return;
      final fromName = s.accountOf(from)?.name ?? '账户';
      final toName = s.accountOf(to)?.name ?? '账户';
      // 先弹提示再关面板：SnackBar 挂在根 ScaffoldMessenger 上，
      // 面板关掉之后它仍然在（`showToast` 的实现见 common.dart）。
      showToast(context, '已转账 ${Fmt.money(cents)}：$fromName → $toName');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final fromAcc = s.accountOf(_fromId);
    final toAcc = s.accountOf(_toId);
    final after = _fromBalanceAfter;

    return SheetShell(
      title: '转账',
      subtitle: '账户之间挪钱，不计入收支',
      child: Padding(
        padding: EdgeInsets.only(
          left: S.lg,
          right: S.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + S.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              // 与还款面板同一档 26：正在输入的数字要比列表里的大一号
              style: T.amount.copyWith(fontSize: 26),
              decoration: const InputDecoration(
                prefixText: '¥ ',
                isDense: true,
                border: UnderlineInputBorder(),
              ),
            ),
            // 余额不足只提示、不拦：见 `_fromBalanceAfter` 的注释
            if (after != null && after < 0) ...[
              const SizedBox(height: S.xs),
              Text(
                '转出后「${fromAcc?.name ?? '转出账户'}」余额为 '
                '${Fmt.yuan(after)}（允许透支）',
                style: T.caption.copyWith(color: C.ink2),
              ),
            ],
            const SizedBox(height: S.md),
            Row(
              children: [
                Expanded(
                  child: _SlotButton(
                    key: const ValueKey('transfer_from'),
                    label: fromAcc?.name ?? '选转出账户',
                    onTap: () => _pickAccount(from: true),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.sm),
                  child: LineIcon('arrow_right', size: 18, color: C.ink3),
                ),
                Expanded(
                  child: _SlotButton(
                    key: const ValueKey('transfer_to'),
                    label: toAcc?.name ?? '选转入账户',
                    onTap: () => _pickAccount(from: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: C.ink2,
                      side: BorderSide(color: C.line2),
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _pickDate,
                    child: Text(Fmt.friendly(_date)),
                  ),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: TextField(
                    controller: _note,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: '备注（可空）',
                      isDense: true,
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
                child: Text(_saving ? '保存中…' : '确认转账'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 转账两端的账户按钮：一行小标签 + 账户名，等宽并排。
///
/// 单独抽出来是因为两端要长得**一模一样**（只差标签），手写两遍最容易
/// 出现「左边 44 高、右边 46 高」这种对不齐。
class _SlotButton extends StatelessWidget {
  const _SlotButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        side: BorderSide(color: C.line2),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: S.md),
      ),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          LineIcon('chevron_down', size: 16, color: C.ink3),
        ],
      ),
    );
  }
}
