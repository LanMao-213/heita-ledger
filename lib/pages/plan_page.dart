import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';

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
          Padding(
            padding: const EdgeInsets.only(top: S.md),
            child: MonthBar(
              month: s.month,
              onPrev: () => s.shiftMonth(-1),
              onNext: () => s.shiftMonth(1),
            ),
          ),
          const _TotalBudgetCard(),
          const SectionTitle('分类预算'),
          const _CategoryBudgets(),
          const SectionTitle('储蓄目标'),
          const _Goals(),
          const SizedBox(height: S.lg),
        ],
      ),
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
    final over = s.overBudget;
    final used = budget == null || budget <= 0 ? 0.0 : s.monthExpenseCents / budget;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LineIcon('target', size: 18, color: C.ink2),
              const SizedBox(width: S.sm),
              Text('本月总预算', style: T.section),
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
                  style: const TextStyle(fontSize: 13, color: C.ink2),
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
                Text(Fmt.money(s.monthExpenseCents),
                    style: T.hero.copyWith(fontSize: 30)),
                Text('  /  ${Fmt.money(budget)}',
                    style: T.body2.copyWith(fontSize: 14)),
              ],
            ),
            const SizedBox(height: S.md),
            Bar(ratio: used, over: over, height: 7),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text('已用 ${(used * 100).toStringAsFixed(0)}%', style: T.caption),
                const Spacer(),
                if (over)
                  Text(
                    '超支 ${Fmt.money(s.overBudgetCents)}',
                    style: T.amountSm.copyWith(color: C.over, fontSize: 13.5),
                  )
                else
                  Text('剩余 ${Fmt.money(s.budgetLeftCents)}',
                      style: T.amountSm.copyWith(fontSize: 13.5)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editTotal(BuildContext context) async {
    final s = Store.i;
    final v = await _askAmount(
      context,
      title: '本月总预算',
      initial: s.totalBudgetCents ?? 0,
    );
    if (v == null) return;
    await Repo.setBudget(
      ledgerId: s.ledgerId,
      month: s.month,
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
      return const SectionCard(
        child: EmptyHint(
          icon: 'tag',
          text: '还没有分类预算或支出',
          hint: '可以在下方为常用分类单独设额度',
          padding: EdgeInsets.symmetric(vertical: S.lg),
        ),
      );
    }

    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: S.sm),
      child: Column(
        children: [
          for (final b in rows) _BudgetRow(stat: b),
          const Divider(height: 1, color: C.line),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: S.sm, top: S.xs),
              child: TextButton.icon(
                onPressed: () => _addCategoryBudget(context),
                icon: const LineIcon('plus', size: 16, color: C.ink2),
                label: const Text('为分类设置额度',
                    style: TextStyle(fontSize: 13, color: C.ink2)),
              ),
            ),
          ),
        ],
      ),
    );
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
      month: s.month,
      categoryId: cat.id,
      amountCents: v,
    );
    await s.afterBudgetChange();
    if (context.mounted) showToast(context, v <= 0 ? '已清除' : '已设置');
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.stat});

  final BudgetStat stat;

  @override
  Widget build(BuildContext context) {
    final hasBudget = stat.budgetCents > 0;
    final ratio = hasBudget ? stat.ratio : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              LineIcon(stat.icon, size: 18, color: C.ink2),
              const SizedBox(width: S.md),
              Text(stat.name, style: T.body.copyWith(fontWeight: FontWeight.w500)),
              const Spacer(),
              if (hasBudget)
                Text(
                  '${Fmt.money(stat.spentCents)} / ${Fmt.money(stat.budgetCents)}',
                  style: T.amountSm.copyWith(
                    fontSize: 13,
                    color: stat.over ? C.over : C.ink,
                  ),
                )
              else
                Text(
                  '${Fmt.money(stat.spentCents)}  ·  未设预算',
                  style: T.caption,
                ),
            ],
          ),
          if (hasBudget) ...[
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
                  Text('${(ratio * 100).toStringAsFixed(0)}%',
                      style: T.caption.copyWith(color: C.over)),
                ],
              ),
            ],
          ],
        ],
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
            child: EmptyHint(
              icon: 'flag',
              text: '还没有储蓄目标',
              hint: '比如「旅行基金 20000 元」',
              padding: EdgeInsets.symmetric(vertical: S.lg),
            ),
          )
        else
          for (final g in s.goals) _GoalCard(goal: g),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.xl),
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
            label: const Text('新建储蓄目标', style: TextStyle(fontSize: 14)),
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
      'flag', 'plane', 'laptop', 'car', 'wallet', 'target', 'home', 'coin',
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
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Center(
                          child: LineIcon(k,
                              size: 19, color: icon == k ? C.bg : C.ink2),
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
      await Repo.insertGoal(SavingGoal(
        id: 0,
        name: name,
        icon: icon,
        targetCents: target,
        savedCents: 0,
      ));
    } else {
      await Repo.updateGoal(goal.copyWith(name: name, icon: icon, targetCents: target));
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
      padding: const EdgeInsets.all(S.md),
      margin: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.xs),
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
                    borderRadius: BorderRadius.circular(11),
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
                          Text(goal.name,
                              style: T.body.copyWith(fontWeight: FontWeight.w600)),
                          if (goal.done) ...[
                            const SizedBox(width: S.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: C.ink,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text('已达成',
                                  style: TextStyle(fontSize: 10, color: C.bg)),
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
                  child: const Text('存一笔',
                      style: TextStyle(fontSize: 13, color: C.ink2)),
                ),
              ],
            ),
            const SizedBox(height: S.md),
            Bar(ratio: goal.progress, height: 6),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text('${(goal.progress * 100).toStringAsFixed(1)}%', style: T.caption),
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
