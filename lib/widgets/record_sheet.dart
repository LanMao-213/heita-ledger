import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/calc.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import 'common.dart';
import 'calc_keypad.dart';
import 'picker_wheels.dart';

/// 打开「记一笔」面板。传入 [editing] 则为编辑模式。
/// 返回 true 表示保存成功。
Future<bool?> showRecordSheet(BuildContext context, {Txn? editing}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.bg,
    builder: (_) => RecordSheet(editing: editing),
  );
}

class RecordSheet extends StatefulWidget {
  const RecordSheet({super.key, this.editing});

  final Txn? editing;

  @override
  State<RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<RecordSheet> {
  late TxnType _type;
  late int? _categoryId;
  late int? _accountId;
  late String _date;
  late TextEditingController _note;

  /// 双轮盘里选了「自定义…」时，把焦点交给备注框
  final _noteFocus = FocusNode();

  /// 正在输入的金额，直接存字符串便于按键操作（避免浮点误差累积）
  String _amountInput = '';
  bool _saving = false;

  /// 从模板填进来的那一笔。保存时会把 template_id 记到账目上并累加使用次数。
  TxnTemplate? _applied;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final s = Store.i;
    final e = widget.editing;
    _type = e?.type ?? TxnType.expense;
    _categoryId = e?.categoryId;
    _accountId = e?.accountId ?? (s.accounts.isEmpty ? null : s.accounts.first.id);
    _date = e?.date ?? Fmt.today();
    _note = TextEditingController(text: e?.note ?? '');
    if (e != null) {
      _amountInput = _amountText(e.amountCents);
    }
    // 编辑时若原记录没分类，落到该类型的第一个分类
    _categoryId ??= _firstCategoryId();
  }

  /// 分 → 输入框里的字符串：「1200」显示成「12」，避免一串 .00 干扰输入
  static String _amountText(int cents) {
    final s = (cents / 100).toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  List<Category> get _cats =>
      _type.isIncome ? Store.i.incomeCats : Store.i.expenseCats;

  int? _firstCategoryId() {
    final list = _cats;
    return list.isEmpty ? null : list.first.id;
  }

  /// 表达式求值结果（分）。没输完或非法时为 null，此时不能保存。
  ///
  /// 0 与负数都算合法：负数表示这一笔的**净额**（代购代付后对方多给的钱，
  /// 记一笔支出 −20，而不是拆成一笔支出加一笔收入）。
  int? get _amountCents => Calc.cents(_amountInput);

  bool get _canSave => _amountCents != null;

  @override
  void dispose() {
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// 双轮盘：左选分类、右选名目。选「自定义…」就把焦点交回备注框。
  Future<void> _pickCategoryNote() async {
    final pick = await showCategoryNoteWheel(
      context,
      cats: _cats,
      categoryId: _categoryId,
      type: _type,
      note: _note.text,
    );
    if (pick == null || !mounted) return;
    setState(() {
      _categoryId = pick.categoryId;
      if (pick.note != null) _note.text = pick.note!;
    });
    if (pick.note == null) _noteFocus.requestFocus();
  }

  /// 按键只是对表达式字符串做一次变换，规则都收在 Calc.press 里
  void _pressKey(String k) {
    setState(() => _amountInput = Calc.press(_amountInput, k));
  }

  /// 点模板 = 把模板里的东西一次性填进来。此时还不算「用了一次」，
  /// 只有真的保存成功才累加使用次数 —— 否则用户点开看看就把统计弄脏了。
  void _applyTemplate(TxnTemplate t) {
    setState(() {
      _applied = t;
      if (t.type != TxnType.transfer) {
        _type = t.type;
        _categoryId = t.categoryId ?? _firstCategoryId();
      }
      if (t.accountId != null) _accountId = t.accountId;
      if (t.hasAmount) _amountInput = _amountText(t.amountCents);
      if (t.note.isNotEmpty) _note.text = t.note;
    });
  }

  /// 把一个已经存在、且内容高度一致的模板找出来（同类型 + 同分类 + 同金额），
  /// 这样即使没用顶部那排模板，手敲的钱也会正确计数。
  TxnTemplate? _matchingTemplate() {
    for (final t in Store.i.templates) {
      if (t.type != _type) continue;
      if (t.categoryId != _categoryId) continue;
      if (!t.hasAmount || t.amountCents != _amountCents) continue;
      return t;
    }
    return null;
  }

  /// 「存为模板」：把当前填好的内容原样存下来
  Future<void> _saveAsTemplate() async {
    if (_categoryId == null) {
      showToast(context, '请先选一个分类');
      return;
    }
    final catName = Store.i.categoryOf(_categoryId)?.name ?? '模板';
    final ctl = TextEditingController(text: catName);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('存为模板', style: T.section),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 8,
            style: T.body,
            decoration: const InputDecoration(
              hintText: '模板名称',
              counterText: '',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: C.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存', style: TextStyle(color: C.ink)),
          ),
        ],
      ),
    );

    final name = ctl.text.trim();
    ctl.dispose();
    if (ok != true) return;

    await Repo.insertTemplate(TxnTemplate(
      id: 0,
      ledgerId: Store.i.ledgerId,
      name: name.isEmpty ? catName : name,
      icon: Store.i.categoryOf(_categoryId)?.icon ?? 'tpl',
      type: _type,
      amountCents: _amountCents ?? 0,
      categoryId: _categoryId,
      accountId: _accountId,
      note: _note.text.trim(),
    ));
    await Store.i.afterTemplateChange();
    if (!mounted) return;
    setState(() {}); // 让顶部那排模板立刻带上新的
    showToast(context, '已存为模板');
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    final cents = _amountCents!;

    final store = Store.i;
    final note = _note.text.trim();
    // 用了模板就记在账目上；没用但内容跟某个模板一模一样，也算它一次
    final tplId = _applied?.id ?? _matchingTemplate()?.id;

    try {
      if (_isEdit) {
        final old = widget.editing!;
        final now = Txn(
          id: old.id,
          ledgerId: old.ledgerId,
          type: _type,
          amountCents: cents,
          date: _date,
          categoryId: _categoryId,
          accountId: _accountId,
          note: note,
          templateId: old.templateId,
          recurringId: old.recurringId,
          createdAt: old.createdAt,
        );
        await Repo.updateTxn(old, now);
      } else {
        await Repo.insertTxn(Txn(
          id: 0,
          ledgerId: store.ledgerId,
          type: _type,
          amountCents: cents,
          date: _date,
          categoryId: _categoryId,
          accountId: _accountId,
          note: note,
          templateId: tplId,
        ));
        if (tplId != null) {
          await Repo.touchTemplate(tplId);
          await store.afterTemplateChange();
        }
      }
      await store.afterTxnChange();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, '保存失败：$err');
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
    if (picked != null) setState(() => _date = Fmt.date(picked));
  }

  void _pickAccount() {
    final s = Store.i;
    if (s.accounts.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(title: '选择账户'),
            for (final a in s.accounts)
              SettingRow(
                icon: a.icon,
                title: a.name,
                subtitle: Fmt.yuan(a.balanceCents),
                trailing: a.id == _accountId
                    ? const Icon(Icons.check_rounded, size: 20, color: C.ink)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _accountId = a.id);
                },
              ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 0.90：顶部多了「最近模板」那排之后，0.88 会把备注框切掉一条
    final maxH = media.size.height * 0.90;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: _isEdit ? '编辑记录' : '记一笔',
            action: _isEdit
                ? TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消', style: TextStyle(color: C.ink2)),
                  )
                : TextButton(
                    onPressed: _saveAsTemplate,
                    child: const Text(
                      '存为模板',
                      style: TextStyle(fontSize: 13, color: C.ink2),
                    ),
                  ),
          ),
          // 顶部常驻「最近用过的模板」—— 记账高频场景下这就是快捷键
          if (!_isEdit && Store.i.recentTemplates.isNotEmpty)
            _TemplateStrip(
              templates: Store.i.recentTemplates,
              appliedId: _applied?.id,
              onTap: _applyTemplate,
            ),
          _TypeSwitch(
            value: _type,
            onChanged: (t) {
              setState(() {
                _type = t;
                // 切换收支后原分类不再适用，重置到第一个；模板也随之失效
                _categoryId = _firstCategoryId();
                _applied = null;
              });
            },
          ),
          _AmountDisplay(input: _amountInput, type: _type),
          const Divider(height: 1, color: C.line),
          // 用 Flexible 而不是 Expanded：内容不满一屏时面板贴着内容收起来，
          // 否则备注框和键盘之间会空出一大块（模板少的时候尤其明显）
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: S.sm),
              child: Column(
                children: [
                  _CategoryNoteRow(
                    category: Store.i.categoryOf(_categoryId),
                    note: _note,
                    onTap: _pickCategoryNote,
                  ),
                  const Divider(height: 1, color: C.line),
                  _MetaRow(
                    date: _date,
                    onPickDate: _pickDate,
                    accountName: Store.i.accountOf(_accountId)?.name ?? '未选账户',
                    accountIcon: Store.i.accountOf(_accountId)?.icon ?? 'wallet',
                    onPickAccount: _pickAccount,
                  ),
                  _NoteField(controller: _note, focusNode: _noteFocus),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: C.line),
          CalcKeypad(
            onKey: _pressKey,
            onConfirm: _save,
            canConfirm: _canSave && !_saving,
          ),
        ],
      ),
    );
  }
}

/// 「最近用过的模板」横排。点一下就填，选中态用纯黑反白，
/// 和其它选中态（分类九宫格、底部导航）保持同一套语言。
class _TemplateStrip extends StatelessWidget {
  const _TemplateStrip({
    required this.templates,
    required this.appliedId,
    required this.onTap,
  });

  final List<TxnTemplate> templates;
  final int? appliedId;
  final ValueChanged<TxnTemplate> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(S.lg, 2, S.lg, 6),
        itemCount: templates.length,
        separatorBuilder: (_, _) => const SizedBox(width: S.sm),
        itemBuilder: (context, i) {
          final t = templates[i];
          final on = t.id == appliedId;
          return GestureDetector(
            onTap: () => onTap(t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: on ? C.ink : C.bg2,
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LineIcon(t.icon, size: 15, color: on ? C.bg : C.ink2),
                  const SizedBox(width: 6),
                  Text(
                    t.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: on ? C.bg : C.ink,
                      fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  if (t.hasAmount) ...[
                    const SizedBox(width: 6),
                    Text(
                      Fmt.yuan(t.amountCents),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: on
                            ? C.bg.withValues(alpha: 0.72)
                            : C.ink3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TypeSwitch extends StatelessWidget {
  const _TypeSwitch({required this.value, required this.onChanged});

  final TxnType value;
  final ValueChanged<TxnType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg),
      child: SegTabs(value: value, onChanged: onChanged),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.input, required this.type});

  final String input;
  final TxnType type;

  @override
  Widget build(BuildContext context) {
    final cents = Calc.cents(input);
    // 收支决定这笔记账的方向；金额本身带负号时符号自然翻转
    // （支出 −20 = 净流入 20，显示成 +20.00）
    final signed = cents == null ? 0 : (type.isIncome ? cents : -cents);
    // 金额还是 0 的时候，符号只能由收支类型决定（支出显示 −、收入显示 +）
    final sign = (cents == null || cents == 0)
        ? (type.isIncome ? '+' : '-')
        : (signed > 0 ? '+' : '-');
    final amountText = cents == null
        ? '0'
        : Fmt.money(signed.abs(), trimZero: true);

    return Padding(
      // 顶部多了一排模板，这里收一点，保证键盘在首屏里露全
      padding: const EdgeInsets.fromLTRB(S.lg, S.xs, S.lg, S.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 有运算才显示算式行，纯数字时不浪费高度
          SizedBox(
            height: 16,
            child: Calc.hasOperator(input)
                ? Text(
                    Calc.pretty(input),
                    style: T.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                sign,
                style: T.hero.copyWith(fontSize: 24, color: C.ink3),
              ),
              const SizedBox(width: 3),
              Text('¥', style: T.hero.copyWith(fontSize: 24, color: C.ink2)),
              const SizedBox(width: 5),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(amountText, style: T.hero.copyWith(fontSize: 40)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.date,
    required this.onPickDate,
    required this.accountName,
    required this.accountIcon,
    required this.onPickAccount,
  });

  final String date;
  final VoidCallback onPickDate;
  final String accountName;
  final String accountIcon;
  final VoidCallback onPickAccount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 上面紧挨着分隔线，留 12 的呼吸位；下面接备注框，收 8 免得两处叠成一大块
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
      child: Row(
        children: [
          Expanded(
            child: _Chip(
              icon: 'rec',
              label: Fmt.friendly(date),
              onTap: onPickDate,
            ),
          ),
          const SizedBox(width: S.md),
          Expanded(
            child: _Chip(
              icon: accountIcon,
              label: accountName,
              onTap: onPickAccount,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: S.md),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(
          children: [
            LineIcon(icon, size: 17, color: C.ink2),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(
                label,
                style: T.body2.copyWith(color: C.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类 + 名目的一行摘要，点它打开双轮盘。
///
/// 原来这里是一个 5 列九宫格：选分类要点一下，写名目要再点备注框打字。
/// 换成一行摘要 + 双轮盘之后，分类和名目在同一次操作里定完。
class _CategoryNoteRow extends StatelessWidget {
  const _CategoryNoteRow({
    required this.category,
    required this.note,
    required this.onTap,
  });

  final Category? category;
  final TextEditingController note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedBuilder(
        // 备注在下方输入框里改动时，这里要跟着显示
        animation: note,
        builder: (context, _) {
          final text = note.text.trim();
          return Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.md, S.md),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: C.bg2,
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Center(
                    child: LineIcon(
                      category?.icon ?? 'more',
                      size: 20,
                      color: C.ink2,
                    ),
                  ),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category?.name ?? '选择分类',
                        style: T.body.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        text.isEmpty ? '选名目，或自己写备注' : text,
                        style: T.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_right_rounded,
                  size: 20,
                  color: C.ink4,
                ),
                const SizedBox(width: S.sm),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller, this.focusNode});

  final TextEditingController controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.lg),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: T.body,
        maxLength: 60,
        inputFormatters: [LengthLimitingTextInputFormatter(60)],
        decoration: InputDecoration(
          counterText: '',
          hintText: '备注（可不填）',
          hintStyle: T.body2.copyWith(color: C.ink4),
          filled: true,
          fillColor: C.bg2,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: S.md, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.md),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

