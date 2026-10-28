part of '../record_sheet.dart';

// ---------------------------------------------------------------------------
// 面板里的展示型组件
// ---------------------------------------------------------------------------
//
// 全是 `StatelessWidget`（外加驱动顶部四段切换的 `_RecordMode`）：只收 props、
// 自己不管任何状态，变化一律由 `_RecordSheetState` 通过回调驱动。它们留在这份
// `part` 里而不是各自的 library，是因为只在「记一笔」这一处出现，并且要共用
// 私有类型（`_RecordMode`、`_NoteField` 里的 `GlobalKey` 约定）—— 拆成独立
// library 就得为私有类型补一层公开转发，白付一层间接。
//
// 搬出来的原因只有一个：`record_sheet.dart` 原本 1627 行，把「状态机」和这堆
// 「行 / 块」堆在同一屏里，改 `_save` 要先滚过十几个 widget。这里没有任何业务
// 逻辑，是纯位移 —— 行为与拆分前逐字节相同，验证方式是截图对拍 0 差异。
//
// 顺序与原来一致：模板条 → 模式页签 → 借贷字段 → 金额 → 日期账户行 → 抬期行
// → 分类备注行 → 详情区 → 备注框。

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
              // 11 是个孤立值：模板胶囊和下面的日期 / 账户胶囊（_Chip，左右
              // S.md）是同屏并排的两种胶囊，收到 S.md 让它们的字边距同一档
              padding: const EdgeInsets.symmetric(horizontal: S.md),
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
                    style: T.caption.copyWith(
                      color: on ? C.bg : C.ink,
                      fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  if (t.hasAmount) ...[
                    const SizedBox(width: 6),
                    Text(
                      Fmt.yuan(t.amountCents),
                      style: T.overline.copyWith(
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

/// 录入模式：支出 / 收入 / 借出 / 借入。
///
/// 只存在于录入面板，**不污染 `TxnType`**：借出借入落库时仍是支出/收入流水，
/// 只是多挂一个 `debt_id`。扩枚举要改统计、筛选、Excel、明细分组里所有
/// 按类型分支的地方，而这里只需要多两个模式。
enum _RecordMode {
  expense('支出'),
  income('收入'),
  lendOut('借出'),
  lendIn('借入');

  const _RecordMode(this.label);

  final String label;

  bool get isLending =>
      this == _RecordMode.lendOut || this == _RecordMode.lendIn;

  DebtDirection get direction =>
      this == _RecordMode.lendOut ? DebtDirection.lent : DebtDirection.borrowed;
}

/// 四段切换。视觉沿用 [SegTabs]（选中黑底白字），只是段数从 2 变 4。
class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.value, required this.onChanged});

  final _RecordMode value;
  final ValueChanged<_RecordMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(
          children: [
            for (final m in _RecordMode.values)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    // 2 是分段控件的固定内缩：轨道高 32 减去上下各 2 才是 28 的
                    // 胶囊高，改了胶囊就顶到轨道外，属于组件内部尺寸，不参与节奏
                    margin: const EdgeInsets.all(2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == m ? C.ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: Text(
                      m.label,
                      style: T.body2.copyWith(
                        fontWeight: FontWeight.w500,
                        color: value == m ? C.bg : C.ink2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 借贷模式的三个输入：对方（必填）、应还日（选填）、计入预算（仅借入）。
class _DebtFields extends StatelessWidget {
  const _DebtFields({
    required this.direction,
    required this.counterparty,
    required this.counterpartyFocus,
    required this.dueDate,
    required this.onPickDue,
    required this.countInBudget,
    required this.onCountChanged,
  });

  final DebtDirection direction;
  final TextEditingController counterparty;
  final FocusNode counterpartyFocus;
  final String? dueDate;
  final VoidCallback onPickDue;
  final bool countInBudget;
  final ValueChanged<bool> onCountChanged;

  @override
  Widget build(BuildContext context) {
    final isBorrow = direction == DebtDirection.borrowed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: counterparty,
            focusNode: counterpartyFocus,
            style: T.body,
            maxLength: 20,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => counterpartyFocus.unfocus(),
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
            decoration: InputDecoration(
              counterText: '',
              hintText: isBorrow ? '向谁借的（必填）' : '借给谁（必填）',
              hintStyle: T.body2.copyWith(color: C.ink3),
              filled: true,
              fillColor: C.bg2,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.md),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: S.md,
              ),
            ),
          ),
          const SizedBox(height: S.sm),
          Row(
            children: [
              Expanded(
                child: _Chip(
                  icon: 'rec',
                  label: dueDate == null ? '应还日（可不选）' : Fmt.friendly(dueDate!),
                  onTap: onPickDue,
                ),
              ),
              if (isBorrow) ...[
                const SizedBox(width: S.md),
                GestureDetector(
                  onTap: () => onCountChanged(!countInBudget),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: S.md),
                    decoration: BoxDecoration(
                      color: countInBudget ? C.ink : C.bg2,
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    child: Center(
                      child: Text(
                        '计入预算',
                        style: T.body2.copyWith(
                          color: countInBudget ? C.bg : C.ink2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.input});

  final String input;

  /// 金额区该显示什么。
  ///
  /// 用 [Calc.display]（「已经敲了什么」）而不是 [Calc.cents]（「能不能存」）：
  /// 后者对 `1.` / `12+` 一律返回 null，于是用户刚按完小数点、刚按完运算符，
  /// 屏幕上那个数就变回 0 —— 1.5.0 用户反馈的就是这一条。
  static String textOf(String input) {
    final d = Calc.display(input);
    if (d == null) return '0';
    // 收支由上方切换表示，这里不画固定的 ± 前缀，也不画 ¥。
    // 只保留用户自己敲的负号 —— 那是「净额」信息，不能吞掉。
    final sign = d.cents < 0 ? '-' : '';
    final body = Fmt.money(d.cents.abs(), trimZero: true);
    // 刚按完小数点：补一个「.」。值里已经带小数时（`1.5+2.`）不再补，
    // 否则会出现 `3.5.` 这种画不出的东西。
    final dot = d.trailingDot && !body.contains('.') ? '.' : '';
    return '$sign$body$dot';
  }

  @override
  Widget build(BuildContext context) {
    final amountText = textOf(input);

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
                // 刻意比 hero(34) 大一档：这一屏只有「金额」一个主角，
                // 键盘占了下半屏，数字不够大就会显得空。别收成 34。
                //
                // key 是给测试用的：键盘上也有 0-9，`find.text('0')` 会撞上
                // 「0」键，只有 key 能唯一定位这颗大数字。
                child: Text(
                  amountText,
                  key: const ValueKey('record_amount_value'),
                  style: T.hero.copyWith(fontSize: 44),
                ),
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
              // 记账时判断的是「这一笔算哪一天」，相对表达省一次心算
              label: Fmt.friendly(date, relative: true),
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
          // 副标题只说「这笔落在哪一层」：选了子分类就带上一级名，
          // 只选到一级就明说未细分 —— 否则用户不知道自己记到了哪一层。
          //
          // 不再缀「备注可不填」：下面就是备注框，自己写着「可不填」，
          // 在这一行重复一遍只是噪音；有备注时这里显示的就是备注本身。
          final hint = parent != null ? parent!.name : '未细分';
          return Padding(
            // 右侧原本收到 S.md(12)，是为了给行尾箭头再补 8 的间距 —— 结果
            // 箭头落在离边 20 的位置，比备注框 / 日期胶囊的右缘（16）多出 4，
            // 信息区整列右边对不齐。现在右侧归到 S.lg(16)，行尾那个 8 的
            // SizedBox 一并去掉，箭头正好压在 16 这条线上。
            padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.md),
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
                LineIcon(
                  'chevron_right',
                  size: 20,
                  color: C.ink3,
                ),
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
                LineIcon(
                  open ? 'chevron_up' : 'chevron_down',
                  size: 18,
                  color: C.ink3,
                ),
              ],
            ),
          ),
        ),
        // 展开/收起原来是 `if (open)` 的裸切换：点一下详情区「啪」地整块出现
        // 或消失，高度突变还会把下面的键盘顶一下。这里改成高度 + 淡出一起动。
        AnimatedExpand(
          expanded: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xs),
            child: Column(children: _rows),
          ),
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
              hintStyle: T.caption.copyWith(color: C.ink3),
              filled: true,
              fillColor: C.bg2,
              isDense: true,
              // 纵向 9 是 dense 输入框的固定内边距：和 isDense + body2(13px)
              // 一起决定这个框的高度，属于组件内部尺寸，不参与页面节奏
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
          hintStyle: T.body2.copyWith(color: C.ink3),
          filled: true,
          fillColor: C.bg2,
          isDense: true,
          // 纵向 13 同上：和 isDense + body(15px) 一起决定备注框的高度，
          // 比详情框高一点是因为备注是主输入项，属于组件内部尺寸
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
              // 3 是开关的固定内缩：轨道高 26 减去上下各 3 正好是 20 的滑块，
              // 改了滑块就会压出轨道或浮空，属于组件内部尺寸
              padding: const EdgeInsets.all(3),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on ? C.ink : C.line,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: C.cardBg,
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
