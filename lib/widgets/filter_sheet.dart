import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cycle.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import 'common.dart';
import 'pickers.dart';

/// 打开筛选面板。
///
/// 返回 `null` 表示用户取消（不应用），返回 [TxnFilter] 表示应用。
Future<TxnFilter?> showFilterSheet(BuildContext context, TxnFilter current) {
  return showModalBottomSheet<TxnFilter>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final TxnFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  TxnType? _type;
  int? _categoryId;
  int? _accountId;
  String? _dateFrom;
  String? _dateTo;

  /// 时间快捷档的 key：null/none/month/lastMonth/quarter/year/custom
  String? _preset;

  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _minFocus = FocusNode();
  final _maxFocus = FocusNode();

  Timer? _debounce;
  int _count = 0;
  bool _countTruncated = false;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _type = f.type;
    _categoryId = f.categoryId;
    _accountId = f.accountId;
    _dateFrom = f.dateFrom;
    _dateTo = f.dateTo;
    _preset = _matchPreset(f.dateFrom, f.dateTo);
    if (f.minCents != null) {
      _minCtrl.text = Fmt.money(f.minCents!, trimZero: true);
    }
    if (f.maxCents != null) {
      _maxCtrl.text = Fmt.money(f.maxCents!, trimZero: true);
    }
    _scheduleCount();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _minFocus.dispose();
    _maxFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 草稿状态

  /// 面板里正在编辑的条件。金额起止填反了直接交换 —— 用户意图明确，
  /// 报错只会多一步操作。
  TxnFilter get _draft {
    var lo = _cents(_minCtrl.text);
    var hi = _cents(_maxCtrl.text);
    if (lo != null && hi != null && lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    return TxnFilter(
      type: _type,
      categoryId: _categoryId,
      accountId: _accountId,
      minCents: lo,
      maxCents: hi,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
    );
  }

  /// 空串 / 非法 / 非正数都当「没填」
  int? _cents(String input) {
    if (input.trim().isEmpty) return null;
    final v = Fmt.parseCents(input);
    return v <= 0 ? null : v;
  }

  void _scheduleCount() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _refreshCount);
  }

  Future<void> _refreshCount() async {
    final f = _draft;
    if (f.isEmpty) {
      if (!mounted) return;
      setState(() {
        _count = 0;
        _countTruncated = false;
      });
      return;
    }
    final (items, truncated) = await Repo.searchTxns(
      ledgerId: Store.i.ledgerId,
      filter: f,
    );
    if (!mounted) return;
    setState(() {
      _count = items.length;
      _countTruncated = truncated;
    });
  }

  void _edit(VoidCallback change) {
    setState(change);
    _scheduleCount();
  }

  /// 切到「收入」时分类必须清掉：支出分类配收入条件永远是空结果
  void _setType(TxnType? t) => _edit(() {
    _type = _type == t ? null : t;
    // 只有「支出」能按分类筛：收入不按分类、转账也没有分类
    if (_type != TxnType.expense) _categoryId = null;
  });

  void _reset() => _edit(() {
    _type = null;
    _categoryId = null;
    _accountId = null;
    _dateFrom = null;
    _dateTo = null;
    _preset = null;
    _minCtrl.clear();
    _maxCtrl.clear();
  });

  // ---------------------------------------------------------------- 时间档

  static const _presets = <String, String>{
    'none': '不限',
    'period': '本期',
    'lastPeriod': '上期',
    'quarter': '近 3 期',
    'year': '今年',
    'custom': '自定义',
  };

  /// 快捷档一律以「今天」所在的那一期为基准，与正在浏览的期无关 ——
  /// 「本期」就该是现在这一期，跟着浏览翻页跑会让人看不懂。
  ///
  /// 注意这里给的是**真实日期**区间：筛选始终按 `date` 筛（设计 §2.4），
  /// 否则用户筛「10 月」会筛不到 10-10 那笔被抬期的工资。
  (String, String) _rangeOf(String key) {
    final s = Store.i;
    final now = DateTime.now();
    final today = Fmt.today();
    final (curFrom, curTo) = cycleRange(now, s.cycleStartDay);
    switch (key) {
      case 'period':
        return (curFrom, curTo);
      case 'lastPeriod':
        return (
          shiftCycleDate(curFrom, s.cycleStartDay, -1),
          Fmt.date(DateTime.parse(curFrom).subtract(const Duration(days: 1))),
        );
      case 'quarter':
        return (shiftCycleDate(curFrom, s.cycleStartDay, -2), curTo);
      case 'year':
        return (Fmt.date(DateTime(now.year, 1, 1)), today);
      default:
        return ('', '');
    }
  }

  /// 反推当前区间命中了哪个快捷档（用于面板重新打开时把已选档点亮）
  String? _matchPreset(String? from, String? to) {
    if (from == null && to == null) return 'none';
    for (final k in _presets.keys) {
      if (k == 'none' || k == 'custom') continue;
      final (f, t) = _rangeOf(k);
      if (f == from && t == to) return k;
    }
    return 'custom';
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    DateTimeRange? initial;
    if (_dateFrom != null && _dateTo != null) {
      initial = DateTimeRange(
        start: DateTime.parse(_dateFrom!),
        end: DateTime.parse(_dateTo!),
      );
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
      helpText: '选择时间段',
      saveText: '确定',
    );
    if (picked == null) return;
    _edit(() {
      _preset = 'custom';
      _dateFrom = Fmt.date(picked.start);
      _dateTo = Fmt.date(picked.end);
    });
  }

  void _choosePreset(String key) {
    if (key == 'custom') {
      _pickRange();
      return;
    }
    _edit(() {
      _preset = key;
      if (key == 'none') {
        _dateFrom = null;
        _dateTo = null;
      } else {
        final (f, t) = _rangeOf(key);
        _dateFrom = f;
        _dateTo = t;
      }
    });
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final maxH = MediaQuery.of(context).size.height * 0.9;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: '筛选',
              action: TextButton(
                onPressed: _reset,
                child: const Text(
                  '重置',
                  style: TextStyle(fontSize: 13, color: C.ink2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: S.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _block('类型', _typeRow()),
                    // 转账没有分类，这一块直接不出现 —— 留着会让人以为能筛
                    if (_type != TxnType.transfer)
                      _block('分类', _categoryBlock(s)),
                    _block('账户', _accountBlock(s)),
                    _block('金额（元）', _amountRow()),
                    _block(
                      '时间',
                      _dateRow(),
                      trailing: Text(
                        _rangeLabel ?? '不限时间',
                        style: T.caption.copyWith(color: C.ink4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _block(String title, Widget child, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(S.xl, S.md, S.xl, S.sm),
          child: Row(
            children: [
              Text(title, style: T.caption),
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
        child,
      ],
    );
  }

  Widget _typeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg),
      child: Row(
        children: [
          _ToggleChip(
            label: '全部',
            selected: _type == null,
            onTap: () => _setType(null),
          ),
          const SizedBox(width: S.sm),
          _ToggleChip(
            label: '支出',
            selected: _type == TxnType.expense,
            onTap: () => _setType(TxnType.expense),
          ),
          const SizedBox(width: S.sm),
          _ToggleChip(
            label: '收入',
            selected: _type == TxnType.income,
            onTap: () => _setType(TxnType.income),
          ),
          const SizedBox(width: S.sm),
          // 「转账」是 1.4.5 补的：明细页顶部那排快捷筛选撤掉之后，
          // 这里是「只看转账」唯一的入口。转账不属于收支两侧，
          // 选中时必须把分类一起清掉（见 _setType），否则条件会互相打架。
          _ToggleChip(
            label: '转账',
            selected: _type == TxnType.transfer,
            onTap: () => _setType(TxnType.transfer),
          ),
        ],
      ),
    );
  }

  Widget _categoryBlock(Store s) {
    final locked = _type == TxnType.income;
    // 选中的可能是子分类（二级筛选），网格的高亮要落回它的一级
    final sel = s.categoryOf(_categoryId);
    final topId = sel == null ? null : (sel.parentId ?? sel.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (locked)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.xl, 0, S.xl, S.xs),
            child: Text('收入不按分类筛选', style: T.caption.copyWith(color: C.ink4)),
          ),
        IgnorePointer(
          ignoring: locked,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: locked ? 0.35 : 1,
            child: CategoryGrid(
              cats: s.expenseCats,
              selected: topId,
              onSelect: (id) =>
                  _edit(() => _categoryId = _categoryId == id ? null : id),
            ),
          ),
        ),
        if (!locked) _subRow(s, sel),
      ],
    );
  }

  /// 选中一级之后，在下面再给一排子分类。
  ///
  /// 两级分类的意义就在这一排：「餐饮」看整体，「餐饮 / 正餐」看细分。
  /// 只给一级的话，用户为了查午饭只能把整月餐饮都翻一遍。
  Widget _subRow(Store s, Category? sel) {
    if (sel == null) return const SizedBox.shrink();
    final top = sel.parentId == null ? sel : s.categoryOf(sel.parentId);
    if (top == null) return const SizedBox.shrink();
    final subs = s.childrenOf(top.id);
    if (subs.isEmpty) return const SizedBox.shrink();
    final activeSub = sel.parentId == null ? null : sel.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xl, S.sm, S.lg, 0),
      child: Wrap(
        spacing: S.sm,
        runSpacing: S.sm,
        children: [
          _ToggleChip(
            label: '全部',
            selected: activeSub == null,
            onTap: () => _edit(() => _categoryId = top.id),
          ),
          for (final c in subs)
            _ToggleChip(
              label: c.name,
              selected: activeSub == c.id,
              onTap: () => _edit(() => _categoryId = c.id),
            ),
        ],
      ),
    );
  }

  Widget _accountBlock(Store s) {
    if (s.accounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: S.xl),
        child: Text('还没有账户，请先到「我的 → 账户管理」添加', style: T.caption),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg),
      child: Wrap(
        spacing: S.sm,
        runSpacing: S.sm,
        children: [
          for (final a in s.accounts)
            _ToggleChip(
              label: a.name,
              icon: a.icon,
              selected: _accountId == a.id,
              onTap: () =>
                  _edit(() => _accountId = _accountId == a.id ? null : a.id),
            ),
        ],
      ),
    );
  }

  Widget _amountRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg),
      child: Row(
        children: [
          Expanded(child: _amountField(_minCtrl, _minFocus, '起')),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.sm),
            child: Text('—', style: TextStyle(color: C.ink4)),
          ),
          Expanded(child: _amountField(_maxCtrl, _maxFocus, '止')),
        ],
      ),
    );
  }

  Widget _amountField(
    TextEditingController ctrl,
    FocusNode focus,
    String hint,
  ) {
    // 触摸目标撑到 48dp（原来 isDense + 上下 12 的 padding 只有 40dp 左右，
    // 点起来发飘），并且整格都能聚焦：灰底之外那圈空白也接手势，
    // 手指偏差个十几像素也不会点空。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!focus.hasFocus) focus.requestFocus();
      },
      child: Container(
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: S.md),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: TextField(
          controller: ctrl,
          focusNode: focus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: T.body,
          onChanged: (_) => _scheduleCount(),
          decoration: InputDecoration.collapsed(
            hintText: hint,
            hintStyle: const TextStyle(color: C.ink4, fontSize: 14.5),
          ),
        ),
      ),
    );
  }

  /// 当前时间段文案，显示在「时间」标题右侧
  String? get _rangeLabel {
    if (_dateFrom == null && _dateTo == null) return null;
    return TxnFilter(dateFrom: _dateFrom, dateTo: _dateTo).dateLabel;
  }

  Widget _dateRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg),
      child: Wrap(
        spacing: S.sm,
        runSpacing: S.sm,
        children: [
          for (final e in _presets.entries)
            _ToggleChip(
              label: e.value,
              selected: _preset == e.key,
              onTap: () => _choosePreset(e.key),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final f = _draft;
    final canApply = f.isNotEmpty;
    final label = canApply
        ? '查看 $_count${_countTruncated ? '+' : ''} 条结果'
        : '选一个条件';

    return Container(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.lg),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(color: C.line2),
                ),
                child: Text('取消', style: T.body2.copyWith(color: C.ink2)),
              ),
            ),
          ),
          const SizedBox(width: S.sm),
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canApply ? () => Navigator.pop(context, f) : null,
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: canApply ? C.ink : C.bg2,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: canApply ? C.bg : C.ink4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 可点选的 chip。与记一笔面板里那个 `_Chip` 不同：那个是「点开选择器」
/// 的入口，没有选中态；筛选要的是「亮起来表示已选中」，所以单独一个。
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: S.md),
        decoration: BoxDecoration(
          color: selected ? C.ink : C.bg2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              LineIcon(icon!, size: 16, color: selected ? C.bg : C.ink2),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? C.bg : C.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
