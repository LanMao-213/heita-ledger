import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/failure.dart';
import '../../../core/local_date.dart';
import '../../../core/period.dart';
import '../../../core/scope.dart';
import '../../../data/db/seeds.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/repo.dart';
import '../../../data/services/calc_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/chip_tabs.dart';
import '../../widgets/pickers/account_sheet.dart';
import '../../widgets/pickers/picker_wheels.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/toast.dart';
import 'category_row.dart';
import 'debt_fields.dart';
import 'detail_block.dart';
import 'record_keypad.dart';

/// 四种记账模式。**借贷不是新的 `TxnType`**：落库仍是 `expense`/`income`
/// + 非空 `debt_id`（口径 3.5）。做成独立枚举要改遍明细分组、筛选、Excel、
/// 统计、周期归集、备份 7 处，漏一处就有一个数字错。
enum RecordMode {
  expense('支出'),
  income('收入'),
  transfer('转账'),
  lend('借出'),
  borrow('借入');

  const RecordMode(this.label);

  final String label;

  bool get isDebt => this == RecordMode.lend || this == RecordMode.borrow;

  bool get isTransfer => this == RecordMode.transfer;

  TxnType get txnType => switch (this) {
    RecordMode.expense || RecordMode.lend => TxnType.expense,
    RecordMode.income || RecordMode.borrow => TxnType.income,
    RecordMode.transfer => TxnType.transfer,
  };
}

/// 保存成功后的回执。外层拿它搬游标 + 拼 toast。
class RecordOutcome {
  const RecordOutcome({required this.periodStart, required this.label});

  final LocalDate periodStart;

  /// `10.01 至 10.31`
  final String label;
}

/// 打开记一笔面板（新建或编辑）。返回 null = 用户取消。
Future<RecordOutcome?> showRecordSheet(
  BuildContext context, {
  Txn? editing,
}) {
  return showModalBottomSheet<RecordOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext ctx) => RecordSheet(editing: editing),
  );
}

/// 记一笔 / 改一笔的编排层。
class RecordSheet extends StatefulWidget {
  const RecordSheet({super.key, this.editing});

  /// 非空 = 编辑已有流水。
  final Txn? editing;

  @override
  State<RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<RecordSheet> {
  late RecordMode _mode;
  final CalcService _calc = CalcService();
  final FocusNode _noteFocus = FocusNode();

  int? _topId;
  int? _subId;
  Map<TxnField, String> _details = <TxnField, String>{};
  String _note = '';
  late LocalDate _date;
  int? _accountId;
  int? _toAccountId;
  String _counterparty = '';
  LocalDate? _dueDate;
  bool _countInBudget = false;
  bool _liftOn = false;

  /// 用户手动拨过抬期开关 → 不再被白名单默认值覆盖。
  bool _liftManual = false;

  bool _detailExpanded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Txn? e = widget.editing;
    _mode = e == null ? RecordMode.expense : _modeOf(e);
    _date = e?.date ?? LocalDate.today();
    _note = e?.note ?? '';
    _topId = e?.categoryId;
    _details = <TxnField, String>{
      for (final TxnField f in TxnField.values) f: e?.detailFields[f] ?? '',
    };
    _accountId = e?.accountId;
    _toAccountId = e?.toAccountId;
    if (e != null) {
      _calc.expr = e.amountCents == 0
          ? ''
          : (e.amountCents.abs() / 100).toStringAsFixed(
              e.amountCents.abs() % 100 == 0 ? 0 : 2,
            );
    }
    // 编辑已有记录时，抬期状态由「落库的期 ≠ 按规则算的期」反推
    _noteFocus.addListener(() => setState(() {}));
  }

  RecordMode _modeOf(Txn t) {
    if (t.type.isTransfer) return RecordMode.transfer;
    if (t.debtId != null) {
      return t.type.isIncome ? RecordMode.borrow : RecordMode.lend;
    }
    return t.type.isIncome ? RecordMode.income : RecordMode.expense;
  }

  /// 当前子分类名（决定详情字段与抬期白名单）。
  String? get _subName => _tree.byId(_subId)?.name;

  String? get _topName => _tree.byId(_topId)?.name;

  int get _cycleStartDay => BookScope.of(context).cycleStartDay;

  CategoryTree get _tree => CatalogScope.watch(context).tree;

  bool get _isIncome => _mode == RecordMode.income;

  /// 这笔是否「落在同月账单日之前」—— 只有这时抬期开关才出现。
  bool get _liftEligible => Period.liftable(_date, _cycleStartDay);

  /// 白名单默认值（收入 + 工资/奖金/提成 + 早于同月账单日）。
  bool get _liftDefault => Period.shouldLift(
    isIncome: _isIncome,
    categoryName: _topName,
    date: _date,
    startDay: _cycleStartDay,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Txn? e = widget.editing;
    if (e == null) {
      if (!_liftManual) _liftOn = _liftEligible && _liftDefault;
      return;
    }
    // 编辑：periodStart 与「不抬期算出来的期」不同 → 当初是抬过的
    if (!_liftManual) {
      final LocalDate plain = Period.periodStartOf(e.date, _cycleStartDay);
      _liftOn = e.periodStart != null && e.periodStart != plain;
      _liftManual = true;
    }
    // 子分类：编辑时 category_id 可能直接是子分类
    if (_topId != null && _subId == null) {
      final Category? c = _tree.byId(_topId);
      if (c != null && c.isChild) {
        _subId = c.id;
        _topId = c.parentId;
      }
    }
    if (_details.isEmpty) {
      _details = <TxnField, String>{
        for (final TxnField f in TxnField.values) f: e.detailFields[f] ?? '',
      };
    }
  }

  @override
  void dispose() {
    _noteFocus.dispose();
    super.dispose();
  }

  void _onModeChanged(RecordMode mode) {
    setState(() {
      _mode = mode;
      _liftManual = false;
      if (mode.isDebt) {
        // 借贷没有分类与详情（数据层会把 count_in_budget 对借出强改 0）
        _topId = null;
        _subId = null;
        _details = <TxnField, String>{};
      }
    });
  }

  void _onCategoryChanged(int? topId, int? subId) {
    setState(() {
      _topId = topId;
      _subId = subId;
      // 换分类 → 只保留新分类认的字段（同组不丢，换到不认的全清）
      _details = detailsAfterCategoryChange(_subName, _details);
      if (!_liftManual) _liftOn = _liftEligible && _liftDefault;
    });
  }

  Future<void> _openCategorySheet() async {
    final CategoryTree tree = _tree;
    final TxnType type = _mode.txnType;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        int? top = _topId;
        int? sub = _subId;
        return SheetFrame(
          title: '选择分类',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CategoryWheels(
                tree: tree,
                type: type,
                initialTopId: top,
                initialSubId: sub,
                onChanged: (int? t, int? s) {
                  top = t;
                  sub = s;
                },
              ),
              const SizedBox(height: S.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('wheel-confirm'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _onCategoryChanged(top, sub);
                  },
                  child: const Text('确定'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAccount({required bool to}) async {
    final int? id = await showAccountSheet(
      context,
      accounts: CatalogScope.of(context).accounts,
      selectedId: to ? _toAccountId : _accountId,
      title: to ? '选择转入账户' : '选择账户',
    );
    if (id == null) return;
    setState(() {
      if (to) {
        _toAccountId = id;
      } else {
        _accountId = id;
      }
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _date = LocalDate.fromDateTime(picked);
      if (!_liftManual) _liftOn = _liftEligible && _liftDefault;
    });
  }

  int? get _cents => _calc.cents;

  /// 能否保存：表达式必须合法；借贷还要求金额 > 0 且对方非空。
  bool get canSave {
    final int? cents = _cents;
    if (cents == null) return false;
    if (_mode.isDebt) {
      return cents > 0 && _counterparty.trim().isNotEmpty;
    }
    if (_mode.isTransfer) {
      return _accountId != null && _toAccountId != null;
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving || !canSave) return;
    setState(() => _saving = true);
    final int cents = _cents!;
    final int startDay = _cycleStartDay;
    final LocalDate periodStart = Period.periodStartOf(
      _date,
      startDay,
      liftToNext: _liftOn,
    );
    try {
      final Txn? editing = widget.editing;
      if (_mode.isDebt) {
        await Repo.createDebt(
          Debt(
            ledgerId: BookScope.of(context).ledgerId,
            direction: _mode == RecordMode.borrow
                ? DebtDirection.in_
                : DebtDirection.out,
            counterparty: _counterparty.trim(),
            amountCents: cents,
            accountId: _accountId,
            date: _date,
            dueDate: _dueDate,
            countInBudget: _mode == RecordMode.borrow && _countInBudget,
            note: _note,
            createdAt: DateTime.now(),
          ),
          cycleStartDay: startDay,
        );
      } else {
        final Txn draft = Txn(
          id: editing?.id,
          ledgerId: BookScope.of(context).ledgerId,
          type: _mode.txnType,
          amountCents: cents,
          categoryId: _mode.isTransfer ? null : (_subId ?? _topId),
          accountId: _accountId,
          toAccountId: _mode.isTransfer ? _toAccountId : null,
          date: _date,
          periodStart: periodStart,
          note: _note,
          placeFrom: _details[TxnField.from],
          placeTo: _details[TxnField.to],
          person: _details[TxnField.person],
          subject: _details[TxnField.subject],
          templateId: editing?.templateId,
          recurringId: editing?.recurringId,
          createdAt: editing?.createdAt ?? DateTime.now(),
        );
        if (editing == null) {
          final Txn saved = await Repo.saveTxn(draft, cycleStartDay: startDay);
          if (!mounted) return;
          Navigator.of(context).pop(
            RecordOutcome(
              periodStart: saved.periodStart ?? periodStart,
              label: periodLabel(Period.cycleRange(saved.periodStart ?? periodStart, startDay)),
            ),
          );
          return;
        }
        await Repo.updateTxn(editing, draft, cycleStartDay: startDay);
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        RecordOutcome(
          periodStart: periodStart,
          label: periodLabel(Period.cycleRange(periodStart, startDay)),
        ),
      );
    } catch (error) {
      // 保存失败：面板不关、按钮复位。**不许**吞掉异常当成功。
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, '保存失败：${detailOf(error)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final double bottomInset = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final bool noteFocused = _noteFocus.hasFocus;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.92,
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: noteFocused ? bottomInset : 0),
        child: Column(
          children: <Widget>[
            const SizedBox(height: S.sm),
            Row(
              children: <Widget>[
                const SizedBox(width: S.md),
                Expanded(
                  child: Text(
                    widget.editing == null ? '记一笔' : '改一笔',
                    style: Ts.section.copyWith(color: pal.ink),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('record-close'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close, size: 20, color: pal.ink3),
                ),
              ],
            ),
            // 模式：支出 / 收入 / 转账 / 借出 / 借入
            ChipTabs<RecordMode>(
              items: <ChipTabItem<RecordMode>>[
                for (final RecordMode m in RecordMode.values)
                  ChipTabItem<RecordMode>(m, m.label),
              ],
              selected: _mode,
              onChanged: _onModeChanged,
            ),
            const SizedBox(height: S.sm),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: S.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _AmountBar(
                      display: _calc.display,
                      empty: _calc.isEmpty,
                      mode: _mode,
                    ),
                    const SizedBox(height: S.sm),
                    if (_mode.isDebt)
                      DebtFields(
                        borrow: _mode == RecordMode.borrow,
                        counterparty: _counterparty,
                        dueDate: _dueDate,
                        countInBudget: _countInBudget,
                        onCounterpartyChanged: (String v) =>
                            setState(() => _counterparty = v),
                        onDueDateChanged: (LocalDate? d) =>
                            setState(() => _dueDate = d),
                        onCountInBudgetChanged: (bool v) =>
                            setState(() => _countInBudget = v),
                      )
                    else ...<Widget>[
                      CategoryRow(
                        tree: _tree,
                        topId: _topId,
                        subId: _subId,
                        note: _note,
                        detailSummary: <String>[
                          for (final TxnField f in TxnField.values)
                            if ((_details[f] ?? '').isNotEmpty)
                              '${f.label} ${_details[f]}',
                        ],
                        onTap: _openCategorySheet,
                      ),
                      const SizedBox(height: S.sm),
                      DetailBlock(
                        subName: _subName,
                        values: _details,
                        folded: !_detailExpanded && kFoldedSubs.contains(_subName),
                        onToggleFold: () =>
                            setState(() => _detailExpanded = !_detailExpanded),
                        onChanged: (Map<TxnField, String> v) =>
                            setState(() => _details = v),
                      ),
                    ],
                    const SizedBox(height: S.sm),
                    _NoteField(
                      initial: _note,
                      focusNode: _noteFocus,
                      onChanged: (String v) => _note = v,
                    ),
                    const SizedBox(height: S.sm),
                    _MetaRow(
                      dateLabel: dateChipLabel(_date),
                      onDate: _pickDate,
                      accountLabel: CatalogScope.watch(context).accountName(_accountId),
                      onAccount: () => _pickAccount(to: false),
                      showToAccount: _mode.isTransfer,
                      toAccountLabel: _toAccountId == null
                          ? '转入账户'
                          : CatalogScope.watch(context).accountName(_toAccountId),
                      onToAccount: () => _pickAccount(to: true),
                    ),
                    if (_liftEligible)
                      // 面板底部是有背景色的 DecoratedBox，ListTile 的墨水得落在
                      // 它自己的透明 Material 上，否则会撞「ink splashes 可能看不见」。
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile(
                          key: const ValueKey<String>('record-lift'),
                          value: _liftOn,
                          onChanged: (bool v) => setState(() {
                            _liftOn = v;
                            _liftManual = true;
                          }),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            '这笔算下一期',
                            style: Ts.body2.copyWith(color: pal.ink),
                          ),
                          subtitle: Text(
                            '这笔钱是拿来支撑下一期生活的',
                            style: Ts.caption.copyWith(color: pal.ink3),
                          ),
                        ),
                      ),
                    const SizedBox(height: S.xl),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: Dur.size,
              curve: Ease.enter,
              child: noteFocused
                  ? const SizedBox(width: double.infinity)
                  : RecordKeypad(
                      expanded: _detailExpanded ||
                          DetailBlock(
                                subName: _subName,
                                values: _details,
                                onChanged: (Map<TxnField, String> _) {},
                              ).activeFields.isNotEmpty,
                      canConfirm: canSave,
                      onKey: (String k) => setState(() {
                        _calc.tap(k);
                        _liftOn = _liftManual
                            ? _liftOn
                            : (_liftEligible && _liftDefault);
                      }),
                      onConfirm: _saving ? () {} : _save,
                    ),
            ),
            const SizedBox(height: S.sm),
          ],
        ),
      ),
    );
  }
}

class _AmountBar extends StatelessWidget {
  const _AmountBar({
    required this.display,
    required this.empty,
    required this.mode,
  });

  final String display;
  final bool empty;
  final RecordMode mode;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      decoration: BoxDecoration(
        color: pal.surfaceSunk,
        borderRadius: R.rMd,
        border: Border.all(color: pal.line),
      ),
      child: Row(
        children: <Widget>[
          Text(
            mode.isDebt ? '本金' : '金额',
            style: Ts.caption.copyWith(color: pal.ink3),
          ),
          const SizedBox(width: S.sm),
          Expanded(
            child: Text(
              empty ? '0' : display,
              key: const ValueKey<String>('record-amount'),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ts.hero.copyWith(
                color: empty ? pal.ink4 : pal.ink,
                fontSize: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteField extends StatefulWidget {
  const _NoteField({
    required this.initial,
    required this.focusNode,
    required this.onChanged,
  });

  final String initial;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return TextField(
      key: const ValueKey<String>('record-note'),
      controller: _controller,
      focusNode: widget.focusNode,
      maxLines: 1,
      style: Ts.body.copyWith(color: pal.ink),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: pal.surfaceAlt,
        hintText: '备注（可不填）',
        hintStyle: Ts.body2.copyWith(color: pal.ink4),
        prefixIcon: Icon(Icons.edit_note, size: 18, color: pal.ink3),
        border: OutlineInputBorder(
          borderRadius: R.rMd,
          borderSide: BorderSide(color: pal.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: R.rMd,
          borderSide: BorderSide(color: pal.line),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.dateLabel,
    required this.onDate,
    required this.accountLabel,
    required this.onAccount,
    required this.showToAccount,
    required this.toAccountLabel,
    required this.onToAccount,
  });

  final String dateLabel;
  final VoidCallback onDate;
  final String accountLabel;
  final VoidCallback onAccount;
  final bool showToAccount;
  final String toAccountLabel;
  final VoidCallback onToAccount;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    Widget chip(String label, Key key, VoidCallback onTap) => Expanded(
      child: OutlinedButton(
        key: key,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, S.touch),
          side: BorderSide(color: pal.line),
          shape: const RoundedRectangleBorder(borderRadius: R.rMd),
          padding: const EdgeInsets.symmetric(horizontal: S.sm),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Ts.body2.copyWith(color: pal.ink2),
        ),
      ),
    );

    return Row(
      children: <Widget>[
        chip(dateLabel, const ValueKey<String>('record-date'), onDate),
        const SizedBox(width: S.sm),
        chip(accountLabel, const ValueKey<String>('record-account'), onAccount),
        if (showToAccount) ...<Widget>[
          const SizedBox(width: S.sm),
          chip(
            toAccountLabel,
            const ValueKey<String>('record-to-account'),
            onToAccount,
          ),
        ],
      ],
    );
  }
}
