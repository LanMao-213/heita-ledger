import 'package:flutter/material.dart';

import '../../data/cycle.dart';
import '../../data/models.dart';
import '../../data/pacing.dart';
import '../../design/tokens.dart';
import '../../store.dart';
import '../calendar_picker.dart';

/// 首页概览卡。
///
/// 浅灰底（`C.bg2`）+ 描边，和下方白底明细卡正好反过来：
/// 一个「压下去」的汇总区，配一组「浮上来」的记录卡。之前是纯黑 hero，
/// 在满屏黑白灰里太重，一进页面眼睛只能看到这块黑。
/// 概览卡的抬头：「本期支出 · 10.01 – 10.31」，整行可点，点了弹日历。
///
/// 日期从独立一行降成标签的注脚，是这张卡从「标题 + 数字」变成
/// 「一个数字 + 它的限定条件」的关键 —— 第一眼只剩金额。
class _PeriodHead extends StatelessWidget {
  const _PeriodHead({
    required this.from,
    required this.to,
    required this.onTap,
  });

  final String from;
  final String to;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const Text(
              '本期支出',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: C.ink2,
                height: 1.2,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 7),
              child: Text('·', style: TextStyle(fontSize: 14, color: C.ink4)),
            ),
            Flexible(
              child: Text(
                periodLabel(from, to),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: C.ink3,
                  letterSpacing: 0.1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    // 筛选态下这张卡整体换口径：周期换成结果摘要，数字改成筛选结果合计，
    // 预算进度条收起（预算按本期，跟跨期筛选没有关系）
    final filtering = s.filtering;
    final expense = filtering ? s.filteredExpenseCents : s.expenseCents;
    final income = filtering ? s.filteredIncomeCents : s.incomeCents;
    // 笔数也用聚合里的真实值：列表可能被截到 500 条，但「共几笔」不该跟着少算
    final count = filtering ? s.filterCount : s.txnCount;

    // 次要文字的灰度：浅底上不能再用「白字压暗」，那是深色卡的做法
    final dim = C.ink2;
    final faint = C.ink3;
    final budget = s.totalBudgetCents;
    // 进度与「还剩几天能花多少」都按**可用额度**算（预算 + 本期计入预算的借入），
    // 否则借入打开后这一行会和计划页对不上
    final cap = s.budgetAvailableCents;
    final borrowed = s.borrowedInBudgetCents;

    // 预算节奏只在「按本期看」时算：跨期筛选的合计和一期预算不是一回事
    final pacing = !filtering && budget != null
        ? Pacing.ofRange(
            from: s.cycleFrom,
            to: s.cycleTo,
            totalCents: cap,
            usedCents: s.expenseCents,
          )
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.xs),
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.lg),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶上不再有一条独立的日期：日期只是「本期支出」的注脚，
          // 和标签排在同一行，层级自然低一档
          if (filtering) ...[
            const _FilterHead(),
            const SizedBox(height: S.md),
            Text('筛选支出', style: TextStyle(fontSize: 12, color: faint)),
          ] else
            _PeriodHead(
              from: s.cycleFrom,
              to: s.cycleTo,
              onTap: () => showCalendarAndGo(context),
            ),
          const SizedBox(height: 2),
          // 金额到六位数时用 FittedBox 收一点，保证永远单行
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Fmt.money(expense),
              maxLines: 1,
              style: T.hero.copyWith(fontSize: 34),
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _HeroStat(label: '收入', value: Fmt.money(income)),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: _HeroStat(
                  label: filtering ? '收支差' : '结余',
                  value: Fmt.money(income - expense, sign: true),
                ),
              ),
              const SizedBox(width: S.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '$count 笔',
                  style: TextStyle(fontSize: 12, color: faint),
                ),
              ),
            ],
          ),
          if (pacing != null) ...[
            const SizedBox(height: S.lg),
            const Divider(height: 1, color: C.line),
            const SizedBox(height: S.md),
            Row(
              children: [
                Text(
                  '本期预算 ${Fmt.money(s.expenseCents)} / '
                  '${Fmt.money(cap)}',
                  style: TextStyle(fontSize: 12, color: dim),
                ),
                const Spacer(),
                Text(
                  s.overBudget
                      ? '超支 ${Fmt.money(s.overBudgetCents)}'
                      : '剩 ${Fmt.money(s.budgetLeftCents)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: s.overBudget ? C.over : C.ink,
                  ),
                ),
              ],
            ),
            // 借入计入预算时单列一行：挤在同一行里，右侧「剩多少」会被顶出屏幕
            if (borrowed > 0) ...[
              const SizedBox(height: 4),
              Text(
                '含借入 ${Fmt.money(borrowed)}（额度 ${Fmt.money(budget!)}）',
                style: TextStyle(fontSize: 11.5, color: faint),
              ),
            ],
            const SizedBox(height: S.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pacing.usedRatio.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: C.line2,
                valueColor: AlwaysStoppedAnimation(
                  s.overBudget ? C.over : C.ink,
                ),
              ),
            ),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text(
                  '还剩 ${pacing.remainDays} 天',
                  style: TextStyle(fontSize: 11.5, color: faint),
                ),
                const Spacer(),
                Text(
                  '每天可花 ${Fmt.money(pacing.canSpendPerDayCents)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: C.ink,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 概览卡里的一格小数字（收入 / 结余）
class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: C.ink3)),
        const SizedBox(height: 2),
        // 金额可能很长（收入五位数 + 结余带符号），等比缩一点保证单行
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: T.amountSm.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// 筛选态下替代周期条的那行：说清「这是筛选结果，共几笔，覆盖哪段时间」
class _FilterHead extends StatelessWidget {
  const _FilterHead();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Row(
      children: [
        const Text('筛选结果', style: T.section),
        const Spacer(),
        Flexible(
          child: Text(
            s.filter.dateLabel ?? '全部时间',
            style: T.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
