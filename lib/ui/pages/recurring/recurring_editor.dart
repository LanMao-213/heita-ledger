import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/money.dart';
import '../../../core/period.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/chip_tabs.dart';
import '../../widgets/pickers/account_sheet.dart';
import '../../widgets/pickers/picker_wheels.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/toast.dart';

/// 新建 / 编辑周期账单规则。返回 `null` = 取消。
///
/// 两个控件是原版漏掉的（判据 5.3）：「每 N 个周期」与「结束日期」。
/// 它们必须**真的落库**，否则「每 2 个月交一次物业费」就表达不出来。
Future<Recurring?> showRecurringEditor(
  BuildContext context, {
  Recurring? rule,
  required int cycleStartDay,
}) {
  return showModalBottomSheet<Recurring>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _RecurringEditor(
      rule: rule,
      cycleStartDay: cycleStartDay,
    ),
  );
}

class _RecurringEditor extends StatefulWidget {
  const _RecurringEditor({this.rule, required this.cycleStartDay});

  final Recurring? rule;
  final int cycleStartDay;

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  late final TextEditingController _note = TextEditingController(
    text: widget.rule?.note ?? '',
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.rule == null
        ? ''
        : Fmt.money(widget.rule!.amountCents, trimZero: true),
  );
  late final TextEditingController _interval = TextEditingController(
    text: '${widget.rule?.interval ?? 1}',
  );
  late RecurFreq _freq = widget.rule?.freq ?? RecurFreq.monthly;
  late TxnType _type = widget.rule?.type ?? TxnType.expense;
  late LocalDate _next = widget.rule?.nextRunDate ?? LocalDate.today();
  late LocalDate? _end = widget.rule?.endDate;
  late int? _categoryId = widget.rule?.categoryId;
  late int? _accountId = widget.rule?.accountId;

  @override
  void dispose() {
    _note.dispose();
    _amount.dispose();
    _interval.dispose();
    super.dispose();
  }

  int get _intervalValue {
    final int? parsed = int.tryParse(_interval.text.trim());
    if (parsed == null || parsed < 1) return 1;
    if (parsed > 12) return 12;
    return parsed;
  }

  Future<void> _pickAccount() async {
    final int? picked = await showAccountSheet(
      context,
      accounts: CatalogScope.of(context).accounts,
      selectedId: _accountId,
      title: '从哪个账户',
    );
    if (picked == null || !mounted) return;
    setState(() => _accountId = picked);
  }

  Future<void> _pickCategory() async {
    final CategoryTree tree = CatalogScope.of(context).tree;
    final ({int topId, int? subId})? picked = await showCategoryPicker(
      context,
      tree: tree,
      type: _type,
      topId: _categoryId,
    );
    if (picked == null || !mounted) return;
    setState(() => _categoryId = picked.subId ?? picked.topId);
  }

  Future<void> _pickNext() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _next.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _next = LocalDate.fromDateTime(picked));
  }

  Future<void> _pickEnd() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (_end ?? _next).toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _end = LocalDate.fromDateTime(picked));
  }

  void _save() {
    final int amount = _amount.text.trim().isEmpty
        ? 0
        : Fmt.parseCents(_amount.text.trim());
    if (amount <= 0) {
      showToast(context, '金额要大于 0', error: true);
      return;
    }
    final Recurring base =
        widget.rule ??
        Recurring(
          ledgerId: 0,
          type: _type,
          amountCents: amount,
          nextRunDate: _next,
        );
    Navigator.of(context).pop(
      base.copyWith(
        type: _type,
        amountCents: amount,
        categoryId: _categoryId,
        accountId: _accountId,
        note: _note.text.trim(),
        freq: _freq,
        interval: _intervalValue,
        nextRunDate: _next,
        endDate: _end,
        enabled: widget.rule?.enabled ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return SheetFrame(
      title: widget.rule == null ? '新建周期账单' : '编辑周期账单',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('名称', style: Ts.micro.copyWith(color: pal.ink3)),
            const SizedBox(height: S.xs),
            _TextField(
              fieldKey: 'recurring-note',
              controller: _note,
              hint: '例如：房租',
            ),
            const SizedBox(height: S.md),
            Text('金额', style: Ts.micro.copyWith(color: pal.ink3)),
            const SizedBox(height: S.xs),
            _TextField(
              fieldKey: 'recurring-amount',
              controller: _amount,
              hint: '必填，要大于 0',
              number: true,
            ),
            const SizedBox(height: S.md),
            Text('类型', style: Ts.micro.copyWith(color: pal.ink3)),
            const SizedBox(height: S.xs),
            ChipTabs<TxnType>(
              padding: EdgeInsets.zero,
              items: const <ChipTabItem<TxnType>>[
                ChipTabItem<TxnType>(TxnType.expense, '支出'),
                ChipTabItem<TxnType>(TxnType.income, '收入'),
              ],
              selected: _type,
              onChanged: (TxnType t) => setState(() {
                _type = t;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: S.md),
            Text('频率', style: Ts.micro.copyWith(color: pal.ink3)),
            const SizedBox(height: S.xs),
            ChipTabs<RecurFreq>(
              padding: EdgeInsets.zero,
              items: <ChipTabItem<RecurFreq>>[
                for (final RecurFreq f in RecurFreq.values)
                  ChipTabItem<RecurFreq>(f, f.label),
              ],
              selected: _freq,
              onChanged: (RecurFreq f) => setState(() => _freq = f),
            ),
            const SizedBox(height: S.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('每几个周期', style: Ts.micro.copyWith(color: pal.ink3)),
                      const SizedBox(height: S.xs),
                      _TextField(
                        fieldKey: 'recurring-interval',
                        controller: _interval,
                        hint: '1',
                        number: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('下次日期', style: Ts.micro.copyWith(color: pal.ink3)),
                      const SizedBox(height: S.xs),
                      OutlinedButton(
                        key: const ValueKey<String>('recurring-next'),
                        onPressed: _pickNext,
                        child: Text(_next.iso),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '结束日期（可不填）',
                        style: Ts.micro.copyWith(color: pal.ink3),
                      ),
                      const SizedBox(height: S.xs),
                      OutlinedButton(
                        key: const ValueKey<String>('recurring-end'),
                        onPressed: _pickEnd,
                        child: Text(_end?.iso ?? '一直有效'),
                      ),
                    ],
                  ),
                ),
                if (_end != null)
                  IconButton(
                    key: const ValueKey<String>('recurring-end-clear'),
                    onPressed: () => setState(() => _end = null),
                    icon: Icon(Icons.close, size: 16, color: pal.ink3),
                  ),
              ],
            ),
            const SizedBox(height: S.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('recurring-category'),
                    onPressed: _pickCategory,
                    child: Text(
                      CatalogScope.watch(context).displayName(_categoryId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('recurring-account'),
                    onPressed: _pickAccount,
                    child: Text(
                      CatalogScope.watch(context).accountName(_accountId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.md),
            Text(
              '补记时按这笔本该发生的日期入账，归属期按账单日现算。',
              style: Ts.micro.copyWith(color: pal.ink4),
            ),
            const SizedBox(height: S.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey<String>('recurring-save'),
                onPressed: _save,
                child: const Text('保存'),
              ),
            ),
            const SizedBox(height: S.sm),
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.fieldKey,
    required this.controller,
    required this.hint,
    this.number = false,
  });

  final String fieldKey;
  final TextEditingController controller;
  final String hint;
  final bool number;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return TextField(
      key: ValueKey<String>(fieldKey),
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: Ts.body.copyWith(color: pal.ink),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: pal.surfaceAlt,
        hintText: hint,
        hintStyle: Ts.body2.copyWith(color: pal.ink4),
        border: OutlineInputBorder(
          borderRadius: R.rMd,
          borderSide: BorderSide(color: pal.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: R.rMd,
          borderSide: BorderSide(color: pal.line),
        ),
      ),
    );
  }
}

/// 周期账单下次到期日距今天几天（入口行副行用）。
int daysUntilDue(Recurring rule, {LocalDate? today}) {
  final LocalDate now = today ?? LocalDate.today();
  final int diff = rule.nextRunDate.diffDays(now);
  return diff < 0 ? 0 : diff;
}

/// 归属期（给测试一个不依赖 UI 的锚点）。
LocalDate periodStartOfRule(Recurring rule, int cycleStartDay) =>
    Period.periodStartOf(rule.nextRunDate, cycleStartDay);
