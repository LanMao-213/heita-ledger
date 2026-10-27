import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/calc.dart';
import '../data/category_seed.dart';
import '../data/cycle.dart';
import '../data/models.dart';
import '../data/record_draft.dart';
import '../design/hairline.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../store.dart';
import 'common.dart';
import 'calc_keypad.dart';
import 'menu.dart';
import 'picker_wheels.dart';

part 'record_sheet/actions.dart';
part 'record_sheet/rows.dart';

/// 保存成功后带出来的信息，给「已记账 · 10-01 至 10-31」这类提示用。
///
/// 为什么要带期标签：这笔钱最后落在哪一期，是「工资抬期」「账单日不是 1 号」
/// 这些规则决定的，用户看不见。1.4.2 修掉「记完在明细里找不到」之后还差一句
/// 话告诉他**记到哪去了** —— 否则跳期只是「界面自己跳了一下」。
class RecordOutcome {
  const RecordOutcome({required this.periodStart, required this.periodLabel});

  /// 这笔的归属期首日（`YYYY-MM-DD`），和 `txn.period_start` 同一口径
  final String periodStart;

  /// 归属期的可读区间，如 `10-01 至 10-31`
  final String periodLabel;
}

/// 打开「记一笔」面板。传入 [editing] 则为编辑模式。
/// 返回 null 表示取消；非 null 表示保存成功，并带上这笔落在哪一期。
Future<RecordOutcome?> showRecordSheet(BuildContext context, {Txn? editing}) {
  return showModalBottomSheet<RecordOutcome>(
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
  /// 面板顶部的四段：支出 / 收入 / 借出 / 借入。
  ///
  /// 借出/借入**不扩 `TxnType`**：扩了要改统计、筛选、Excel、明细分组里
  /// 所有按类型分支的地方。这里只多两个录入模式，保存时走 `Repo.createDebt`，
  /// 流水类型按借贷方向定（借出=支出、借入=收入）。
  late _RecordMode _mode;
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

  // ---- 借贷模式专用 ----

  /// 对方（谁借给我 / 我借给谁），借出借入必填
  final _counterparty = TextEditingController();
  final _counterpartyFocus = FocusNode();

  /// 约定还款日，可空
  String? _dueDate;

  /// 借入时是否算进本期可用。借出恒为 false（用户口径：借出不算预算）
  bool _countInBudget = false;

  bool get _isLending => _mode.isLending;

  /// 借出/借入对应的流水类型：借出是钱出去（支出），借入是钱进来（收入）
  TxnType get _type =>
      (_mode == _RecordMode.income || _mode == _RecordMode.lendIn)
      ? TxnType.income
      : TxnType.expense;

  /// 「这笔算下一期」的手动开关。null = 跟着分类白名单走默认值。
  /// 白名单只给初值，最终值必须能听用户的（设计 §5.2）。
  bool? _liftOverride;

  bool get _isEdit => widget.editing != null;

  /// 只有收入、且这笔真的落在「同月账单日之前」时，抬期开关才有意义
  bool get _showLift =>
      !_isLending && _type.isIncome && liftable(_date, Store.i.cycleStartDay);

  /// 当前开关状态：手动拨过就听手动的，否则按分类白名单
  bool get _liftOn =>
      _liftOverride ??
      (_categoryId != null && Store.i.liftableCatIds.contains(_categoryId));

  @override
  void initState() {
    super.initState();
    // 备注框拿到/失去焦点时要重画：焦点在备注里时数字键盘要让位给系统输入法
    _noteFocus.addListener(_onTextFocusChanged);
    _counterpartyFocus.addListener(_onTextFocusChanged);
    // 对方是必填项：输入时要重建面板，确认键才会从灰变实
    _counterparty.addListener(_onCounterpartyChanged);
    _scroll.addListener(_syncScrollHint);
    final s = Store.i;
    final e = widget.editing;
    _mode = (e?.type == TxnType.income)
        ? _RecordMode.income
        : _RecordMode.expense;
    _categoryId = e?.categoryId;
    _accountId =
        e?.accountId ?? (s.accounts.isEmpty ? null : s.accounts.first.id);
    _date = e?.date ?? Fmt.today();
    _note = TextEditingController(text: e?.note ?? '');
    if (e != null) {
      _amountInput = Fmt.input(e.amountCents);
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

  /// 借贷必须填对方、金额大于 0 —— 「谁欠我 0 元」这种记录没有意义。
  /// 其余情况沿用原规则：只要算式能算出数就能存。
  bool get _canSave {
    final cents = _amountCents;
    if (cents == null) return false;
    if (_isLending) {
      return cents > 0 && _counterparty.text.trim().isNotEmpty;
    }
    return true;
  }

  @override
  void dispose() {
    _noteFocus.removeListener(_onTextFocusChanged);
    _note.dispose();
    _noteFocus.dispose();
    _counterpartyFocus
      ..removeListener(_onTextFocusChanged)
      ..dispose();
    _counterparty
      ..removeListener(_onCounterpartyChanged)
      ..dispose();
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

  /// 改完表单状态后触发重建。
  ///
  /// 行为方法都在 `record_sheet/actions.dart` 的 extension 里，而
  /// `State.setState` 带 `@protected` —— extension 不算子类，直接调会被
  /// `invalid_use_of_protected_member` 拦下（项目门禁 `--fatal-infos`，
  /// 这是硬错误）。这里是唯一一处转发，语义与 `setState` 相同：先跑改动，
  /// 再标记本帧重建。
  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});

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
      _noteFocus.hasFocus ||
      _counterpartyFocus.hasFocus ||
      _detailFocus.values.any((f) => f.hasFocus);

  /// 当前有焦点的输入框位置，没焦点返回 null
  GlobalKey? get _focusedKey {
    if (_noteFocus.hasFocus) return _noteKey;
    for (final e in _detailFocus.entries) {
      if (e.value.hasFocus) return _detailKey[e.key];
    }
    return null;
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
    // 备注框一拿到焦点，数字键盘立刻收起来 —— **不等输入法真的升起**。
    //
    // 旧写法是 `keyboard > 0 && _hasTextFocus`，看着更"精确"，但真机上输入法
    // 从 0 升到全高有 3~5 帧：这几帧里面板正被 bottomInset 顶着往上走，290dp 的
    // 数字键盘还赖在下面，可滚动区被压成 0，备注框先被挤没再弹回来 ——
    // 用户的原话是「点一下备注卡片，面板重新打开了一次」。改成跟焦点走之后，
    // 顺序变成「数字键盘先收起 → 输入法再升起」，全程只有一个方向的位移。
    //
    // 只对**备注**用这个提前量：「借给谁」「出发地」这些填完还得接着按数字，
    // 键盘早收一拍反而碍事，它们仍按「输入法真的占了下半屏」判断。
    final typingNote = _noteFocus.hasFocus || (keyboard > 0 && _hasTextFocus);
    // 写备注时把面板「钉住」。
    //
    // 旧行为的三个动作叠在一起：数字键盘收起（-270）、面板跟着塌、
    // 系统键盘升起再把它顶上去 —— 看着就是「点一下备注，面板缩回去了」。
    // 现在让它一动不动：面板保持满高、不给系统键盘让位，由键盘直接盖住
    // 原本属于数字键盘的那块。用户看到的是「键盘换了一个」，不是布局重排。
    final reserved = typingNote ? 0.0 : bottomInset;
    // 0.90：顶部多了「最近模板」那排之后，0.88 会把备注框切掉一条。
    final maxH = (media.size.height - reserved) * 0.90;

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
      padding: EdgeInsets.only(bottom: reserved),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxH,
          // 钉住高度：数字键盘收起时若让面板跟着塌，就是那一下「缩回去」
          minHeight: typingNote ? maxH : 0,
        ),
        child: ClipRRect(
          // 背景由面板自己画（sheet 本身是透明的），这样让给键盘的那段
          // 留白不会跟着变白
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
          // 面板面用卡面（纯白），不是页面底（纸白）：底与面同色会糊成一片
          child: Container(
            color: C.cardBg,
            child: _sheetBody(
              context,
              keyboard: keyboard,
              typingNote: typingNote,
            ),
          ),
        ),
      ),
    );
  }

  /// 面板主体：头部 → 模板条 → 模式页签 → 金额 → 可滚动信息区 → 数字键盘。
  ///
  /// 单独抽出来，是为了让 [build] 只剩「让位计算 + 外壳」这十几行 —— 那部分每个
  /// 数值（`reserved` / `maxH` / `typingNote`）背后都是一段真机上的踩坑记录，混在
  /// 三百行的 widget 树里根本读不出来，改一行要靠猜。
  ///
  /// 键高要等 layout 结果才知道，所以整块仍留在 `LayoutBuilder` 里。`keyboard` 与
  /// `typingNote` 是上面算好的让位结论，往下传而不重算 —— 重算等于把「输入法升起
  /// 的那 3~5 帧」那段判断写成两份，迟早走岔。
  Widget _sheetBody(
    BuildContext context, {
    required double keyboard,
    required bool typingNote,
  }) {
    return LayoutBuilder(
      builder: (context, box) {
        // 键高跟着可用高度走：先给头部 / 金额 / 信息区留 380，剩下 5 排均分。
        // 56 是设计值（46 → 52 → 56，键偏矮不好按），只有矮屏才往下收 ——
        // 宁可键矮一点，也不要裁掉「确认」。
        //
        // 有分类详情时上限压到 52：详情区要多吃 40~90 的高度，而信息区里
        // 的「日期 / 账户」不能因为多填两个框就被挤出可视区。
        //
        // **不能再看 `_detailsOpen`**。之前这里写成
        // `_fields.isEmpty ? 56 : (_detailsOpen ? 48 : 52)`，想着「展开后最挤，
        // 再压 4dp 腾地方」。结果点一下「添加详情」，5 排键每排矮 4dp、整块
        // 键盘瞬间少 20dp —— 用户的原话是「打开详情，小键盘抖了一下」。
        //
        // 键盘是这一屏最稳的东西：手指正在上面按，它的尺寸不该因为上面内容
        // 多少而变。内容变高由滚动区吸收，不是压缩键盘。
        // 只保留「有没有详情字段」这一层结构差异（56 / 52）。
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
                      // 取消：弹出 null，调用方按「没保存」处理
                      onPressed: () => Navigator.pop(context),
                      child: Text('取消', style: TextStyle(color: C.ink2)),
                    )
                  : TextButton(
                      onPressed: _saveAsTemplate,
                      child: Text(
                        '存为模板',
                        style: T.body2,
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
            _ModeTabs(
              value: _mode,
              onChanged: (m) {
                setState(() {
                  _mode = m;
                  // 切换模式后原分类不再适用，重置到第一个；模板也随之失效
                  _categoryId = _firstCategoryId();
                  _applied = null;
                  // 支出侧的详情字段（出发地/对象）不该带到收入侧
                  _pruneDetails();
                  // 借贷不带分类与详情；「计入预算」只在借入时有意义
                  if (m.isLending) {
                    _detailsOpen = false;
                    _countInBudget = false;
                  }
                });
              },
            ),
            _AmountDisplay(input: _amountInput),
            _hairline(context),
            // 用 Flexible 而不是 Expanded：内容不满一屏时面板贴着内容收起来，
            // 否则备注框和键盘之间会空出一大块（模板少的时候尤其明显）
            Flexible(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scroll,
                    // 写备注时面板不让位，被键盘盖住的那段要靠底部留白补，
                    // 否则备注框「滚到底」也还在键盘底下
                    padding: EdgeInsets.only(
                      bottom: typingNote
                          ? keyboard + S.sm
                          // 展开详情时多留一点：键盘不再为内容让位，
                          // 最后一个字段的边框才不会贴着键盘上沿
                          : (_detailsOpen ? S.md : S.sm),
                    ),
                    child: Column(
                      children: [
                        if (_isLending) ...[
                          _DebtFields(
                            direction: _mode.direction,
                            counterparty: _counterparty,
                            counterpartyFocus: _counterpartyFocus,
                            dueDate: _dueDate,
                            onPickDue: _pickDueDate,
                            countInBudget: _countInBudget,
                            onCountChanged: (v) =>
                                setState(() => _countInBudget = v),
                          ),
                          _hairline(context),
                          _NoteField(
                            key: _noteKey,
                            controller: _note,
                            focusNode: _noteFocus,
                            onSubmitted: (_) => _noteFocus.unfocus(),
                          ),
                          _hairline(context),
                        ] else ...[
                          _CategoryNoteRow(
                            category: Store.i.categoryOf(_categoryId),
                            parent: Store.i.parentOf(
                              Store.i.categoryOf(_categoryId),
                            ),
                            note: _note,
                            onTap: _pickCategory,
                          ),
                          _hairline(context),
                        ],
                        // 有详情字段时，备注框提到分类下面（它不是必填项，
                        // 藏起来用户就当它不存在了）。
                        if (!_isLending && _fields.isNotEmpty) ...[
                          _NoteField(
                            key: _noteKey,
                            controller: _note,
                            focusNode: _noteFocus,
                            onSubmitted: (_) => _noteFocus.unfocus(),
                          ),
                          _hairline(context),
                        ],
                        // 日期 / 账户**必须在详情区前面**。
                        // 原来顺序是「备注 → 详情 → 日期账户」，一展开详情，
                        // 这两行就被顶到可视区外面 —— 而它们比详情重要得多
                        // （出行的「出发地」可以空着，日期和账户不能空）。
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
                        // 详情区放最后：它展开时只会往下长，不会把上面任何
                        // 一行挤走。
                        if (!_isLending && _fields.isNotEmpty) ...[
                          _hairline(context),
                          _DetailBlock(
                            fields: _fields,
                            folded: _folded,
                            open: _detailsOpen,
                            controllers: _detailCtl,
                            focusNodes: _detailFocus,
                            keys: _detailKey,
                            onToggle: () {
                              setState(() => _detailsOpen = !_detailsOpen);
                              if (_detailsOpen) {
                                // 展开后滚到底：否则新出现的字段会落在可视区
                                // 下沿之外，用户以为「点了没反应」。
                                //
                                // 套两层 postFrame：第一帧 detail 区的尺寸还没
                                // 进 maxScrollExtent，这时 animateTo 拿到的是
                                // 旧值（往往是 0），等于没滚。
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!_scroll.hasClients) return;
                                      _scroll.animateTo(
                                        _scroll.position.maxScrollExtent,
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        curve: Curves.easeOutCubic,
                                      );
                                    });
                                  },
                                );
                              }
                            },
                          ),
                        ],
                        // 借贷模式已经在上面单独放了备注框，这里不能再放一个 ——
                        // 两处都用同一个 GlobalKey，会在切换模式时报重复 key
                        if (!_isLending && _fields.isEmpty)
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
                              // 渐隐的终点必须是面板自己的面（卡面），
                              // 不是页面底 —— 否则暗一圈，像没画完
                              colors: [C.cardBg.withValues(alpha: 0), C.cardBg],
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
            //
            // 让位要**滑下去**，不能直接抽走：键盘升起时面板整体被顶高，如果
            // 这 270dp 在同一帧里消失，画面就是「先缩一下、再跳一下」——
            // 用户的原话是「点备注像重新打开了一次面板」。
            // 只给这一块加动画，整个面板仍然逐帧跟随 viewInsets：键盘高度是
            // 连续变化的，给面板加动画会让它永远追不上键盘（见下面的长注释）。
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: typingNote
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _hairline(context),
                        CalcKeypad(
                          onKey: _pressKey,
                          onConfirm: _save,
                          canConfirm: _canSave && !_saving,
                          keyHeight: keyH,
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 1 物理像素的分隔线。
///
/// `Divider` 的三个参数在这个文件里出现七次，每次都是同一组值。重复七遍的代价不是
/// 多敲几个字，而是「改分隔线颜色」要改七处 —— 漏一处就只有那一条颜色不对，肉眼
/// 极难发现。
Widget _hairline(BuildContext context) =>
    Divider(height: 1, thickness: hairlineOf(context), color: C.line);
