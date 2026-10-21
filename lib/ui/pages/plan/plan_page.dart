import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/period.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/repo.dart';
import '../../../data/services/summary_service.dart';
import '../../../stores/catalog_store.dart';
import '../../../stores/plan_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pickers/calendar_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/swipe_flip.dart';
import '../../widgets/toast.dart';
import 'budget_card.dart';
import 'category_budget_list.dart';
import 'goal_card.dart';

/// 计划页（tab 2 / 底栏槽位 3）：往来摘要 + 周期条 + 预算 + 分类预算 + 储蓄目标。
///
/// 与图表页的分工：计划页**恒按「期」**（判据 3.8），口径切换只影响图表页 ——
/// 计划是「这一期我打算怎么花」，没有一个「本月」的版本。
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage>
    with AutomaticKeepAliveClientMixin<PlanPage> {
  @override
  bool get wantKeepAlive => true;

  // ── 周期条 ──

  void _flip(int delta) => PlanScope.of(context).movePeriod(delta);

  void _backToToday() => PlanScope.of(context).resetPeriodToToday();

  Future<void> _pickPeriod() async {
    final PlanStore plan = PlanScope.of(context);
    final LocalDate? picked = await showCalendarSheet(
      context,
      initial: plan.period.from,
    );
    if (picked == null || !mounted) return;
    await plan.jumpToPeriod(Period.cycleRange(picked, plan.cycleStartDay));
  }

  // ── 预算 ──

  Future<void> _editTotalBudget() async {
    final PlanStore plan = PlanScope.of(context);
    final int? cents = await showBudgetSheet(
      context,
      currentCents: plan.budget.totalBudgetCents,
      periodLabel: plan.period.dotLabel,
    );
    if (cents == null || !mounted) return;
    try {
      await Repo.budget.setTotalBudget(
        ledgerId: plan.ledgerId,
        periodStart: plan.period.from,
        amountCents: cents,
      );
      await plan.reload();
      if (mounted) showToast(context, cents <= 0 ? '已清除预算' : '预算已保存');
    } catch (_) {
      if (mounted) showToast(context, '保存失败，请重试', error: true);
    }
  }

  Future<void> _editCategoryBudget(CategoryBudgetRow row) async {
    final PlanStore plan = PlanScope.of(context);
    final int? cents = await showCategoryBudgetSheet(
      context,
      categoryName: row.category.name,
      currentCents: row.budgetCents,
    );
    if (cents == null || !mounted) return;
    final int? categoryId = row.category.id;
    if (categoryId == null) return;
    try {
      await Repo.budget.setCategoryBudget(
        ledgerId: plan.ledgerId,
        periodStart: plan.period.from,
        categoryId: categoryId,
        amountCents: cents,
      );
      await plan.reload();
      if (mounted) showToast(context, cents <= 0 ? '已取消限额' : '限额已保存');
    } catch (_) {
      if (mounted) showToast(context, '保存失败，请重试', error: true);
    }
  }

  // ── 储蓄目标 ──

  Future<void> _newGoal() async {
    final CatalogStore catalog = CatalogScope.of(context);
    final SavingGoal? goal = await showGoalSheet(context);
    if (goal == null || !mounted) return;
    await catalog.saveGoal(goal);
  }

  Future<void> _editGoal(SavingGoal goal) async {
    final CatalogStore catalog = CatalogScope.of(context);
    final SavingGoal? edited = await showGoalSheet(context, goal: goal);
    if (edited == null || !mounted) return;
    await catalog.saveGoal(edited);
  }

  Future<void> _deleteGoal(SavingGoal goal) async {
    final int? id = goal.id;
    if (id == null) return;
    final CatalogStore catalog = CatalogScope.of(context);
    final bool ok = await showConfirmDialog(
      context,
      title: '删除这个目标？',
      body: '「${goal.name}」里的已存记录会一起删掉，但不会动你记过的流水。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await catalog.deleteGoal(id);
    if (mounted) showToast(context, '已删除');
  }

  Future<void> _moveFunds(SavingGoal goal, {required bool deposit}) async {
    final int? id = goal.id;
    if (id == null) return;
    final CatalogStore catalog = CatalogScope.of(context);
    final int? cents = await showGoalFundsSheet(
      context,
      goal: goal,
      deposit: deposit,
    );
    if (cents == null || cents <= 0 || !mounted) return;
    final int saved = await catalog.addGoalFunds(id, deposit ? cents : -cents);
    if (mounted) {
      showToast(
        context,
        deposit ? '已存入，累计 ${saved ~/ 100}' : '已取出，累计 ${saved ~/ 100}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AppPalette pal = context.pal;
    final PlanStore plan = PlanScope.watch(context);
    final CatalogStore catalog = CatalogScope.watch(context);

    final BudgetStats stats = plan.budget;
    final List<CategoryBudgetRow> rows = plan.categoryBudgetRows;
    final List<SavingGoal> goals = catalog.goals;
    final DebtSums sums = debtSumsOf(plan.debts, plan.repaidIndex, plan.period);

    return ColoredBox(
      color: pal.bg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: SwipeFlip(
                onPrev: () => _flip(-1),
                onNext: () => _flip(1),
                onToday: _backToToday,
                onPick: _pickPeriod,
                child: _PeriodBar(period: plan.period),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, 0),
                child: sums.isEmpty
                    ? const _DebtGuide()
                    : _DebtSummaryCard(sums: sums),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.page, S.md, S.page, 0),
                child: BudgetCard(
                  stats: stats,
                  period: plan.period,
                  onEdit: _editTotalBudget,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '分类预算',
                trailing: Text(
                  '点一行改限额',
                  style: Ts.micro.copyWith(color: pal.ink4),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CategoryBudgetList(
                rows: rows,
                onEdit: _editCategoryBudget,
              ),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '储蓄目标',
                trailing: TextButton(
                  key: const ValueKey<String>('goal-new'),
                  onPressed: _newGoal,
                  child: Text(
                    '新建',
                    style: Ts.caption.copyWith(color: pal.ink),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.page),
                child: goals.isEmpty
                    ? Text(
                        '还没有储蓄目标。攒钱这件事，写下来比记在脑子里管用。',
                        key: const ValueKey<String>('goal-empty'),
                        style: Ts.caption.copyWith(color: pal.ink3),
                      )
                    : Column(
                        children: <Widget>[
                          for (final SavingGoal g in goals)
                            Padding(
                              padding: const EdgeInsets.only(bottom: S.sm),
                              child: GestureDetector(
                                onLongPress: () => _deleteGoal(g),
                                child: GoalCard(
                                  goal: g,
                                  onEdit: () => _editGoal(g),
                                  onDeposit: () =>
                                      _moveFunds(g, deposit: true),
                                  onWithdraw: () =>
                                      _moveFunds(g, deposit: false),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: S.xxxl)),
          ],
        ),
      ),
    );
  }
}

/// 往来摘要的三个数（应收 / 应付 / 本期到期笔数）。
class DebtSums {
  const DebtSums({
    required this.receivableCents,
    required this.payableCents,
    required this.dueCount,
  });

  static const DebtSums empty = DebtSums(
    receivableCents: 0,
    payableCents: 0,
    dueCount: 0,
  );

  final int receivableCents;
  final int payableCents;

  /// 本期到期的未结清笔数（翻期后要跟着变，判据 3.7）。
  final int dueCount;

  bool get isEmpty =>
      receivableCents == 0 && payableCents == 0 && dueCount == 0;
}

/// 纯函数：借贷 → 摘要。抽出来是为了「翻期后到期数重算」能被直接断言。
DebtSums debtSumsOf(List<Debt> debts, RepaidIndex index, Period period) {
  int due = 0;
  for (final Debt d in debts) {
    final int remaining = d.remainingCents(index);
    final LocalDate? dueDate = d.dueDate;
    if (dueDate != null &&
        remaining > 0 &&
        dueDate >= period.from &&
        dueDate <= period.to) {
      due++;
    }
  }
  return DebtSums(
    receivableCents: SummaryService.receivable(debts, index),
    payableCents: SummaryService.payable(debts, index),
    dueCount: due,
  );
}

/// 期条（三手势挂在 `SwipeFlip` 上）。
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.period});

  final Period period;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.page, S.md, S.page, S.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('本期计划', style: Ts.micro.copyWith(color: pal.ink3)),
                const SizedBox(height: 2),
                Text(
                  period.dotLabel,
                  key: const ValueKey<String>('plan-period'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ts.section.copyWith(color: pal.ink),
                ),
              ],
            ),
          ),
          Text(period.shortLabel, style: Ts.micro.copyWith(color: pal.ink4)),
        ],
      ),
    );
  }
}

/// 没有借贷时：**退化成一行引导**（不占整张卡，判据 3.6）。
class _DebtGuide extends StatelessWidget {
  const _DebtGuide();

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Row(
      key: const ValueKey<String>('debt-guide'),
      children: <Widget>[
        Icon(Icons.swap_horiz, size: 14, color: pal.ink4),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '还没有往来。记「借出 / 借入」时这里会显示谁欠你多少。',
            maxLines: 2,
            style: Ts.micro.copyWith(color: pal.ink3),
          ),
        ),
      ],
    );
  }
}

/// 有借贷时的摘要卡。
class _DebtSummaryCard extends StatelessWidget {
  const _DebtSummaryCard({required this.sums});

  final DebtSums sums;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: S.card,
        vertical: S.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('应收', style: Ts.micro.copyWith(color: pal.ink4)),
                AmountText(
                  key: const ValueKey<String>('debt-receivable'),
                  cents: sums.receivableCents,
                  tier: AmountTier.small,
                  color: pal.ink2,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('应付', style: Ts.micro.copyWith(color: pal.ink4)),
                AmountText(
                  key: const ValueKey<String>('debt-payable'),
                  cents: sums.payableCents,
                  tier: AmountTier.small,
                  color: pal.ink2,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text('本期到期', style: Ts.micro.copyWith(color: pal.ink4)),
              Text(
                '${sums.dueCount} 笔',
                key: const ValueKey<String>('debt-due-count'),
                style: Ts.amountSm.copyWith(color: pal.ink2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
