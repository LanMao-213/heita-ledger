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
part 'record_sheet/layout.dart';
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
    // 编辑时听原记录的，新建时听「默认支出账户」——见 [_initialAccountId]
    _accountId = e?.accountId ?? _initialAccountId();
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

  /// 新建一笔时的默认账户（编辑态不走这里，编辑听原记录的）。
  ///
  /// 顺序：**用户设的默认支出账户 → 列表第一个**。
  ///
  /// 为什么拿之前要先验证：默认账户存的是 id 快照，账户被删掉之后它就是一个
  /// 指不到任何账户的死引用。直接拿来用，新记录会挂在不存在账户上 ——
  /// 明细里那笔解析不出账户名，账户余额也不会变，看起来像「记账丢了」。
  /// 停用的账户同理（`Store.accounts` 本来就不含停用的，这里再挡一次是
  /// 因为将来若把它改成含停用，这条兜底不用跟着改）。
  int? _initialAccountId() {
    final s = Store.i;
    final preferred = s.defaultExpenseAccountId;
    if (preferred != null) {
      final hit = s.accountOf(preferred);
      if (hit != null && !hit.archived) return hit.id;
    }
    return s.accounts.isEmpty ? null : s.accounts.first.id;
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
  /// 口径来自 [fieldsOfCat]：子分类按种子登记的字段来（公共交通/打车 → 地点两端，
  /// 红包份子 → 对象…）；一级分类只有在 [kParentFieldSpecs] 里登记过才算 ——
  /// 「出行 / 不细分」必须有出发地和目的地，否则用户想记「从家到公司」时
  /// 连入口都没有（2026-10-28 反馈）。用户自建的分类不在任何一张表里 = 不要
  /// 详情字段，猜不出的字段宁可不显示，也别给每个分类都塞四个框。
  List<TxnField> get _fields =>
      fieldsOfCat(Store.i.categoryOf(_categoryId)?.name);

  /// 这个分类的详情要不要默认折叠（只看出行的地点两端）
  bool get _folded =>
      kFoldedSubs.contains(Store.i.categoryOf(_categoryId)?.name);

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
    // 系统输入法占掉的高度。面板底边要跟着它走。
    final keyboard = media.viewInsets.bottom;
    // 没有输入法时，屏幕底部还有手势条 / 三键导航栏。它不体现在 size 里，
    // 面板必须自己让出来 —— 之前漏了这一步，真机上键盘最后一排（0 / . / 确认）
    // 正好被手势条压掉一条，看起来就是「键盘尺寸不对」。
    final bottomInset = keyboard > media.viewPadding.bottom
        ? keyboard
        : media.viewPadding.bottom;
    // 面板底边始终贴着「键盘或手势条」的上沿，高度按内容算（封顶 maxH）。
    //
    // 这个高度策略被推翻重写过两次，两次的教训是同一条：**别让高度和底边各走各的**。
    //
    // - 1.4.x 写备注时把面板钉在 0.9 屏高、且不让位给输入法（`reserved = 0`）。
    //   面板一动不动，但内容顶对齐，多出来的高度全堆在备注框下面被键盘盖住 ——
    //   2026-10-28 用户的原话：「输入备注时，下方与键盘之间留白过高」。
    // - 那次还把「钉住」写成只在 `typingNote` 时生效：失焦那一帧 minHeight
    //   从满高掉到 0，面板当场塌 380dp，紧接着数字键盘用 150ms 长回来又把内容
    //   顶回去 —— 一帧下坠 + 一段回升，就是「返回输入金额时界面抽搐一下」。
    //
    // 现在两条都归零：底边跟随 viewInsets，高度只由内容决定，数字键盘的让位
    // 交给 record_sheet/layout.dart 那条「1:1 被顶出去」的规则。三者一起，面板顶边
    // 在键盘升起的整个过程里基本不动（见测试 `record_note_layout_test`）。
    final reserved = bottomInset;
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
          // 高度就按内容来。**不要**给 minHeight 钉一个「满高」：那正是
          // 「备注下面空 100dp + 返回时抽搐」的来源，理由见上面那段。
        ),
        child: ClipRRect(
          // 背景由面板自己画（sheet 本身是透明的），这样让给键盘的那段
          // 留白不会跟着变白
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
          // 面板面用卡面（纯白），不是页面底（纸白）：底与面同色会糊成一片
          child: Container(
            color: C.cardBg,
            child: _sheetBody(context, keyboard: keyboard),
          ),
        ),
      ),
    );
  }

  /// 面板主体：头部 → 模板条 → 模式页签 → 金额 → 可滚动信息区 → 数字键盘。
  ///
  /// 单独抽出来，是为了让 [build] 只剩「让位计算 + 外壳」这十几行 —— 那部分每个
  /// 数值（`reserved` / `maxH`）背后都是一段真机上的踩坑记录，混在三百行的
  /// widget 树里根本读不出来，改一行要靠猜。
  ///
  /// `keyboard` 是上面量到的输入法高度，往下传而不重算 —— 重算等于把同一件事
  /// 写成两份。键高也在这里算，因为它要和键盘剩余高度对得上（见 `solveKeypadSlot`）。
  Widget _sheetBody(BuildContext context, {required double keyboard}) {
    // 键高按**屏幕高度**算，不按面板的可用高度。
    //
    // 面板的可用高度会随输入法逐帧变化：键盘每升一帧，键高就变一次，整块键盘
    // 跟着缩。而「键盘被输入法 1:1 顶出去」那条规则要求键盘的自然高度是**常量**
    // —— 否则顶出去的量和长回来的量对不上，面板顶边就会在这场动画里上下跳
    // （1.5.0 修 bug 3 时实测：顶边 141 → 221 → 165）。
    //
    // 屏幕高度对同一台机器是常量，所以键高在一次录入里不会变，正是想要的。
    // 56 是设计值（46 → 52 → 56，键偏矮不好按）；只有矮屏才往下收 ——
    // 宁可键矮一点，也不要裁掉「确认」。有分类详情时上限压到 52：详情区要
    // 多吃 40~90 的高度，而信息区里的「日期 / 账户」不能被挤出可视区。
    //
    // **不能再看 `_detailsOpen`**：之前写成「展开详情就再压 4dp」，结果点一下
    // 「添加详情」，整块键盘瞬间矮 20dp —— 用户的原话是「打开详情，小键盘抖了
    // 一下」。键盘是这一屏最稳的东西：手指正在上面按，它的尺寸不该因为上面
    // 内容多少而变；内容变高由滚动区吸收，不是压缩键盘。
    final keyH = ((MediaQuery.sizeOf(context).height - 380) / 5).clamp(
      38.0,
      _fields.isEmpty ? 56.0 : 52.0,
    );
    // 数字键盘还剩多高（0 = 已经完全让给输入法）。见 record_sheet/layout.dart。
    //
    // **这里只调纯函数，不做任何分段判断。**「剩不到一排键就整块收掉」那条规则
    // 曾经住在这里，它是面板顶边在整段输入法动画里唯一的分段点 —— 跨过它的
    // 那一帧顶边会跳（实测 177.5 → 217.5）。碎边是视觉问题，交给下面的渐隐，
    // 布局层必须保持连续。
    final slot = solveKeypadSlot(
      keypadNaturalHeight: CalcKeypad.heightOf(keyH),
      keyboardInset: keyboard,
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
                // 底部只留一点呼吸位：面板自己已经让开键盘了（见 [build] 里
                // 的 `reserved`），这里再补一份「键盘高度」的空白，屏幕上就是
                // 「备注框下面空一大截」。1.4.x 写的是 `keyboard + S.sm`，
                // 那是因为当时面板不给自己让位 —— 两处补偿不能都留着。
                // 展开详情时多留一点：最后一个字段的边框才不会贴着键盘上沿。
                padding: EdgeInsets.only(
                  bottom: _detailsOpen ? S.md : S.sm,
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
        // 数字键盘给自己让位的方式：**被输入法 1:1 顶出去**，而不是自己「收起来」。
        //
        // 为什么不是 AnimatedSize 收起：那是一个 150ms 的独立动画，和输入法
        // 升起（0.2~0.3s、逐帧变化）永远对不齐。动画快了，键盘先消失、面板
        // 当场变矮；动画慢了，键盘赖着不走、可滚动区被压成 0。两边的观感
        // 都是「面板跳了一下」——1.4.1 与 1.5.0 各踩过一次。
        //
        // 现在让位量直接取 `键盘高度`：输入法升多少，键盘就被剪掉多少。
        // 面板高度 = 内容 + 剩下的那截键盘，底边 = 键盘上沿，于是
        //
        //     顶边 = (屏高 − 键盘) − (内容 + 键盘高 − 键盘) = 常数
        //
        // 键盘升起的整个过程里面板顶边一动不动，只有键盘块在缩短 ——
        // 看起来就是「输入法从底下把键盘顶上去」，正是手指底下的物理事实。
        // 输入法比键盘还高（少数机型）时它自然变成 0，不需要额外分支。
        //
        // 1.6.0 修掉了这条恒等式上唯一的分段点（`left < 40 ? 0 : left`）。
        // 算式与全部推导见 record_sheet/layout.dart 的文件头；这里只剩「按算出来
        // 的槽高摆一个框」，不再有任何 if。
        //
        // 不给「完成」按钮：输入法自带的那颗 + 收起键盘，都是「写完了」。
        //
        // slot 归零时整块（含分隔线）都不出现，而不是留一个 0 高的空壳：
        // 「键盘已经让开了」在测试与读代码时都该是一个能直接判断的事实。
        if (slot.visible) ...[
          _hairline(context),
          SizedBox(
            // key 给测试用：键盘本身的 rect 永远是「自然高度」（它被自己的
            // 排版尺寸撑开、只是被外层剪掉），要量「还剩多少露在外面」只能量
            // 这个槽。
            key: const ValueKey('record_keypad_slot'),
            height: slot.slot,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  // 键盘按**自然高度**排一次版，再由外面这个 SizedBox 从下往上
                  // 剪掉：不这么做，键会为了挤进剩余空间而改高度（那就变成
                  // 又一次「小键盘抖了一下」）。
                  //
                  // 「从下往上剪」意味着露在外面的是键盘**顶部的几排**，
                  // 被剪断的那条边落在槽的**下沿**——也就是贴着输入法上沿的
                  // 那一排半截键。用户说的「键盘抖/画坏了」就是它。
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: slot.naturalHeight,
                    maxHeight: slot.naturalHeight,
                    child: CalcKeypad(
                      onKey: _pressKey,
                      onConfirm: _save,
                      canConfirm: _canSave && !_saving,
                      keyHeight: keyH,
                    ),
                  ),
                ),
                // 碎边渐隐：把被剪断的那条边溶进卡面。
                //
                // 为什么画在**下沿**而不是上沿：被剪的是下面那一排（键盘被
                // 输入法从底下顶出去），要溶的是贴着输入法的那一条。画在上沿
                // 只会让键盘看起来从内容区里长出来，半截键照样贴在输入法上，
                // 用户的抱怨一个字都没解决。
                //
                // 满键盘时 `shatterFade == 0`，这一层根本不出现 —— 「0 / . /
                // 确认」那排真键绝不能被溶掉。
                if (slot.shatterFade > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: slot.shatterFade,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey('record_keypad_shatter_fade'),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            // 终点是卡面，和 `_moreBelow` 同一条规则：
                            // 渐隐的终点必须是面板自己的面，否则暗一圈
                            colors: [C.cardBg.withValues(alpha: 0), C.cardBg],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
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
