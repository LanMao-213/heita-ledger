import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/money.dart';
import '../../../core/period.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/txn_query.dart';
import '../../../data/repo/txn_repo.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/chip_tabs.dart';
import '../../widgets/sheet_frame.dart';

/// 时间快捷档。**按真实日期筛**（不是 `period_start`）—— 用户说「今年」时
/// 指的是日历上的今年，不是「落在今年的期」。
enum TimePreset {
  any('不限'),
  current('本期'),
  last('上期'),
  last3('近 3 期'),
  thisYear('今年'),
  custom('自定义');

  const TimePreset(this.label);

  final String label;
}

/// 把快捷档算成真实日期区间。`any` 返回 null（不带时间条件）。
///
/// 基准一律是**今天所在的期**，与正在浏览的期无关（口径 3.7：时间档以今天为基准）。
({LocalDate from, LocalDate to})? rangeOfPreset(
  TimePreset preset, {
  required int cycleStartDay,
  LocalDate? today,
  LocalDate? customFrom,
  LocalDate? customTo,
}) {
  final LocalDate now = today ?? LocalDate.today();
  final Period current = Period.cycleRange(now, cycleStartDay);
  switch (preset) {
    case TimePreset.any:
      return null;
    case TimePreset.current:
      return (from: current.from, to: current.to);
    case TimePreset.last:
      final Period last = Period.shiftCycle(current, -1, cycleStartDay);
      return (from: last.from, to: last.to);
    case TimePreset.last3:
      final Period three = Period.shiftCycle(current, -2, cycleStartDay);
      return (from: three.from, to: current.to);
    case TimePreset.thisYear:
      return (from: LocalDate(now.year, 1, 1), to: LocalDate(now.year, 12, 31));
    case TimePreset.custom:
      if (customFrom == null || customTo == null) return null;
      return (from: customFrom, to: customTo);
  }
}

/// 筛选面板。`null` = 取消（**不改条件**）；非 null = 应用。
Future<TxnQuery?> showFilterSheet(
  BuildContext context, {
  required TxnQuery initial,
  required int cycleStartDay,
}) {
  return showModalBottomSheet<TxnQuery>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => FilterSheet(
      initial: initial,
      cycleStartDay: cycleStartDay,
    ),
  );
}

/// 筛选面板本体：类型 / 分类两级 / 账户 / 金额区间 / 时间段。
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.initial,
    required this.cycleStartDay,
  });

  final TxnQuery initial;
  final int cycleStartDay;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late TxnType? _type = widget.initial.type;
  late int? _categoryId = widget.initial.categoryId;
  late int? _accountId = widget.initial.accountId;
  late TimePreset _preset = _presetOf(widget.initial);
  LocalDate? _customFrom;
  LocalDate? _customTo;
  late final TextEditingController _min = TextEditingController(
    text: widget.initial.minCents == null
        ? ''
        : Fmt.money(widget.initial.minCents!, trimZero: true),
  );
  late final TextEditingController _max = TextEditingController(
    text: widget.initial.maxCents == null
        ? ''
        : Fmt.money(widget.initial.maxCents!, trimZero: true),
  );

  TimePreset _presetOf(TxnQuery q) {
    if (q.from == null || q.to == null) return TimePreset.any;
    for (final TimePreset p in <TimePreset>[
      TimePreset.current,
      TimePreset.last,
      TimePreset.last3,
      TimePreset.thisYear,
    ]) {
      final ({LocalDate from, LocalDate to})? r = rangeOfPreset(
        p,
        cycleStartDay: widget.cycleStartDay,
      );
      if (r != null && r.from == q.from && r.to == q.to) return p;
    }
    return TimePreset.custom;
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  /// 转账没有分类维度 → 分类整块不渲染；类型切到「不是支出/收入」也要清分类。
  bool get _showCategories => _type != TxnType.transfer;

  /// 切类型时把不再成立的分类清掉。
  ///
  /// 分类天然只属于一侧（支出分类 / 收入分类），所以切到另一侧后旧选择是
  /// 无意义的 —— 留着会筛出一片空白，用户还得再回来点一次「重置」。
  /// 但切到「全部」（[type] 为 null）时分类仍然成立，保留。
  void _onTypeChanged(CategoryTree tree, TxnType? type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      if (type == TxnType.transfer) {
        _categoryId = null;
        return;
      }
      final int? id = _categoryId;
      if (id == null || type == null) return;
      final Category? picked = tree.byId(id);
      if (picked != null && picked.type != type) _categoryId = null;
    });
  }

  ({int? min, int? max}) get _amountRange {
    int? min = _min.text.trim().isEmpty ? null : Fmt.parseCents(_min.text);
    int? max = _max.text.trim().isEmpty ? null : Fmt.parseCents(_max.text);
    // 填反了自动交换（用户不该因为顺序被骂一次）
    if (min != null && max != null && min > max) {
      final int t = min;
      min = max;
      max = t;
    }
    return (min: min, max: max);
  }

  void _apply() {
    final ({LocalDate from, LocalDate to})? range = _preset == TimePreset.custom
        ? (_customFrom == null || _customTo == null
              ? null
              : (from: _customFrom!, to: _customTo!))
        : rangeOfPreset(_preset, cycleStartDay: widget.cycleStartDay);
    final ({int? min, int? max}) amount = _amountRange;
    Navigator.of(context).pop(
      TxnQuery(
        type: _type,
        categoryId: _showCategories ? _categoryId : null,
        accountId: _accountId,
        minCents: amount.min,
        maxCents: amount.max,
        from: range?.from,
        to: range?.to,
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(
              start: _customFrom!.toDateTime(),
              end: _customTo!.toDateTime(),
            )
          : null,
    );
    if (picked == null) return;
    setState(() {
      _customFrom = LocalDate.fromDateTime(picked.start);
      _customTo = LocalDate.fromDateTime(picked.end);
      _preset = TimePreset.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final CategoryTree tree = CatalogScope.watch(context).tree;

    return SheetFrame(
      title: '筛选',
      trailing: TextButton(
        key: const ValueKey<String>('filter-reset'),
        onPressed: () => setState(() {
          _type = null;
          _categoryId = null;
          _accountId = null;
          _preset = TimePreset.any;
          _min.clear();
          _max.clear();
        }),
        child: Text('重置', style: Ts.caption.copyWith(color: pal.ink2)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _label('类型', pal),
            ChipTabs<TxnType?>(
              padding: EdgeInsets.zero,
              items: const <ChipTabItem<TxnType?>>[
                ChipTabItem<TxnType?>(null, '全部'),
                ChipTabItem<TxnType?>(TxnType.expense, '支出'),
                ChipTabItem<TxnType?>(TxnType.income, '收入'),
                ChipTabItem<TxnType?>(TxnType.transfer, '转账'),
              ],
              selected: _type,
              onChanged: (TxnType? t) => _onTypeChanged(tree, t),
            ),
            if (_showCategories) ...<Widget>[
              _label('分类', pal),
              _CategoryChips(
                tree: tree,
                type: _type ?? TxnType.expense,
                selected: _categoryId,
                onChanged: (int? id) => setState(() => _categoryId = id),
              ),
            ],
            _label('账户', pal),
            _AccountChips(
              selected: _accountId,
              onChanged: (int? id) => setState(() => _accountId = id),
            ),
            _label('金额区间（元）', pal),
            Row(
              children: <Widget>[
                Expanded(child: _amountField(_min, '最低', 'filter-min')),
                const SizedBox(width: S.sm),
                Expanded(child: _amountField(_max, '最高', 'filter-max')),
              ],
            ),
            _label('时间段', pal),
            ChipTabs<TimePreset>(
              padding: EdgeInsets.zero,
              items: <ChipTabItem<TimePreset>>[
                for (final TimePreset p in TimePreset.values)
                  ChipTabItem<TimePreset>(p, p.label),
              ],
              selected: _preset,
              onChanged: (TimePreset p) {
                setState(() => _preset = p);
                if (p == TimePreset.custom) _pickCustomRange();
              },
            ),
            const SizedBox(height: S.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey<String>('filter-apply'),
                onPressed: _apply,
                child: const Text('应用'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, AppPalette pal) => Padding(
    padding: const EdgeInsets.only(top: S.md, bottom: S.sm),
    child: Text(text, style: Ts.caption.copyWith(color: pal.ink3)),
  );

  Widget _amountField(TextEditingController c, String hint, String key) {
    final AppPalette pal = context.pal;
    return TextField(
      key: ValueKey<String>(key),
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.tree,
    required this.type,
    required this.selected,
    required this.onChanged,
  });

  final CategoryTree tree;
  final TxnType type;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<Category> tops = tree.topsOf(type);
    final Category? selectedTop = selected == null ? null : tree.byId(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ChipTabs<int?>(
          padding: EdgeInsets.zero,
          items: <ChipTabItem<int?>>[
            const ChipTabItem<int?>(null, '全部分类'),
            for (final Category c in tops) ChipTabItem<int?>(c.id, c.name),
          ],
          selected: selectedTop == null
              ? null
              : (selectedTop.isTop ? selectedTop.id : selectedTop.parentId),
          onChanged: onChanged,
        ),
        // 选了一级之后展开它的子分类（选子分类 = 只看这一细分）
        if (selectedTop != null) ...<Widget>[
          const SizedBox(height: S.sm),
          ChipTabs<int?>(
            padding: EdgeInsets.zero,
            items: <ChipTabItem<int?>>[
              ChipTabItem<int?>(
                selectedTop.isTop ? selectedTop.id : selectedTop.parentId,
                selectedTop.isTop ? '全部${selectedTop.name}' : '全部',
              ),
              for (final Category c in tree.childrenOf(
                selectedTop.isTop ? selectedTop.id : selectedTop.parentId,
              ))
                ChipTabItem<int?>(c.id, c.name),
            ],
            selected: selected,
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }
}

class _AccountChips extends StatelessWidget {
  const _AccountChips({required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final accounts = CatalogScope.watch(context).accounts;
    return ChipTabs<int?>(
      padding: EdgeInsets.zero,
      items: <ChipTabItem<int?>>[
        const ChipTabItem<int?>(null, '全部账户'),
        for (final Account a in accounts) ChipTabItem<int?>(a.id, a.name),
      ],
      selected: selected,
      onChanged: onChanged,
    );
  }
}
