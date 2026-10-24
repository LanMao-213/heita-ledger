import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/debt_grouping.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/hairline.dart';
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
          icon: LineIcon('arrow_left', semanticLabel: '返回', size: 22, color: C.ink),
        ),
        title: Text('往来', style: T.section),
        centerTitle: false,
      ),
      body: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          final open = s.debts.where((d) => !d.isClosed).toList();
          final closed = s.debts.where((d) => d.isClosed).toList();
          // 未结清按**人**汇总：主业是「谁欠我多少」，单笔只是背后的来龙去脉
          final groups = groupDebtsByCounterparty(open);
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
                const SectionTitle('未结清（按人）'),
                for (final g in groups) _PersonRow(group: g),
              ],
              if (closed.isNotEmpty) ...[
                const SectionTitle('已结清'),
                // 已结清的钱不再构成「欠」，一笔一行就够，不按人合并
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
          Container(
            width: hairlineOf(context),
            height: 34,
            color: C.line,
          ),
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
          style: T.amount,
        ),
      ],
    );
  }
}

/// 一个人的未结清往来：姓名 + 净额。
///
/// 只有一笔时点进去就是那笔的详情；多笔时先看这个人的明细 ——
/// 「他到底欠我几笔、哪笔快到期」是多笔场景下真正要回答的问题。
class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.group});

  final PersonDebts group;

  @override
  Widget build(BuildContext context) {
    final net = group.netCents;
    final overdue = group.overdueDays;
    final due = group.nearestDue;

    final sub = <String>[
      if (group.count > 1)
        '${group.count} 笔'
      else
        group.debts.first.direction.label,
      // 同一个人既借又还时，净额怎么来的要说清楚，否则「他欠我 3000」
      // 会和记忆里的「5000 和 2000」对不上
      if (group.isMixed)
        '借出 ${Fmt.money(group.receivableCents)} / 借入 ${Fmt.money(group.payableCents)}',
      if (overdue != null)
        '逾期 $overdue 天'
      else if (due != null)
        '应还 ${Fmt.md(due)}'
      else
        '未约定还款日',
    ].join(' · ');

    final (String amount, String label) = switch (net) {
      > 0 => (Fmt.money(net), '净应收'),
      < 0 => (Fmt.money(-net), '净应付'),
      _ => ('两清', group.count > 1 ? '借还相抵' : '已无欠款'),
    };

    final icon = group.isMixed
        ? 'coin'
        : (group.debts.first.direction.isMoneyOut ? 'upload' : 'download');

    return GestureDetector(
      onTap: () {
        final one = group.single;
        if (one != null) {
          showDebtDetail(context, one);
        } else {
          showPersonDebtsSheet(context, group);
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.sm),
        // 左右归一到 16：原来 12，卡边（margin 16）+ 12 = 28，比别处的内容少 4
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
        decoration: ShapeDecoration(
          // 卡片面：纯白，比纸白底亮一档（见 C.cardBg）
          // 边界交给 E.low 的柔投影 —— 1px 描边在 1.29:1 下几乎看不见，
          // 只是把整屏切成「被细线划开的白板」（见 C.line 注释）
          color: C.cardBg,
          shadows: E.low,
          shape: Shape.squircle(R.card),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: C.bg2,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Center(
                child: LineIcon(icon, size: 19, color: C.ink),
              ),
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: T.body.copyWith(
                      color: C.ink,
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
                  amount,
                  style: T.amount,
                ),
                const SizedBox(height: 2),
                Text(label, style: T.caption.copyWith(color: C.ink3)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 某个人的全部未结清往来。点其中一笔进那笔的详情（在那儿记还款）。
Future<void> showPersonDebtsSheet(BuildContext context, PersonDebts group) {
  final s = Store.i;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.bg,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
    ),
    builder: (ctx) => AnimatedBuilder(
      animation: s,
      builder: (ctx, _) {
        // 面板开着时可能刚还完一笔，重新算一遍，避免显示已结清的旧数据
        final fresh = [
          for (final d in s.debts)
            if (!d.isClosed &&
                (d.counterparty.trim().isEmpty
                    ? '未填对方'
                    : d.counterparty.trim()) ==
                group.name)
              d,
        ];
        if (fresh.isEmpty) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(S.xl),
              child: Text(
                '${group.name}的往来都结清了',
                style: T.body.copyWith(color: C.ink2),
              ),
            ),
          );
        }
        final g = PersonDebts(group.name, fresh);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
                child: Row(
                  children: [
                    Text(group.name, style: T.section),
                    const Spacer(),
                    Text(
                      g.isMixed
                          ? '借出 ${Fmt.money(g.receivableCents)} · 借入 ${Fmt.money(g.payableCents)}'
                          : '${g.netCents > 0 ? '应收' : '应付'} ${Fmt.money(g.netCents.abs())}',
                      style: T.caption.copyWith(color: C.ink3),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: S.xs, bottom: S.md),
                  children: [for (final d in g.debts) _DebtRow(debt: d)],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
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
        // 左右归一到 16：原来 12，卡边（margin 16）+ 12 = 28，比别处的内容少 4
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
        decoration: ShapeDecoration(
          // 卡片面：纯白，比纸白底亮一档（见 C.cardBg）
          color: C.cardBg,
          shadows: E.low,
          shape: Shape.squircle(R.card),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: C.bg2,
                borderRadius: BorderRadius.circular(R.sm),
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
                    color: dimmed ? C.ink3 : C.ink,
                  ),
                ),
                if (!dimmed && debt.repaidCents > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '已还 ${Fmt.money(debt.repaidCents)}',
                    style: T.caption.copyWith(color: C.ink3),
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
                      side: BorderSide(color: C.line2),
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
                const SizedBox(height: S.sm),
                // 记错一笔往来之后唯一的退路。次要动作，压在最下面、
                // 只用红字表达危险，不加红底 —— 它不是这一屏的主按钮。
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: C.over,
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () {
                      _confirmDeleteDebt(context, ctx, d);
                    },
                    child: const Text('删除这笔往来'),
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

/// 删除一笔往来：先查清会连带删掉几笔流水 → 二次确认 → 删 → 关面板 → 提示。
///
/// 文案里的笔数是**当场 `COUNT(*)` 出来的**，不是按「本金 + 已还笔数」估的：
/// `_DeleteDebt` 的实际行为是「把 `debt_id` 命中的流水全部反向回滚余额后删掉，
/// 再删 debt 行」，提示里写几笔，用户点下去就必须删几笔 —— 这一步不可撤销。
Future<void> _confirmDeleteDebt(
  BuildContext pageContext,
  BuildContext sheetContext,
  Debt d,
) async {
  final txnCount = await Repo.debtTxnCount(d.id);
  if (!sheetContext.mounted) return;

  final ok = await showDialog<bool>(
    context: sheetContext,
    builder: (ctx) => AlertDialog(
      title: Text(
        '删除「${d.counterparty} · ${d.direction.label}」？',
        style: T.section,
      ),
      content: Text(
        '${Fmt.money(d.amountCents)} 这笔往来会一起删掉'
        '${txnCount > 0 ? '，还有挂在上面的 $txnCount 笔流水'
              '${txnCount > 1 ? '（本金和各次还款）' : '（本金）'}，'
              '账户余额跟着回滚' : ''}。'
        '\n删掉之后没法撤销。',
        style: T.body2,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('取消', style: TextStyle(color: C.ink2)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('删除', style: TextStyle(color: C.over)),
        ),
      ],
    ),
  );
  if (ok != true) return;

  await Repo.deleteDebt(d.id);
  await Store.i.afterTxnChange();
  if (sheetContext.mounted) Navigator.pop(sheetContext);
  if (pageContext.mounted) showToast(pageContext, '已删除');
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
  // 默认账户优先取这笔借贷当时用的账户（钱从哪儿出去就回哪儿），
  // 没有才退到列表第一个。不然从微信借出去的钱，还款默认记到现金上，
  // 两个账户的余额就都不对了 —— 而且看不出来，因为总额是对的。
  late int? _accountId = _defaultAccountId();

  int? _defaultAccountId() {
    final accounts = Store.i.accounts;
    if (accounts.isEmpty) return null;
    final same = accounts.where((a) => a.id == widget.debt.accountId);
    return same.isNotEmpty ? same.first.id : accounts.first.id;
  }
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
            // 刻意用 26（不是金额档）：这是**正在输入**的数字，比列表里的
            // 金额大一档才看得出「我在填这个」。别当成漂移收掉。
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
                    side: BorderSide(color: C.line2),
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
                    side: BorderSide(color: C.line2),
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
