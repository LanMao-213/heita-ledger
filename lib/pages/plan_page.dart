import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/pacing.dart';
import '../data/repo.dart';
import '../design/hairline.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/calendar_picker.dart';
import '../widgets/common.dart';
import 'debts_page.dart';

/// 计划页 = 预算 + 储蓄目标。
/// 这个位置原来是「分类」，按用户要求把分类移进了「我的」，这里放计划。
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: S.xxl),
        children: [
          const PageHeader(title: '计划'),
          Padding(
            padding: const EdgeInsets.only(top: S.xs),
            child: CycleBar(
              from: s.cycleFrom,
              to: s.cycleTo,
              onPrev: () => s.shiftCycle(-1),
              onNext: () => s.shiftCycle(1),
              onTapLabel: () => showCalendarAndGo(context),
              onReset: s.backToCurrentCycle,
            ),
          ),
          // ⚠️ 不要加 const：这些组件读 Store，const 实例在重建时会被
          // 判定为「同一个 widget」而跳过 build，界面上就是「改了没反应」
          _DebtsCard(),
          _TotalBudgetCard(),
          const SectionTitle('分类预算'),
          _CategoryBudgets(),
          const SectionTitle('储蓄目标'),
          _Goals(),
          const SizedBox(height: S.lg),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------- 往来

/// 往来摘要：应收 / 应付 / 本期到期笔数，点进去是完整台账。
///
/// 放在计划页而不是「我的」，是因为借贷直接改变这一期还能花多少，
/// 和预算同屏才容易被看见。没有借贷时退化成一行引导，不占一整张卡。
class _DebtsCard extends StatelessWidget {
  const _DebtsCard();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final open = s.debts.where((d) => !d.isClosed).toList();
    final receivable = open
        .where((d) => d.direction.isReceivable)
        .fold<int>(0, (a, d) => a + d.remainingCents);
    final payable = open
        .where((d) => !d.direction.isReceivable)
        .fold<int>(0, (a, d) => a + d.remainingCents);
    final dueSoon = open.where((d) {
      final due = d.dueDate;
      return due != null &&
          due.compareTo(s.cycleFrom) >= 0 &&
          due.compareTo(s.cycleTo) <= 0;
    }).length;

    void openPage() => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DebtsPage()));

    if (open.isEmpty) {
      return SectionCard(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: openPage,
          child: Row(
            children: [
              const LineIcon('coin', size: 18, color: C.ink2),
              const SizedBox(width: S.sm),
              Expanded(
                child: Text('往来：记借出/借入后，在这里看谁欠谁多少', style: T.body2),
              ),
              const LineIcon(
                'chevron_right',
                size: 20,
                color: C.ink3,
              ),
            ],
          ),
        ),
      );
    }

    return SectionCard(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: openPage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const LineIcon('coin', size: 18, color: C.ink2),
                const SizedBox(width: S.sm),
                Text('往来', style: T.section),
                const Spacer(),
                if (dueSoon > 0)
                  Text(
                    '本期到期 $dueSoon 笔',
                    style: T.caption.copyWith(color: C.ink2),
                  ),
                const SizedBox(width: S.xs),
                const LineIcon(
                  'chevron_right',
                  size: 20,
                  color: C.ink3,
                ),
              ],
            ),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Expanded(child: _MiniFigure(label: '应收', cents: receivable)),
                Expanded(child: _MiniFigure(label: '应付', cents: payable)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniFigure extends StatelessWidget {
  const _MiniFigure({required this.label, required this.cents});

  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.caption),
        const SizedBox(height: 2),
        Text(Fmt.money(cents), style: T.amount),
      ],
    );
  }
}

// --------------------------------------------------------------------- 总预算

class _TotalBudgetCard extends StatelessWidget {
  const _TotalBudgetCard();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final budget = s.totalBudgetCents;
    final borrowed = s.borrowedInBudgetCents;
    // 进度按**可用额度**算：借入计入预算时它比额度大，不按它算就会出现
    // 「条子才到 84%，剩余却有 5,951」这种自相矛盾的组合
    final cap = s.budgetAvailableCents;
    final over = s.overBudget;
    final used = budget == null || cap <= 0 ? 0.0 : s.expenseCents / cap;
    final pacing = Pacing.ofRange(
      from: s.cycleFrom,
      to: s.cycleTo,
      totalCents: cap,
      usedCents: s.expenseCents,
    );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LineIcon('target', size: 18, color: C.ink2),
              const SizedBox(width: S.sm),
              Text('本期总预算', style: T.section),
              const Spacer(),
              TextButton(
                onPressed: () => _editTotal(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: S.sm),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  budget == null ? '设置' : '修改',
                  style: T.body2,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          if (budget == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.sm),
              child: Text('还没有设预算。设一个数，超支时会用红色提醒你。', style: T.body2),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  Fmt.money(s.expenseCents),
                  style: T.hero,
                ),
                Text(
                  '  /  ${Fmt.money(cap)}',
                  style: T.body2,
                ),
              ],
            ),
            // 借入计入预算时，卡片上的额度直接显示成「额度 + 借入」（9000），
            // 下面小字说明这多出来的 3000 是借的 —— 借来的钱确实能花，
            // 大数字若还停在 6000，用户会以为预算没变。存的额度不动，下期自动还原。
            //
            // 措辞与明细页概览卡一致：**额度在前、借入在括号里**（D-26）。
            // 两处同一件事用两种写法，用户会以为是两个不同的数。
            if (borrowed > 0) ...[
              const SizedBox(height: S.xs),
              Text(
                '额度 ${Fmt.money(budget)}（含借入 ${Fmt.money(borrowed)}）',
                style: T.caption.copyWith(color: C.ink3),
              ),
            ],
            const SizedBox(height: S.md),
            Bar(ratio: used, over: over, height: 7),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text(
                  '已用 ${(used * 100).toStringAsFixed(0)}%',
                  style: T.caption,
                ),
                const Spacer(),
                if (over)
                  Text(
                    '超支 ${Fmt.money(s.overBudgetCents)}',
                    style: T.amountXs.copyWith(color: C.over),
                  )
                else
                  Text(
                    '剩余 ${Fmt.money(s.budgetLeftCents)}',
                    style: T.amountXs,
                  ),
              ],
            ),
            // 预算节奏：把「还剩多少」翻成「还剩几天、每天能花多少」。
            // 数字看完还得自己心算的东西，等于没给。
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text('还剩 ${pacing.remainDays} 天', style: T.caption),
                const Spacer(),
                // 已经超支时这个数必然是 0.00 —— 一个恒为 0 的数字不是信息
                if (pacing.canSpendPerDayCents > 0)
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '每天可花 ', style: T.caption),
                        TextSpan(
                          text: Fmt.money(pacing.canSpendPerDayCents),
                          style: T.amountSm,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            // 只在**有新增信息**时出现（已结束 / 按现在节奏会超）。
            // 原来这里常驻一块灰底文案，把上面「剩余 X」「每天可花 Y」
            // 原样复述一遍 —— 同一组数字说两遍，还多占 60dp 高度。
            if (pacing.alert != null) ...[
              const SizedBox(height: S.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LineIcon(
                    'info',
                    size: 15,
                    color: over ? C.over : C.ink3,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pacing.alert!,
                      style: T.body2.copyWith(
                        color: over ? C.over : C.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _editTotal(BuildContext context) async {
    final s = Store.i;
    final v = await _askAmount(
      context,
      title: '本期总预算',
      initial: s.totalBudgetCents ?? 0,
    );
    if (v == null) return;
    await Repo.setBudget(
      ledgerId: s.ledgerId,
      periodStart: s.cycleFrom,
      amountCents: v,
    );
    await s.afterBudgetChange();
    if (context.mounted) showToast(context, v <= 0 ? '已清除预算' : '预算已更新');
  }
}

// ------------------------------------------------------------------- 分类预算

class _CategoryBudgets extends StatelessWidget {
  const _CategoryBudgets();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final rows = s.budgetStats;

    if (rows.isEmpty) {
      // 空态卡：上下 24 由卡自己撑，EmptyHint 不再叠一层内边距
      return const SectionCard(
        padding: EdgeInsets.symmetric(horizontal: S.lg, vertical: S.xxl),
        child: EmptyHint(
          icon: 'tag',
          text: '还没有分类预算或支出',
          hint: '可以在下方为常用分类单独设额度',
          padding: EdgeInsets.zero,
        ),
      );
    }

    // 分成两组：设了额度的看进度，没设额度的直接可以点去设。
    // 原来混在一张列表里，没额度的只有「未设预算」四个字，既没有进度
    // 也没有动作 —— 而花得最多的分类往往正在这一组里（房租这类）。
    final budgeted = rows.where((b) => b.budgetCents > 0).toList();
    final unbudgeted = rows.where((b) => b.budgetCents <= 0).toList();

    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: S.sm),
      child: Column(
        children: [
          for (final b in budgeted)
            _BudgetRow(stat: b, onTap: () => _editBudget(context, b)),
          if (budgeted.isNotEmpty && unbudgeted.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.lg),
              child: Divider(
                height: 1,
                thickness: hairlineOf(context),
                color: C.line,
              ),
            ),
          for (final b in unbudgeted)
            _UnbudgetedRow(stat: b, onTap: () => _editBudget(context, b)),
          Divider(height: 1, thickness: hairlineOf(context), color: C.line),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: S.sm, top: S.xs),
              child: TextButton.icon(
                onPressed: () => _addCategoryBudget(context),
                icon: const LineIcon('plus', size: 16, color: C.ink2),
                label: const Text(
                  '为分类设置额度',
                  style: T.body2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 点已设额度的行 → 直接改这一类的额度（不用先逛选择器）。
  Future<void> _editBudget(BuildContext context, BudgetStat b) async {
    final s = Store.i;
    final v = await _askAmount(
      context,
      title: '${b.name} 的预算',
      initial: b.budgetCents,
    );
    if (v == null) return;
    await Repo.setBudget(
      ledgerId: s.ledgerId,
      periodStart: s.cycleFrom,
      categoryId: b.categoryId,
      amountCents: v,
    );
    await s.afterBudgetChange();
    if (context.mounted) showToast(context, v <= 0 ? '已清除' : '已更新');
  }

  Future<void> _addCategoryBudget(BuildContext context) async {
    final s = Store.i;
    final cat = await showModalBottomSheet<Category>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(title: '选择分类'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in s.expenseCats)
                    SettingRow(
                      icon: c.icon,
                      title: c.name,
                      onTap: () => Navigator.pop(ctx, c),
                    ),
                ],
              ),
            ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
    if (cat == null || !context.mounted) return;

    final v = await _askAmount(context, title: '${cat.name} 的预算', initial: 0);
    if (v == null) return;
    await Repo.setBudget(
      ledgerId: s.ledgerId,
      periodStart: s.cycleFrom,
      categoryId: cat.id,
      amountCents: v,
    );
    await s.afterBudgetChange();
    if (context.mounted) showToast(context, v <= 0 ? '已清除' : '已设置');
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.stat, required this.onTap});

  final BudgetStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = stat.ratio;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        // 列表卡的左右内边距是 0，左右 16 由行自己补，才和别的内容卡对齐
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
        child: Column(
          children: [
            Row(
              children: [
                LineIcon(stat.icon, size: 18, color: C.ink2),
                const SizedBox(width: S.md),
                Text(
                  stat.name,
                  style: T.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                // 已用是主角、额度是参照：原来两个数字同字号同灰度，
                // 读不出哪个是花掉的、哪个是上限
                Text(
                  Fmt.money(stat.spentCents),
                  style: T.amountXs.copyWith(
                    color: stat.over ? C.over : C.ink,
                  ),
                ),
                Text(
                  ' / ${Fmt.money(stat.budgetCents)}',
                  style: T.caption,
                ),
              ],
            ),
            const SizedBox(height: S.sm),
            Bar(ratio: ratio, over: stat.over, height: 5),
            if (stat.over) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '已超 ${Fmt.money(stat.overCents)}',
                    style: T.caption.copyWith(color: C.over),
                  ),
                  const Spacer(),
                  Text(
                    '${(ratio * 100).toStringAsFixed(0)}%',
                    style: T.caption.copyWith(color: C.over),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 未设额度：一行，点一下就能设。
///
/// 不把这行做「灰」—— 待设额度的常常是花得最多的分类，
/// 把最大的支出画成禁用态，方向正好反了。
class _UnbudgetedRow extends StatelessWidget {
  const _UnbudgetedRow({required this.stat, required this.onTap});

  final BudgetStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 11),
        child: Row(
          children: [
            LineIcon(stat.icon, size: 18, color: C.ink2),
            const SizedBox(width: S.md),
            Expanded(
              child: Text(
                stat.name,
                style: T.body,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(Fmt.money(stat.spentCents), style: T.amountSm),
            const SizedBox(width: S.sm),
            Text('设额度', style: T.caption),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- 储蓄目标

class _Goals extends StatelessWidget {
  const _Goals();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Column(
      children: [
        if (s.goals.isEmpty)
          const SectionCard(
            padding: EdgeInsets.symmetric(horizontal: S.lg, vertical: S.xxl),
            child: EmptyHint(
              icon: 'flag',
              text: '还没有储蓄目标',
              hint: '比如「旅行基金 20000 元」',
              padding: EdgeInsets.zero,
            ),
          )
        else
          for (final g in s.goals) _GoalCard(goal: g),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.lg),
          child: OutlinedButton.icon(
            onPressed: () => _edit(context, null),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              side: const BorderSide(color: C.line2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.md),
              ),
              foregroundColor: C.ink,
            ),
            icon: const LineIcon('plus', size: 18, color: C.ink),
            label: const Text('新建储蓄目标', style: T.body),
          ),
        ),
      ],
    );
  }

  static Future<void> _edit(BuildContext context, SavingGoal? goal) async {
    final s = Store.i;
    final nameCtl = TextEditingController(text: goal?.name ?? '');
    final targetCtl = TextEditingController(
      text: goal == null ? '' : (goal.targetCents / 100).toStringAsFixed(0),
    );
    var icon = goal?.icon ?? 'flag';

    const iconChoices = [
      'flag',
      'plane',
      'laptop',
      'car',
      'wallet',
      'target',
      'home',
      'coin',
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(goal == null ? '新建储蓄目标' : '编辑目标', style: T.section),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(hintText: '目标名称'),
              ),
              const SizedBox(height: S.md),
              TextField(
                controller: targetCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '目标金额（元）'),
              ),
              const SizedBox(height: S.lg),
              Wrap(
                spacing: S.sm,
                runSpacing: S.sm,
                children: [
                  for (final k in iconChoices)
                    GestureDetector(
                      onTap: () => setLocal(() => icon = k),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: icon == k ? C.ink : C.bg2,
                          borderRadius: BorderRadius.circular(R.sm),
                        ),
                        child: Center(
                          child: LineIcon(
                            k,
                            size: 19,
                            color: icon == k ? C.bg : C.ink2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
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
      ),
    );

    if (ok != true) return;
    final name = nameCtl.text.trim();
    final target = Fmt.parseCents(targetCtl.text);
    if (name.isEmpty || target <= 0) {
      if (context.mounted) showToast(context, '名称和金额都要填');
      return;
    }

    if (goal == null) {
      await Repo.insertGoal(
        SavingGoal(
          id: 0,
          name: name,
          icon: icon,
          targetCents: target,
          savedCents: 0,
        ),
      );
    } else {
      await Repo.updateGoal(
        goal.copyWith(name: name, icon: icon, targetCents: target),
      );
    }
    await s.afterGoalChange();
    if (context.mounted) showToast(context, '已保存');
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final SavingGoal goal;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      // 内容卡：内边距用默认 16。左右外边距也归一到 16 —— 目标卡和按钮
      // 原是 20，与本页其他卡（16）差 4，整屏会错开一条
      margin: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.xs),
      child: InkWell(
        onLongPress: () => _menu(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: C.bg2,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Center(
                    child: LineIcon(goal.icon, size: 20, color: C.ink),
                  ),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            goal.name,
                            style: T.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (goal.done) ...[
                            const SizedBox(width: S.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: C.ink,
                                borderRadius: BorderRadius.circular(R.xs),
                              ),
                              child: Text(
                                '已达成',
                                style: T.overline.copyWith(color: C.bg),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${Fmt.money(goal.savedCents)} / ${Fmt.money(goal.targetCents)}',
                        style: T.caption,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _addFunds(context, goal),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: S.sm),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '存一笔',
                    style: T.body2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.md),
            Bar(ratio: goal.progress, height: 6),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text(
                  '${(goal.progress * 100).toStringAsFixed(1)}%',
                  style: T.caption,
                ),
                const Spacer(),
                if (goal.dueMonth != null)
                  Text('目标 ${Fmt.monthLabel(goal.dueMonth!)}', style: T.caption)
                else
                  Text('还差 ${Fmt.money(goal.remainCents)}', style: T.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFunds(BuildContext context, SavingGoal g) async {
    final s = Store.i;
    final v = await _askAmount(context, title: '存入「${g.name}」', initial: 0);
    if (v == null || v == 0) return;
    await Repo.addFunds(g.id, v);
    await s.afterGoalChange();
    if (context.mounted) showToast(context, '已存入 ${Fmt.money(v)}');
  }

  Future<void> _menu(BuildContext context) async {
    final s = Store.i;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: goal.name),
            SettingRow(
              icon: 'tpl',
              title: '编辑',
              onTap: () {
                Navigator.pop(ctx);
                _Goals._edit(context, goal);
              },
            ),
            SettingRow(
              icon: 'download',
              title: '取出全部',
              subtitle: Fmt.money(goal.savedCents),
              onTap: () async {
                Navigator.pop(ctx);
                await Repo.addFunds(goal.id, -goal.savedCents);
                await s.afterGoalChange();
              },
            ),
            SettingRow(
              icon: 'more',
              title: '删除目标',
              danger: true,
              onTap: () async {
                Navigator.pop(ctx);
                await Repo.deleteGoal(goal.id);
                await s.afterGoalChange();
              },
            ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- 工具

/// 金额输入弹窗。返回分；返回 null 表示取消。
Future<int?> _askAmount(
  BuildContext context, {
  required String title,
  required int initial,
}) async {
  final ctl = TextEditingController(
    text: initial <= 0 ? '' : (initial / 100).toStringAsFixed(0),
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: T.section),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          prefixText: '¥ ',
          hintText: '0（留空或 0 表示清除）',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消', style: TextStyle(color: C.ink2)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确定', style: TextStyle(color: C.ink)),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  return Fmt.parseCents(ctl.text);
}
