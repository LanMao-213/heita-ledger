import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/money.dart';
import '../../../core/period.dart';
import '../../../data/models/models.dart';
import '../../../data/services/pacing_service.dart';
import '../../../data/services/summary_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/progress_bar.dart';

/// 小字那一行的文案：**额度本身 + 借入明细**。
///
/// 判据 3.2 盯的就是这句：大数字（可用额度）会随借入变，但「额度」永远是
/// 用户自己设的那个数 —— 两个数必须同时出现在卡上，否则用户会以为
/// 自己设的 6000 被改了。
String budgetCaptionOf({required int? totalCents, required int borrowedCents}) {
  if (totalCents == null) return '未设';
  final String total = Fmt.money(totalCents);
  if (borrowedCents <= 0) return '额度 $total';
  return '额度 $total（含借入 ${Fmt.money(borrowedCents)}）';
}

/// 可用额度 = 额度 + 本期计入预算的借入（借出恒不计）。
int budgetAvailableOf(BudgetStats stats) => SummaryService.budgetAvailable(
  totalCents: stats.totalBudgetCents,
  borrowedInBudgetCents: stats.borrowedInBudgetCents,
);

/// 本期总预算卡：可用额度 + 进度 + 已花/剩余/每天可花 + 一句节奏。
///
/// ★ 进度、剩余、每天可花**全部走可用额度**（判据 3.2）：拿 `totalBudget` 去算，
/// 借入一打开这三个数字就全错。
class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.stats,
    required this.period,
    required this.onEdit,
    this.today,
  });

  final BudgetStats stats;

  /// 当前正在看的那一期（节奏句里的「还剩 N 天」要按它算）。
  final Period period;

  final VoidCallback onEdit;

  /// 测试可注入「今天」；`null` 走系统时间。
  final LocalDate? today;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final int? total = stats.totalBudgetCents;
    final int borrowed = stats.borrowedInBudgetCents;
    final int available = budgetAvailableOf(stats);

    final Pacing pacing = Pacing.ofRange(
      period: period,
      // 没设预算就是没设：给 `null` 而不是 0，否则卡片会显示「额度 0」的假象
      totalCents: total == null ? null : available,
      usedCents: stats.usedCents,
      today: today,
    );

    return AppCard(
      shadow: true,
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('本期可用', style: Ts.caption.copyWith(color: pal.ink2)),
              const Spacer(),
              Text(
                total == null ? '去设一个' : '改额度',
                style: Ts.micro.copyWith(color: pal.ink3),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (total == null)
            Text(
              '未设预算',
              key: const ValueKey<String>('budget-unset'),
              style: Ts.heroSm.copyWith(color: pal.ink3),
            )
          else
            AmountText(
              key: const ValueKey<String>('budget-available'),
              cents: available,
              yuan: true,
              tier: AmountTier.hero,
            ),
          const SizedBox(height: 2),
          Text(
            budgetCaptionOf(totalCents: total, borrowedCents: borrowed),
            key: const ValueKey<String>('budget-caption'),
            style: Ts.micro.copyWith(color: pal.ink4),
          ),
          const SizedBox(height: S.md),
          ProgressBar(
            ratio: pacing.usedRatio,
            overCents: pacing.overCents,
            height: 8,
          ),
          const SizedBox(height: S.md),
          Row(
            children: <Widget>[
              _Figure(
                label: '已花',
                child: AmountText(
                  key: const ValueKey<String>('budget-used'),
                  cents: stats.usedCents,
                  tier: AmountTier.small,
                  color: pal.ink2,
                ),
              ),
              _Figure(
                label: '剩余',
                child: AmountText(
                  key: const ValueKey<String>('budget-left'),
                  cents: pacing.hasBudget ? pacing.leftCents : 0,
                  tier: AmountTier.small,
                  color: pacing.overCents > 0 ? pal.over : pal.ink2,
                ),
              ),
              _Figure(
                label: '每天可花',
                child: AmountText(
                  key: const ValueKey<String>('budget-per-day'),
                  cents: pacing.canSpendPerDayCents,
                  tier: AmountTier.small,
                  color: pal.ink2,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          Text(
            pacing.sentence,
            key: const ValueKey<String>('budget-sentence'),
            style: Ts.micro.copyWith(color: pal.ink3, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Ts.micro.copyWith(color: pal.ink4)),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

/// 编辑本期总预算的面板。返回 `null` = 取消；返回金额（分）= 应用。
///
/// `amountCents <= 0` 由 `BudgetRepo.setTotalBudget` 落成「删行」——
/// 界面上「清空额度」就是输入 0 或留空。
Future<int?> showBudgetSheet(
  BuildContext context, {
  required int? currentCents,
  required String periodLabel,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) =>
        _BudgetSheet(currentCents: currentCents, periodLabel: periodLabel),
  );
}

class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({required this.currentCents, required this.periodLabel});

  final int? currentCents;
  final String periodLabel;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.currentCents == null
        ? ''
        : Fmt.money(widget.currentCents!, trimZero: true),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _apply() {
    final String raw = _amount.text.trim();
    final int cents = raw.isEmpty ? 0 : Fmt.parseCents(raw);
    Navigator.of(context).pop(cents);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: pal.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        child: Padding(
          padding: const EdgeInsets.all(S.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('本期总预算', style: Ts.section.copyWith(color: pal.ink)),
              const SizedBox(height: 2),
              Text(
                widget.periodLabel,
                style: Ts.micro.copyWith(color: pal.ink3),
              ),
              const SizedBox(height: S.md),
              TextField(
                key: const ValueKey<String>('budget-amount'),
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: Ts.body.copyWith(color: pal.ink),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: pal.surfaceAlt,
                  hintText: '留空或 0 = 清除预算',
                  hintStyle: Ts.body2.copyWith(color: pal.ink4),
                  prefixText: '¥ ',
                  prefixStyle: Ts.body.copyWith(color: pal.ink3),
                  border: OutlineInputBorder(
                    borderRadius: R.rMd,
                    borderSide: BorderSide(color: pal.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: R.rMd,
                    borderSide: BorderSide(color: pal.line),
                  ),
                ),
              ),
              const SizedBox(height: S.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('budget-save'),
                  onPressed: _apply,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
