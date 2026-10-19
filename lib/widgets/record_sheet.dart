import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/calc.dart';
import '../data/category_seed.dart';
import '../data/cycle.dart';
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
    // 透明底 + 自己画背景：面板要给系统键盘让出底部空间，那段留白如果由
    // 面板自己涂白，键盘弹起的过程中会先闪一块白板（看起来像「重开了一页」）。
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
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

  /// 备注框滚到可见位置用（键盘弹起后信息区会被压扁）
  final _scroll = ScrollController();

  /// 备注框自身的位置。键盘弹起时只把**它**滚进视野，
  /// 不再 `animateTo(maxScrollExtent)` —— 后者会把整个信息区顶上去，
  /// 和面板收缩叠在一起，看起来就像「关掉一页又开了一页」。
  final _noteKey = GlobalKey();

  /// 四个详情字段的输入控制器。**四个都建**，不管当前分类用不用得上：
  /// 用户选错分类再选回来时，已经敲进去的内容不能因为重建而消失。
  final _detailCtl = <TxnField, TextEditingController>{};
  final _detailFocus = <TxnField, FocusNode>{};
  final _detailKey = <TxnField, GlobalKey>{};

  /// 折叠区的展开状态（只看出行类）。编辑一条已经填过地点的记录时默认展开，
  /// 否则用户会以为数据丢了。
  bool _detailsOpen = false;

  /// 信息区下面还压着东西（详情区一展开，日期/备注就会被顶出可视区）。
  /// 用来在底部画一条渐变，否则被裁掉的那一行看起来像「界面坏了」。
  bool _moreBelow = false;

  /// 正在输入的金额，直接存字符串便于按键操作（避免浮点误差累积）
  String _amountInput = '';
  bool _saving = false;

  /// 从模板填进来的那一笔。保存时会把 template_id 记到账目上并累加使用次数。
  TxnTemplate? _applied;

  /// 「这笔算下一期」的手动开关。null = 跟着分类白名单走默认值。
  /// 白名单只给初值，最终值必须能听用户的（设计 §5.2）。
  bool? _liftOverride;

  bool get _isEdit => widget.editing != null;

  /// 只有收入、且这笔真的落在「同月账单日之前」时，抬期开关才有意义
  bool get _showLift =>
      _type.isIncome && liftable(_date, Store.i.cycleStartDay);

  /// 当前开关状态：手动拨过就听手动的，否则按分类白名单
  bool get _liftOn =>
      _liftOverride ??
      (_categoryId != null && Store.i.liftableCatIds.contains(_categoryId));

  @override
  void initState() {
    super.initState();
    // 备注框拿到/失去焦点时要重画：焦点在备注里时数字键盘要让位给系统输入法
    _noteFocus.addListener(_onTextFocusChanged);
    _scroll.addListener(_syncScrollHint);
    final s = Store.i;
    final e = widget.editing;
    _type = e?.type ?? TxnType.expense;
    _categoryId = e?.categoryId;
    _accountId =
        e?.accountId ?? (s.accounts.isEmpty ? null : s.accounts.first.id);
    _date = e?.date ?? Fmt.today();
    _note = TextEditingController(text: e?.note ?? '');
    if (e != null) {
      _amountInput = _amountText(e.amountCents);
    }
    // 编辑时若原记录没分类，落到该类型的第一个分类
    _categoryId ??= _firstCategoryId();

    for (final f in TxnField.values) {
      _detailCtl[f] = TextEditingController(text: e?.detail(f) ?? '');
      _detailFocus[f] = FocusNode()..addListener(_onTextFocusChanged);
      _detailKey[f] = GlobalKey();
    }
    _detailsOpen = e != null && e.filledDetails.isNotEmpty;

    // 反推「计入下期」开关：归属期跟真实日期所在期不一致，就是当时拨开了
    if (e != null && e.periodStart != null) {
      _liftOverride = e.periodStart != periodStartOf(e.date, s.cycleStartDay);
    }
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
    _noteFocus.removeListener(_onTextFocusChanged);
    _note.dispose();
    _noteFocus.dispose();
    _scroll
      ..removeListener(_syncScrollHint)
      ..dispose();
    for (final c in _detailCtl.values) {
      c.dispose();
    }
    for (final f in _detailFocus.values) {
      f
        ..removeListener(_onTextFocusChanged)
        ..dispose();
    }
    super.dispose();
  }

  /// 同步「下面还有内容」的状态。只在真的变化时 setState，
  /// 否则会变成「重建 → 布局 → 又重建」的死循环。
  void _syncScrollHint() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final more = p.maxScrollExtent - p.pixels > 2;
    if (more != _moreBelow) setState(() => _moreBelow = more);
  }

  /// 当前分类要填哪些详情字段。空表示不需要（绝大多数分类）。
  ///
  /// 口径来自 [fieldsOfSub]：种子登记过的子分类才有，用户自建的分类不要 ——
  /// 猜不出的字段宁可不显示，也别给每个分类都塞四个框。
  List<TxnField> get _fields =>
      fieldsOfSub(Store.i.categoryOf(_categoryId)?.name);

  /// 这个分类的详情要不要默认折叠（只看出行：地点两端）
  bool get _folded =>
      kFoldedSubs.contains(Store.i.categoryOf(_categoryId)?.name);

  /// 任意一个文本输入框有焦点。有焦点才让数字键盘让位 ——
  /// 只判备注框的话，点「出发地」时数字键盘还赖在下面占掉半屏。
  bool get _hasTextFocus =>
      _noteFocus.hasFocus || _detailFocus.values.any((f) => f.hasFocus);

  /// 当前有焦点的输入框位置，没焦点返回 null
  GlobalKey? get _focusedKey {
    if (_noteFocus.hasFocus) return _noteKey;
    for (final e in _detailFocus.entries) {
      if (e.value.hasFocus) return _detailKey[e.key];
    }
    return null;
  }

  void _onTextFocusChanged() {
    if (!mounted) return;
    setState(() {});
    // 输入法把信息区压扁之后，正在输入的框可能落到可视区下面。只保证**它**
    // 可见，不做整块滚动 —— 滚动幅度越小，越不会被看成「换了一个界面」。
    final key = _focusedKey;
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// 双轮盘：左选一级、右选子分类。右轮首项「不细分」= 只记到一级。
  Future<void> _pickCategory() async {
    final pick = await showCategoryWheel(
      context,
      cats: _cats,
      childrenOf: Store.i.childrenOf,
      selectedCategoryId: _categoryId,
    );
    if (pick == null || !mounted) return;
    setState(() => _categoryId = pick.txnCategoryId);
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

    await Repo.insertTemplate(
      TxnTemplate(
        id: 0,
        ledgerId: Store.i.ledgerId,
        name: name.isEmpty ? catName : name,
        icon: Store.i.categoryOf(_categoryId)?.icon ?? 'tpl',
        type: _type,
        amountCents: _amountCents ?? 0,
        categoryId: _categoryId,
        accountId: _accountId,
        note: _note.text.trim(),
      ),
    );
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

    // 四个详情字段**全部带上**，哪怕当前分类用不上：用户在「公共交通」里
    // 填了出发地又改成「打车」，两个分类都要这两个字段，中间不该丢一次。
    String d(TxnField f) => _detailCtl[f]!.text.trim();

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
          placeFrom: d(TxnField.from),
          placeTo: d(TxnField.to),
          person: d(TxnField.person),
          subject: d(TxnField.subject),
          templateId: old.templateId,
          recurringId: old.recurringId,
          createdAt: old.createdAt,
        );
        await Repo.updateTxn(old, now, liftToNext: _liftOverride);
      } else {
        await Repo.insertTxn(
          Txn(
            id: 0,
            ledgerId: store.ledgerId,
            type: _type,
            amountCents: cents,
            date: _date,
            categoryId: _categoryId,
            accountId: _accountId,
            note: note,
            placeFrom: d(TxnField.from),
            placeTo: d(TxnField.to),
            person: d(TxnField.person),
            subject: d(TxnField.subject),
            templateId: tplId,
          ),
          liftToNext: _liftOverride,
        );
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
    // 系统输入法占掉的高度。写备注时下半屏归它，面板必须整体让开，
    // 否则备注框正好落在它底下。
    final keyboard = media.viewInsets.bottom;
    // 没有输入法时，屏幕底部还有手势条 / 三键导航栏。它不体现在 size 里，
    // 面板必须自己让出来 —— 之前漏了这一步，真机上键盘最后一排（0 / . / 确认）
    // 正好被手势条压掉一条，看起来就是「键盘尺寸不对」。
    final bottomInset = keyboard > media.viewPadding.bottom
        ? keyboard
        : media.viewPadding.bottom;
    // 焦点在备注里、且输入法真的弹出时，才把数字键盘收起来。
    // 只看焦点不看键盘高度的话，用户用输入法自带的「完成」收起键盘后，
    // 数字键盘不会回来，连确认键一起消失。
    final typingNote = keyboard > 0 && _hasTextFocus;
    // 0.90：顶部多了「最近模板」那排之后，0.88 会把备注框切掉一条。
    final maxH = (media.size.height - bottomInset) * 0.90;

    final body = LayoutBuilder(
      builder: (context, box) {
        // 键高跟着可用高度走：先给头部 / 金额 / 信息区留 380，剩下 5 排均分。
        // 56 是设计值（46 → 52 → 56，键偏矮不好按），只有矮屏才往下收 ——
        // 宁可键矮一点，也不要裁掉「确认」。
        //
        // 有分类详情时上限压到 52：详情区要多吃 40~90 的高度，而信息区里
        // 的「日期 / 账户」不能因为多填两个框就被挤出可视区。4dp 的键高差
        // 手感上几乎看不出，信息被裁掉却一眼就能看出。
        final keyH = ((box.maxHeight - 380) / 5).clamp(
          38.0,
          _fields.isEmpty ? 56.0 : 52.0,
        );
        return Column(
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
            _AmountDisplay(input: _amountInput),
            const Divider(height: 1, color: C.line),
            // 用 Flexible 而不是 Expanded：内容不满一屏时面板贴着内容收起来，
            // 否则备注框和键盘之间会空出一大块（模板少的时候尤其明显）
            Flexible(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: S.sm),
                    child: Column(
                      children: [
                        _CategoryNoteRow(
                          category: Store.i.categoryOf(_categoryId),
                          parent: Store.i.parentOf(
                            Store.i.categoryOf(_categoryId),
                          ),
                          note: _note,
                          onTap: _pickCategory,
                        ),
                        const Divider(height: 1, color: C.line),
                        // 有详情字段时，备注框**提到详情前面**。
                        // 详情区一出现就把信息区撑高，备注留在最后会被整块顶出
                        // 可视区 —— 它不是必填项，藏起来用户就当它不存在了。
                        // 顺序仍是「先补充说明、再日期账户」：详情本来就是
                        // 分类的延伸，和备注挨着比隔着日期更顺。
                        if (_fields.isNotEmpty) ...[
                          _NoteField(
                            key: _noteKey,
                            controller: _note,
                            focusNode: _noteFocus,
                            onSubmitted: (_) => _noteFocus.unfocus(),
                          ),
                          const Divider(height: 1, color: C.line),
                          _DetailBlock(
                            fields: _fields,
                            folded: _folded,
                            open: _detailsOpen,
                            controllers: _detailCtl,
                            focusNodes: _detailFocus,
                            keys: _detailKey,
                            onToggle: () =>
                                setState(() => _detailsOpen = !_detailsOpen),
                          ),
                          const Divider(height: 1, color: C.line),
                        ],
                        _MetaRow(
                          date: _date,
                          onPickDate: _pickDate,
                          accountName:
                              Store.i.accountOf(_accountId)?.name ?? '未选账户',
                          accountIcon:
                              Store.i.accountOf(_accountId)?.icon ?? 'wallet',
                          onPickAccount: _pickAccount,
                        ),
                        if (_showLift)
                          _LiftRow(
                            on: _liftOn,
                            periodLabel: shortYmd(
                              periodStartOf(
                                _date,
                                Store.i.cycleStartDay,
                                liftToNext: _liftOn,
                              ),
                            ),
                            onChanged: (v) => setState(() => _liftOverride = v),
                          ),
                        if (_fields.isEmpty)
                          _NoteField(
                            key: _noteKey,
                            controller: _note,
                            focusNode: _noteFocus,
                            // 输入法的「完成」= 备注写完：收起键盘，数字键盘和确认键回来
                            onSubmitted: (_) => _noteFocus.unfocus(),
                          ),
                      ],
                    ),
                  ),
                  // 还能往下滚时，底部压一层渐隐 —— 不铺这层的话，被裁掉的
                  // 「日期 / 备注」看起来像界面画坏了一道横线。
                  if (_moreBelow)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 22,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [C.bg.withValues(alpha: 0), C.bg],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 写备注时数字键盘让位：它 270dp 高，和系统键盘叠在一起会把可滚动区
            // 压成 0，备注框照样看不见；何况这时候本来也按不到数字。
            // 不给「完成」按钮：输入法自带的那颗 + 收起键盘，都是「写完了」。
            if (!typingNote) ...[
              const Divider(height: 1, color: C.line),
              CalcKeypad(
                onKey: _pressKey,
                onConfirm: _save,
                canConfirm: _canSave && !_saving,
                keyHeight: keyH,
              ),
            ],
          ],
        );
      },
    );

    // 键盘弹出 / 收起时面板整体让位。
    //
    // 这里**故意不加 AnimatedPadding / AnimatedSize**：`viewInsets` 是键盘
    // 升起过程中逐帧变化的，每变一帧就会重建一次。加了 180ms 动画，等于每帧
    // 都把动画重新起步，面板永远追不上键盘 —— 表现就是「先僵硬地缩一下、
    // 卡半拍、再突然跳到终点」，观感正是「关掉一页又开了一页」。
    //
    // 直接跟随 viewInsets 反而最顺：键盘推多少，面板就让多少，两者同帧同步。
    // 代价是「切换收支导致模板条出现/消失」时高度是突变的，但那一下本来也
    // 不该有慢动作。
    // 布局完成之后才知道有没有溢出，所以滚动提示只能在下一帧同步。
    // [_syncScrollHint] 自带「值没变就不 setState」，不会打转。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollHint());

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: ClipRRect(
          // 背景由面板自己画（sheet 本身是透明的），这样让给键盘的那段
          // 留白不会跟着变白
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
          child: Container(color: C.bg, child: body),
        ),
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
                        color: on ? C.bg.withValues(alpha: 0.72) : C.ink3,
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
  const _AmountDisplay({required this.input});

  final String input;

  @override
  Widget build(BuildContext context) {
    final cents = Calc.cents(input);
    // 收支由上方切换表示，这里不再画固定的 ± 前缀，也不画 ¥。
    // 只保留用户自己敲的负号 —— 那是「净额」信息，不能吞掉。
    final amountText = cents == null
        ? '0'
        : '${cents < 0 ? '-' : ''}${Fmt.money(cents.abs(), trimZero: true)}';

    return Padding(
      // 顶部多了一排模板，这里收一点，保证键盘在首屏里露全
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // 左边留给算式，纯数字时是空的
          Expanded(
            flex: 3,
            child: Text(
              Calc.hasOperator(input) ? Calc.pretty(input) : '',
              style: T.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: S.sm),
          // 数字靠右贴边；太长时等比缩小，不折行也不溢出
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(amountText, style: T.hero.copyWith(fontSize: 44)),
              ),
            ),
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
      // 上面紧挨着分隔线，留 8 的呼吸位；下面接备注框，收 8 免得两处叠成一大块
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.sm),
      child: Row(
        children: [
          Expanded(
            child: _Chip(
              key: const ValueKey('record_date_chip'),
              icon: 'rec',
              label: Fmt.friendly(date),
              onTap: onPickDate,
            ),
          ),
          const SizedBox(width: S.md),
          Expanded(
            child: _Chip(
              key: const ValueKey('record_account_chip'),
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
  const _Chip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
    required this.parent,
    required this.note,
    required this.onTap,
  });

  final Category? category;

  /// 选中的是子分类时，这里是它的一级
  final Category? parent;
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
          // 副标题说清楚「这笔落在哪一层」：选了子分类就带上一级名，
          // 只选到一级就明说未细分 —— 否则用户不知道自己记到了哪一层
          final hint = parent != null
              ? '${parent!.name} · 备注可不填'
              : '未细分 · 备注可不填';
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
                        text.isEmpty ? hint : text,
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

/// 分类详情区。
///
/// 两套呈现方式，分界线是「这条信息有多重要」：
/// - **折叠**（出行）：多数人懒得填出发地/目的地，常驻两行是白占高度，
///   收进「＋ 添加详情」，填过的会在标题后面显示 `家 → 公司` 摘要。
/// - **平铺**（人情 / 成长）：记了红包份子却不知道给谁，这条记录就没有价值，
///   所以对象和名称必须一眼可见、直接能填。
class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.fields,
    required this.folded,
    required this.open,
    required this.controllers,
    required this.focusNodes,
    required this.keys,
    required this.onToggle,
  });

  final List<TxnField> fields;
  final bool folded;
  final bool open;
  final Map<TxnField, TextEditingController> controllers;
  final Map<TxnField, FocusNode> focusNodes;
  final Map<TxnField, GlobalKey> keys;
  final VoidCallback onToggle;

  /// 折叠时标题右边那串 `家 → 公司`，没填就空着
  String get _summary {
    final from = controllers[TxnField.from]!.text.trim();
    final to = controllers[TxnField.to]!.text.trim();
    if (from.isEmpty && to.isEmpty) return '';
    return '${from.isEmpty ? '—' : from} → ${to.isEmpty ? '—' : to}';
  }

  List<Widget> get _rows => [
    for (final f in fields)
      Padding(
        padding: const EdgeInsets.only(bottom: S.sm),
        child: _DetailInput(
          key: keys[f],
          field: f,
          controller: controllers[f]!,
          focusNode: focusNodes[f]!,
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    if (!folded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, 2),
        child: Column(children: _rows),
      );
    }
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.sm),
            child: Row(
              children: [
                Text(
                  open ? '收起详情' : '＋ 添加详情',
                  style: T.caption.copyWith(color: C.ink2),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text(
                    open ? '' : _summary,
                    style: T.caption.copyWith(color: C.ink3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: C.ink4,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xs),
            child: Column(children: _rows),
          ),
      ],
    );
  }
}

/// 一行「标签 + 输入框」。标签宽度固定，几个框的输入起点才会对齐。
class _DetailInput extends StatelessWidget {
  const _DetailInput({
    super.key,
    required this.field,
    required this.controller,
    required this.focusNode,
  });

  final TxnField field;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(field.label, style: T.caption.copyWith(color: C.ink2)),
        ),
        const SizedBox(width: S.sm),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: T.body2.copyWith(color: C.ink),
            maxLength: 30,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => focusNode.unfocus(),
            onTapOutside: (_) => focusNode.unfocus(),
            inputFormatters: [LengthLimitingTextInputFormatter(30)],
            decoration: InputDecoration(
              counterText: '',
              hintText: field.hint,
              hintStyle: T.caption.copyWith(color: C.ink4),
              filled: true,
              fillColor: C.bg2,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: 9,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// 系统键盘上的「完成」：收起输入法，把数字键盘和确认键唤回来
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.md),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: T.body,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        onSubmitted: onSubmitted,
        // 点空白处也算写完了：不再要求用户专门去点一颗「完成」
        onTapOutside: (_) => focusNode?.unfocus(),
        onEditingComplete: () => focusNode?.unfocus(),
        inputFormatters: [LengthLimitingTextInputFormatter(60)],
        decoration: InputDecoration(
          counterText: '',
          hintText: '备注（可不填）',
          hintStyle: T.body2.copyWith(color: C.ink4),
          filled: true,
          fillColor: C.bg2,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: S.md,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.md),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// 「这笔算 X 起的这期」——手动抬期的唯一入口。
///
/// 为什么必须有这个开关：R1 抬期是**自动**的，用户看不见发生了什么。
/// 10 号发的工资悄悄算进 15 号那期，用户会以为账错了。给一行小字 + 拨动开关，
/// 让它可见、可改、可复原（不写设置，只作用于当前这一笔）。
class _LiftRow extends StatelessWidget {
  const _LiftRow({
    required this.on,
    required this.periodLabel,
    required this.onChanged,
  });

  final bool on;
  final String periodLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '这笔算 $periodLabel 起的这期',
              style: T.caption.copyWith(color: C.ink2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!on),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(3),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on ? C.ink : C.line,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: C.bg,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
