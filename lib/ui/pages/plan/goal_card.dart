import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/icon_map.dart';
import '../../widgets/progress_bar.dart';

/// 储蓄目标卡：图标 + 名字 + 已存/目标 + 进度 + 存钱/取钱两个按钮。
///
/// ★ 存钱**不生成流水**：它不是支出，进了流水会把预算和统计一起污染。
///   这一点在数据层（`GoalRepo.addFunds`）保证，UI 只负责说清楚。
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    required this.onEdit,
    required this.onDeposit,
    required this.onWithdraw,
  });

  final SavingGoal goal;
  final VoidCallback onEdit;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return AppCard(
      key: ValueKey<String>('goal-${goal.id}'),
      onTap: onEdit,
      onLongPress: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: pal.accentSoft,
                  borderRadius: R.rSm,
                ),
                child: Icon(IconMap.of(goal.icon), size: 16, color: pal.ink2),
              ),
              const SizedBox(width: S.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.body.copyWith(
                        color: pal.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      goal.dueMonth == null ? '没有期限' : '目标 ${goal.dueMonth}',
                      style: Ts.micro.copyWith(color: pal.ink4),
                    ),
                  ],
                ),
              ),
              if (goal.isDone)
                Text(
                  '已达成',
                  key: ValueKey<String>('goal-done-${goal.id}'),
                  style: Ts.micro.copyWith(color: pal.accent),
                ),
            ],
          ),
          const SizedBox(height: S.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              AmountText(
                cents: goal.savedCents,
                tier: AmountTier.heroSm,
              ),
              Text(
                ' / ${Fmt.money(goal.targetCents, trimZero: true)}',
                style: Ts.micro.copyWith(color: pal.ink4),
              ),
              const Spacer(),
              Text(
                '还差 ${Fmt.money(goal.remainingCents)}',
                style: Ts.micro.copyWith(color: pal.ink4),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          ProgressBar(ratio: goal.progress, height: 6),
          const SizedBox(height: S.md),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  key: ValueKey<String>('goal-deposit-${goal.id}'),
                  onPressed: onDeposit,
                  child: const Text('存钱'),
                ),
              ),
              const SizedBox(width: S.sm),
              Expanded(
                child: OutlinedButton(
                  key: ValueKey<String>('goal-withdraw-${goal.id}'),
                  onPressed: onWithdraw,
                  child: const Text('取钱'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 新建 / 编辑储蓄目标。返回 `null` = 取消。
Future<SavingGoal?> showGoalSheet(
  BuildContext context, {
  SavingGoal? goal,
}) {
  return showModalBottomSheet<SavingGoal>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _GoalSheet(goal: goal),
  );
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({this.goal});

  final SavingGoal? goal;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.goal?.name ?? '',
  );
  late final TextEditingController _target = TextEditingController(
    text: widget.goal == null
        ? ''
        : Fmt.money(widget.goal!.targetCents, trimZero: true),
  );
  late final TextEditingController _due = TextEditingController(
    text: widget.goal?.dueMonth ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _due.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    final int target = Fmt.parseCents(_target.text.trim());
    final String due = _due.text.trim();
    final SavingGoal base = widget.goal ?? const SavingGoal(name: '');
    Navigator.of(context).pop(
      base.copyWith(
        name: name,
        targetCents: target,
        dueMonth: due.isEmpty ? null : due,
        savedCents: widget.goal?.savedCents ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: pal.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(S.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.goal == null ? '新建储蓄目标' : '编辑储蓄目标',
                style: Ts.section.copyWith(color: pal.ink),
              ),
              const SizedBox(height: S.md),
              _Field(
                fieldKey: 'goal-name',
                controller: _name,
                hint: '叫什么（例如：换手机）',
              ),
              const SizedBox(height: S.sm),
              _Field(
                fieldKey: 'goal-target',
                controller: _target,
                hint: '目标金额',
                number: true,
              ),
              const SizedBox(height: S.sm),
              _Field(
                fieldKey: 'goal-due',
                controller: _due,
                hint: '目标月份 YYYY-MM（可不填）',
              ),
              const SizedBox(height: S.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('goal-save'),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(height: S.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// 存钱 / 取钱。返回**正数**分（调用方按 `deposit` 决定符号）。
Future<int?> showGoalFundsSheet(
  BuildContext context, {
  required SavingGoal goal,
  required bool deposit,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) =>
        _FundsSheet(goal: goal, deposit: deposit),
  );
}

class _FundsSheet extends StatefulWidget {
  const _FundsSheet({required this.goal, required this.deposit});

  final SavingGoal goal;
  final bool deposit;

  @override
  State<_FundsSheet> createState() => _FundsSheetState();
}

class _FundsSheetState extends State<_FundsSheet> {
  final TextEditingController _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String verb = widget.deposit ? '存钱' : '取钱';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: pal.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        child: Padding(
          padding: const EdgeInsets.all(S.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${widget.goal.name} · $verb',
                style: Ts.section.copyWith(color: pal.ink),
              ),
              const SizedBox(height: 2),
              Text(
                '已存 ${Fmt.money(widget.goal.savedCents)}',
                style: Ts.micro.copyWith(color: pal.ink3),
              ),
              const SizedBox(height: S.md),
              _Field(
                fieldKey: 'goal-funds-amount',
                controller: _amount,
                hint: '$verb金额',
                number: true,
                autofocus: true,
              ),
              const SizedBox(height: S.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('goal-funds-save'),
                  onPressed: () {
                    final int cents = Fmt.parseCents(_amount.text.trim());
                    Navigator.of(context).pop(cents);
                  },
                  child: Text(verb),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.controller,
    required this.hint,
    this.number = false,
    this.autofocus = false,
  });

  final String fieldKey;
  final TextEditingController controller;
  final String hint;
  final bool number;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return TextField(
      key: ValueKey<String>(fieldKey),
      controller: controller,
      autofocus: autofocus,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: Ts.body.copyWith(color: pal.ink),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: pal.surfaceAlt,
        hintText: hint,
        hintStyle: Ts.body2.copyWith(color: pal.ink4),
        border: OutlineInputBorder(
          borderRadius: R.rMd,
          borderSide: BorderSide(color: pal.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: R.rMd,
          borderSide: BorderSide(color: pal.line),
        ),
      ),
    );
  }
}
