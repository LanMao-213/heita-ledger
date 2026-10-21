import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/money.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/repo.dart';
import '../../../stores/plan_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/toast.dart';
import 'recurring_editor.dart';

/// 周期账单页（从计划页进来）。
///
/// 这一页最容易说错话的地方是**机制说明**：原版文案里带着 Markdown 星号
/// （`**每月 1 号**`）直接显示给用户看。判据 5.1 用「页面文本不含 `*`」盯着它，
/// 所以这里一个星号都不许有。
class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key});

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (!mounted) return;
    await PlanScope.of(context).reload();
  }

  Future<void> _catchUpNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    // **手动补记绕过闸一**（见 PlanStore.manualCatchUp 的注释）
    final int added = await PlanScope.of(context).manualCatchUp();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (!mounted) return;
    showToast(context, added > 0 ? '已补记 $added 笔' : '没有到期的账单');
  }

  Future<void> _toggle(Recurring rule, bool enabled) async {
    await Repo.recurring.update(rule.copyWith(enabled: enabled));
    await _refresh();
  }

  Future<void> _delete(Recurring rule) async {
    final bool ok = await showConfirmDialog(
      context,
      title: '删除这条规则？',
      body: '只删规则，已经记下的流水不会动。别处的账目一条都不会少。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await Repo.recurring.delete(rule.id!);
    await _refresh();
    if (mounted) showToast(context, '已删除规则');
  }

  Future<void> _edit([Recurring? rule]) async {
    final int cycleStartDay = PlanScope.of(context).cycleStartDay;
    final Recurring? saved = await showRecurringEditor(
      context,
      rule: rule,
      cycleStartDay: cycleStartDay,
    );
    if (saved == null || !mounted) return;
    if (saved.id == null) {
      // 编辑器不知道账本 id（它不该知道），插入前补上 —— 漏了会撞 FK constraint
      await Repo.recurring.insert(
        saved.copyWith(ledgerId: PlanScope.of(context).ledgerId),
      );
    } else {
      await Repo.recurring.update(saved);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final PlanStore plan = PlanScope.watch(context);
    final List<Recurring> rules = plan.recurring;
    final LocalDate today = LocalDate.today();

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        elevation: 0,
        title: Text('周期账单', style: Ts.section.copyWith(color: pal.ink)),
        iconTheme: IconThemeData(color: pal.ink),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('recurring-catchup'),
            onPressed: _busy ? null : _catchUpNow,
            child: Text('立刻补记', style: Ts.caption.copyWith(color: pal.ink)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey<String>('recurring-new'),
        onPressed: () => _edit(),
        backgroundColor: pal.accent,
        foregroundColor: pal.onAccent,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('新建规则'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxxl),
        children: <Widget>[
          AppCard(
            color: pal.surfaceAlt,
            child: Text(
              '到期的账单会在打开 App 或回到前台时自动补记，交易日期记成'
              '本该发生的那一天（不是补记当天）。同一笔不会记两次；'
              '改系统日期也不会重复。',
              key: const ValueKey<String>('recurring-note'),
              style: Ts.caption.copyWith(color: pal.ink2, height: 1.6),
            ),
          ),
          const SizedBox(height: S.md),
          if (rules.isEmpty)
            const SizedBox(
              height: 220,
              child: EmptyState(
                key: ValueKey<String>('recurring-empty'),
                icon: Icons.event_repeat_outlined,
                title: '还没有周期账单',
                hint: '房租、订阅、工资这类每月固定的事，建一条规则就不用每次记。',
              ),
            )
          else
            for (final Recurring rule in rules)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: _RuleCard(
                  rule: rule,
                  today: today,
                  onTap: () => _edit(rule),
                  onToggle: (bool v) => _toggle(rule, v),
                  onDelete: () => _delete(rule),
                ),
              ),
        ],
      ),
    );
  }
}

/// 规则卡副行：`每月 · 支出 ¥3,000.00 · 待补记` / `... · 下次 11-01`。
///
/// 抽成纯函数是为了「待补记」这三个字能被直接断言（它要标红）。
String recurringSubtitle(Recurring rule, {LocalDate? today}) {
  final String freq = rule.interval <= 1
      ? rule.freq.label
      : '每 ${rule.interval} ${rule.freq.label.replaceAll('每', '')}';
  final String type = rule.type.isIncome ? '收入' : '支出';
  final String amount = '¥${Fmt.money(rule.amountCents)}';
  final LocalDate now = today ?? LocalDate.today();
  final bool due = rule.isDue(now);
  final String tail = due
      ? '待补记'
      : '下次 ${rule.nextRunDate.month.toString().padLeft(2, '0')}-'
            '${rule.nextRunDate.day.toString().padLeft(2, '0')}';
  return '$freq · $type $amount · $tail';
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.today,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final Recurring rule;
  final LocalDate today;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final bool due = rule.isDue(today);
    return AppCard(
      key: ValueKey<String>('recurring-card-${rule.id}'),
      onTap: onTap,
      onLongPress: onDelete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  rule.note.trim().isEmpty ? '周期账单' : rule.note.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ts.body.copyWith(color: pal.ink),
                ),
              ),
              if (rule.endDate != null)
                Text(
                  '至 ${rule.endDate!.iso}',
                  style: Ts.micro.copyWith(color: pal.ink4),
                ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  key: ValueKey<String>('recurring-toggle-${rule.id}'),
                  value: rule.enabled,
                  onChanged: onToggle,
                ),
              ),
            ],
          ),
          Text(
            recurringSubtitle(rule, today: today),
            key: ValueKey<String>('recurring-sub-${rule.id}'),
            style: Ts.caption.copyWith(
              color: !rule.enabled
                  ? pal.ink4
                  : (due ? pal.over : pal.ink3),
            ),
          ),
          if (!rule.enabled)
            Text(
              '已暂停',
              key: ValueKey<String>('recurring-paused-${rule.id}'),
              style: Ts.micro.copyWith(color: pal.ink4),
            ),
        ],
      ),
    );
  }
}

/// 供外部打开周期账单页。
Future<void> openRecurringPage(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (BuildContext _) => const RecurringPage()));

/// 计划页入口行的副行。
String recurringEntrySubtitle(List<Recurring> rules, {LocalDate? today}) {
  if (rules.isEmpty) return '还没有周期账单';
  final int due = rules.where((Recurring r) => r.isDue(today ?? LocalDate.today())).length;
  return due > 0 ? '$due 条待补记' : '${rules.length} 条规则';
}
