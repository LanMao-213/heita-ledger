import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/haptics.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../pages/debts_page.dart';
import '../../store.dart';
import '../common.dart';
import '../menu.dart';
import '../record_sheet.dart';

/// 单条交易。点按进入编辑，长按弹操作菜单。
///
/// 多选模式（[selecting]）下点按改为**切换选中**，并且**不响应长按** ——
/// 勾选时手指按住久一点就跳出菜单，是最容易误触的一种设计。
class TxnRow extends StatelessWidget {
  const TxnRow({
    super.key,
    required this.txn,
    this.showDate = false,
    this.selecting = false,
    this.selected = false,
    this.onToggle,
    this.onEnterSelection,
  });

  final Txn txn;
  final bool showDate;

  /// 多选模式：点按 = 切换选中，不再进编辑
  final bool selecting;

  /// 当前是否被选中（只在 [selecting] 为 true 时有意义）
  final bool selected;

  /// 多选模式下的点按回调
  final VoidCallback? onToggle;

  /// 长按菜单里的「多选」入口。
  ///
  /// 为 null 时退回旧的「长按直接删」—— 别处复用这个组件时不必都接多选。
  /// **长按不是被多选顶掉的**：菜单里「删除」还在，只是多了一条路。
  final VoidCallback? onEnterSelection;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final cat = s.categoryOf(txn.categoryId);
    // 借出/借入：这笔属于某笔往来，标题、图标、金额颜色都不走「分类 + 收支」那套
    final debt = s.debtOf(txn.debtId);
    // 子分类要带上一级，否则明细里只看到「正餐」，不知道它属于餐饮
    final parent = s.parentOf(cat);
    final acc = s.accountOf(txn.accountId);

    // 标题**永远**是分类名：两级分类之后，分类才是结构信息，备注只是补充。
    // 旧版本把备注当标题（因为名目就存在备注里），那笔账的「是什么」和
    // 「补充说明」被混成了一栏，统计上也就查不到「午饭一共花了多少」。
    // 借贷流水没有分类，标题换成「借出 · 张三」——一眼看出这是借钱不是花钱。
    final title = debt != null
        ? '${debt.direction.label} · ${debt.counterparty}'
        : (cat?.name ?? '未分类');
    final subParts = <String>[
      // 借贷最要紧的是「什么时候该还」，排在副行第一位
      if (debt != null && debt.dueDate != null) '应还 ${Fmt.md(debt.dueDate!)}',
      if (debt == null && parent != null) parent.name,
      // 出发地/目的地、对象、名称 —— 记了就得看得见，否则录完就再也找不到
      if (txn.detailSummary.isNotEmpty) txn.detailSummary,
      if (txn.note.isNotEmpty) txn.note,
      if (showDate) Fmt.md(txn.date),
      if (acc != null) acc.name,
    ];

    return FadeSlideIn(
      // 记一笔/删一笔之后整段列表是重建的：没有这一下，新增和删除都是
      // 「凭空出现 / 凭空消失」，看不出是哪一行变了。
      child: InkWell(
        // 借贷流水不能当普通支出编辑：改金额会和债务记录对不上。
        // 点它直接看往来详情，记还款也在那一页。
        onTap: selecting
            ? onToggle
            : (debt != null
                  ? () => showDebtDetail(context, debt)
                  : () => showRecordSheet(context, editing: txn)),
        onLongPress: selecting ? null : () => _longPressMenu(context),
        child: AnimatedContainer(
          duration: M.base,
          // 选中态加一层淡底。**主信号是左侧的勾选圈**，底色只是辅助 ——
          // 深色主题下 bg2 与 cardBg 的差异很小，指望底色扛区分度会失手。
          color: selected ? C.bg2 : Colors.transparent,
          child: Padding(
          // 左右 S.lg(16)：与日卡里其他元素（日期头、合计行）的右缘同一条线。
          // 纵向 11 是行内固定留白（配 36 的图标底 → 行高 58），属于组件内部
          // 尺寸，不参与页面节奏，不要收进 S 令牌
          padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 11),
          child: Row(
            children: [
              // 勾选圈只占多选态：平时不占位，行宽与原来一像素不差
              if (selecting) ...[
                _SelectMark(selected: selected),
                const SizedBox(width: S.sm),
              ],
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: C.bg2,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Center(
                  child: LineIcon(
                    // 借出=钱出去、借入=钱进来
                    debt != null
                        ? (debt.direction.isMoneyOut ? 'upload' : 'download')
                        : (cat?.icon ?? 'more'),
                    size: 19,
                    color: C.ink,
                  ),
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: T.body.copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 「周期账单」是它自己记的，不是用户点的。1.4.4 起补记会
                        // 在回到前台时就发生，列表里凭空多出几笔不标一下，
                        // 第一反应会是「我没记过这笔」。
                        if (debt == null && txn.recurringId != null) ...[
                          const SizedBox(width: 6),
                          const _AutoTag(),
                        ],
                      ],
                    ),
                    if (subParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subParts.join(' · '),
                        style: T.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: S.sm),
              Text(
                // 用 signedCents：支出为负、收入为正。金额本身为负（净额，如代购
                // 对方多给的钱）时符号自然翻转，不会出现「--20.00」
                Fmt.money(txn.signedCents, sign: true),
                style: T.amount.copyWith(
                  // 借贷用中性灰：它既不是消费也不是收入，用支出红会让
                  // 「这个月花了多少」在视觉上被一笔借款顶掉
                  color: debt != null
                      ? C.ink3
                      : (txn.type.isIncome ? C.ink2 : C.ink),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// 长按菜单：编辑 / 多选 / 删除。
  ///
  /// 为什么是菜单而不是「长按直接进多选」：长按删除是这个 App 用了很久的
  /// 路径，而 `deleteTxn` 的 UI 入口**只有这一处**（编辑页没有删除按钮）。
  /// 长按直接改成多选，等于把「删一笔」从两步变成三步。
  /// 菜单把多选**加**进来，两件事都保住。
  Future<void> _longPressMenu(BuildContext context) async {
    // 没接多选的调用方：保持原来的「长按直接删」，不必都升级
    if (onEnterSelection == null) {
      await _confirmDelete(context);
      return;
    }
    Haptics.tap();
    final act = await showMenuSheet<String>(
      context: context,
      // 标题用「分类 · 金额」：与列表同一口径，一眼知道长按的是哪一笔
      title: Store.i.categoryOf(txn.categoryId)?.name ?? '未分类',
      subtitle: Fmt.money(txn.signedCents, sign: true),
      groups: [
        MenuGroup(
          actions: [
            MenuAction(icon: 'pen', title: '编辑这笔', result: 'edit'),
            MenuAction(
              icon: 'check',
              title: '多选',
              subtitle: '批量改分类、批量删除',
              result: 'select',
            ),
            MenuAction(
              icon: 'trash',
              title: '删除这笔',
              danger: true,
              result: 'delete',
            ),
          ],
        ),
      ],
    );
    if (act == null || !context.mounted) return;
    if (act == 'edit') {
      await showRecordSheet(context, editing: txn);
    } else if (act == 'select') {
      onEnterSelection!();
    } else if (act == 'delete') {
      await _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showAppConfirm(
      context,
      title: '删除这笔记录？',
      // 与列表同一口径：分类名在前，备注只作补充。
      // 旧版拿备注当标题，出现的是「删除这笔记录？午饭」，看不出删的是哪一类。
      message:
          '${Store.i.categoryOf(txn.categoryId)?.name ?? '未分类'}'
          ' · ${Fmt.money(txn.signedCents, sign: true)}'
          '${txn.note.isEmpty ? '' : '\n${txn.note}'}',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok) return;
    await Store.i.deleteTxn(txn);
    Haptics.warn();
    if (context.mounted) showToast(context, '已删除');
  }
}

/// 「周期」小标签：这笔是周期账单自动生成的，不是用户自己点的。
///
/// 刻意做得很轻 —— 它只是「说明来源」的辅助信息，不该抢分类名和金额的注意力，
/// 所以用最浅的文字色 + 和正文对齐的基线，而不是做成醒目的 chip。
class _AutoTag extends StatelessWidget {
  const _AutoTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      // 角标自己的固定内边距：5/1 只为了把「周期」两个字包出一圈底，
      // 和行高无关，属于组件内部尺寸，不参与页面节奏
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(R.xs),
      ),
      child: Text(
        '周期',
        style: T.overline.copyWith(height: 1.35),
      ),
    );
  }
}

/// 多选态的勾选圈。
///
/// 用空心圆 → 实心带勾，而不是复选框方块：这个 App 里没有一块直角方块，
/// 圆形与卡片圆角、头像底同族，不会突然冒出一套「系统控件」的观感。
class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: M.base,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? C.ink : Colors.transparent,
        border: Border.all(color: selected ? C.ink : C.ink3, width: 1.5),
      ),
      child: selected
          ? Center(child: LineIcon('check', size: 12, color: C.bg))
          : null,
    );
  }
}
