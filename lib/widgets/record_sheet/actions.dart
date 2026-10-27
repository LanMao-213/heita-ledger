part of '../record_sheet.dart';

// ---------------------------------------------------------------------------
// 「记一笔」的行为方法：滚到底提示 / 改分类 / 按键盘 / 选日期账户 / 存模板 / 落库
// ---------------------------------------------------------------------------
//
// 与 `store/actions.dart` 同一个理由：把「一次用户动作」的完整语义收在一处，
// 不和布局混着读。`_RecordSheetState` 那边只留字段、派生 getter、两个生命周期
// 方法，剩下的就是 `build` / `_sheetBody` 两块布局。
//
// 为什么用 extension 而不是在 `part` 里再写一个类：这些方法要读写状态类的 15 个
// 私有字段（`_amountInput`、`_note`、`_detailCtl`、`_liftOverride`…），同一个
// library 的 extension 能直接碰到，不必造一层中转，也不必把字段改成公开。
//
// 一个必须交代的限制：`State.setState` 带 `@protected`，而 extension 不算
// `State` 的子类 —— 直接调用会被 `invalid_use_of_protected_member` 拦下。
// 本项目门禁是 `--fatal-infos`，所以这是硬错误而不是提示。因此这里统一改用
// `_rebuild()`：它在状态类里只是一行转发，语义与 `setState` 完全相同
// （先跑传入的改动，再标记本帧重建）。
//
// `widget` / `context` / `mounted` 三个 `State` 成员在 extension 里可以照常读，
// 这几个确实没有 `@protected`，不用转发。

extension _RecordSheetActions on _RecordSheetState {
  /// 同步「下面还有内容」的状态。只在真的变化时 setState，
  /// 否则会变成「重建 → 布局 → 又重建」的死循环。
  void _syncScrollHint() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final more = p.maxScrollExtent - p.pixels > 2;
    if (more != _moreBelow) _rebuild(() => _moreBelow = more);
  }

  void _onTextFocusChanged() {
    if (!mounted) return;
    _rebuild(() {});
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

  /// 对方输入变化：只用来刷新「确认键是否可用」，不做别的
  void _onCounterpartyChanged() {
    if (mounted) _rebuild(() {});
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
    _rebuild(() {
      _categoryId = pick.txnCategoryId;
      _pruneDetails();
    });
  }

  /// 分类一换，详情字段的语义就变了 —— 把新分类用不到的字段就地清空。
  ///
  /// 规则收在 [pruneDetails]（纯函数，保存时也走它），这里只负责把结果写回控件。
  void _pruneDetails() {
    final kept = pruneDetails(Store.i.categoryOf(_categoryId)?.name, {
      for (final f in TxnField.values) f: _detailCtl[f]!.text,
    });
    for (final e in kept.entries) {
      if (e.value.isEmpty) _detailCtl[e.key]!.clear();
    }
    // 新分类的详情区默认收起；留着展开状态会突然多出一片空输入框
    _detailsOpen = false;
  }

  /// 按键只是对表达式字符串做一次变换，规则都收在 Calc.press 里
  void _pressKey(String k) {
    _rebuild(() => _amountInput = Calc.press(_amountInput, k));
  }

  /// 点模板 = 把模板里的东西一次性填进来。此时还不算「用了一次」，
  /// 只有真的保存成功才累加使用次数 —— 否则用户点开看看就把统计弄脏了。
  void _applyTemplate(TxnTemplate t) {
    _rebuild(() {
      _applied = t;
      if (t.type != TxnType.transfer) {
        _mode = t.type == TxnType.income
            ? _RecordMode.income
            : _RecordMode.expense;
        _categoryId = t.categoryId ?? _firstCategoryId();
      }
      if (t.accountId != null) _accountId = t.accountId;
      if (t.hasAmount) _amountInput = Fmt.input(t.amountCents);
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

    final ok = await showAppDialog<bool>(
      context: context,
      title: '存为模板',
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: 8,
        style: T.body,
        decoration: const InputDecoration(
          hintText: '模板名称',
          counterText: '',
        ),
      ),
      actions: const [
        DialogAction(label: '取消', value: false),
        DialogAction(label: '保存', value: true, strong: true),
      ],
    );

    final name = ctl.text.trim();
    ctl.dispose();
    if (ok != true) return;

    await Store.i.saveTemplate(
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
    if (!mounted) return;
    _rebuild(() {}); // 让顶部那排模板立刻带上新的
    showToast(context, '已存为模板');
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    _rebuild(() => _saving = true);
    final cents = _amountCents!;

    final store = Store.i;
    final note = _note.text.trim();
    // 用了模板就记在账目上；没用但内容跟某个模板一模一样，也算它一次
    final tplId = _applied?.id ?? _matchingTemplate()?.id;

    // 只写**当前分类用得到**的字段（规则见 [pruneDetails]）。同一组字段的场景
    // （公共交通 ⇄ 打车）照旧带上，中间不该丢一次；但换成「书籍」时，控件里
    // 残留的出发地必须丢掉 —— 否则界面上看不见的值会跟着写进库里。
    final detailValues = pruneDetails(Store.i.categoryOf(_categoryId)?.name, {
      for (final f in TxnField.values) f: _detailCtl[f]!.text,
    });

    // 表单 → 草稿：拼 Txn / 判分支的规则都在 `RecordDraft` 里（可单测）。
    // 这里只负责「把界面上的东西读出来」，不再写业务判断。
    final draft = RecordDraft(
      ledgerId: store.ledgerId,
      type: _type,
      // 借贷恒为正：方向由 type 表示，不靠符号
      amountCents: _isLending ? cents.abs() : cents,
      date: _date,
      accountId: _accountId,
      categoryId: _categoryId,
      note: note,
      details: detailValues,
      // 编辑时不走借贷路径：对方与应还日属于「往来」，要改去往来详情
      debt: (!_isEdit && _isLending)
          ? Debt(
              id: 0,
              ledgerId: store.ledgerId,
              direction: _mode.direction,
              counterparty: _counterparty.text.trim(),
              amountCents: cents.abs(),
              date: _date,
              accountId: _accountId,
              dueDate: _dueDate,
              // 借出恒不计预算；借入按开关
              countInBudget: _mode == _RecordMode.lendIn && _countInBudget,
              note: note,
            )
          : null,
      editing: widget.editing,
      templateId: tplId,
    );

    try {
      final String periodStart;
      switch (draft.action) {
        case RecordAction.lend:
          periodStart = await store.addDebt(draft.debt!, draft.toTxn());
        case RecordAction.update:
          // 编辑走原地刷新（不跳期）：用户正在看的就是那一行
          await store.updateTxn(
            draft.editing!,
            draft.toTxn(),
            liftToNext: _liftOverride,
          );
          // 提示文案仍要说「这笔在哪一期」；编辑不改归属期，按当前日期算即可
          periodStart = periodStartOf(
            _date,
            store.cycleStartDay,
            liftToNext: _liftOn,
          );
        case RecordAction.insert:
          // 归属期由 `Store.addTxn` 返回（内部走 `Repo.periodFor`：抬期白名单
          // + 用户手动开关），面板不再按自己的规则算第二遍。
          periodStart = await store.addTxn(
            draft.toTxn(),
            liftToNext: _liftOverride,
            touchTemplateId: tplId,
          );
      }
      if (!mounted) return;
      Navigator.pop(context, _outcomeOf(periodStart));
    } catch (err) {
      if (!mounted) return;
      _rebuild(() => _saving = false);
      showToast(context, '保存失败：$err');
    }
  }

  /// 归属期首日 → 带区间文案的结果对象（`10-01 至 10-31`）
  RecordOutcome _outcomeOf(String periodStart) {
    final (from, to) = cycleRange(
      DateTime.parse(periodStart),
      Store.i.cycleStartDay,
    );
    return RecordOutcome(
      periodStart: periodStart,
      periodLabel: cycleLabel(from, to),
    );
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
    if (picked != null) _rebuild(() => _date = Fmt.date(picked));
  }

  /// 借出/借入的约定还款日。可以不选 —— 不选就是「没约好什么时候还」，
  /// 往来卡片会把它排在最后，不会当成逾期。
  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate != null
          ? (DateTime.tryParse(_dueDate!) ?? now)
          : now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10, 12, 31),
      locale: const Locale('zh', 'CN'),
    );
    if (picked == null || !mounted) return;
    _rebuild(() => _dueDate = Fmt.date(picked));
  }

  Future<void> _pickAccount() async {
    final s = Store.i;
    if (s.accounts.isEmpty) return;
    final picked = await showPickSheet<int>(
      context: context,
      title: '选择账户',
      options: [
        for (final a in s.accounts)
          PickOption(
            value: a.id,
            icon: a.icon,
            title: a.name,
            subtitle: Fmt.yuan(a.balanceCents),
          ),
      ],
      current: _accountId,
    );
    if (picked == null || !mounted) return;
    _rebuild(() => _accountId = picked);
  }
}
