import 'package:flutter/material.dart';

import '../../data/cycle.dart';
import '../../data/models.dart';
import '../../data/pacing.dart';
import '../../design/hairline.dart';
import '../../design/haptics.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../store.dart';
import '../calendar_picker.dart';

/// 首页概览卡。
///
/// 浅灰底（`C.heroBg`，默认主题下等于 `C.bg2`）+ 描边，和下方白底明细卡正好反过来：
/// 一个「压下去」的汇总区，配一组「浮上来」的记录卡。之前是纯黑 hero，
/// 在满屏黑白灰里太重，一进页面眼睛只能看到这块黑。
/// 概览卡的抬头：「本期支出 · 10.01 – 10.31」，整行可点，点了弹日历。
///
/// 日期从独立一行降成标签的注脚，是这张卡从「标题 + 数字」变成
/// 「一个数字 + 它的限定条件」的关键 —— 第一眼只剩金额。
///
/// **双击**回到今天所在的期：1.4.5 起横滑概览卡就能一期一期地翻，
/// 翻远了以后双击是最省事的回程（不用一期一期点回去，也不用在日历里
/// 找今天）。和统计页的月份条是同一套手感 —— 单击开日历、双击回当前。
///
/// ⚠️ 同时挂 tap 与 doubleTap 的代价：单击要等 300ms 双击窗口
/// （`kDoubleTapTimeout`），日历会晚一点点弹出来。这是「一个地方两种点击」
/// 的固有成本，全应用只有两处这样（这行、统计页月份条），不是卡顿。
class _PeriodHead extends StatelessWidget {
  const _PeriodHead({
    required this.from,
    required this.to,
    required this.onTap,
    required this.onReset,
  });

  final String from;
  final String to;
  final VoidCallback onTap;

  /// 双击回本期（已经在本期时是空操作，见调用点）
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    // 翻到期外还说「本期」就是错的。横滑之前翻期要点日历、不容易走远，
    // 现在一滑就到上个月，这行字必须跟着变。
    final label = s.isCurrentPeriod ? '本期支出' : '支出';
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onReset,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Text(
              label,
              style: T.body.copyWith(
                fontWeight: FontWeight.w500,
                color: C.ink2,
                height: 1.2,
              ),
            ),
            Padding(
              // 7 是孤立值：它是「本期支出」和日期之间的间隔点，收到 S.sm(8)
              // 落到 8pt 栅格上
              padding: const EdgeInsets.symmetric(horizontal: S.sm),
              child: Text('·', style: T.body.copyWith(color: C.ink4)),
            ),
            Flexible(
              child: Text(
                periodLabel(from, to),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.caption.copyWith(
                  letterSpacing: 0.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
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

    // 没设预算的期：底栏**不消失**，换成这一期的小总结（日均 / 最大一笔 / 环比）。
    //
    // 预算按「期」存（`budget.period_start`），翻到上个月那张表里通常没有记录，
    // 以前整块底栏直接消失 —— 卡片高度从 300px 掉到 150px，下面的列表跟着窜一下，
    // 而空出来的地方什么都不说。翻期又能一滑就到，这个跳动会反复出现。
    //
    // 只做纯计算，不查库：天数由 Pacing 现算，最大一笔从已加载的 txns 里取，
    // 上一期的合计在 loadCycle 里**仅当这一期没预算时**才取（见 store 的注释）。
    final summary = !filtering && budget == null
        ? Pacing.ofRange(
            from: s.cycleFrom,
            to: s.cycleTo,
            totalCents: null,
            usedCents: s.expenseCents,
          )
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.xs),
      // 内容卡：四边 16。原来是 16/12/16/16（上边少了 4），和同屏日卡、
      // SectionCard 的 all(S.lg) 对不上，抬头会比其他卡片的左侧文字高一档
      padding: const EdgeInsets.all(S.lg),
      // 概览卡是「压下去」的那一档（heroBg 比 bg 深），靠明度差分界，
      // 不再叠一条暖描边 —— 日卡是「浮起来」的一档（白面 + E.low），
      // 同屏只留这一套语法，边界才不糊。
      decoration: ShapeDecoration(
        color: C.heroBg,
        shadows: E.none,
        shape: Shape.squircle(R.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶上不再有一条独立的日期：日期只是「本期支出」的注脚，
          // 和标签排在同一行，层级自然低一档
          if (filtering) ...[
            const _FilterHead(),
            const SizedBox(height: S.md),
            Text('筛选支出', style: T.caption),
          ] else
            _PeriodHead(
              from: s.cycleFrom,
              to: s.cycleTo,
              onTap: () => showCalendarAndGo(context),
              // 已经在本期就什么都不做：否则白跑一次 loadCycle，还多震一下，
              // 用户会以为「双击有什么副作用」
              onReset: () {
                if (s.isCurrentPeriod) return;
                Haptics.tap();
                s.backToCurrentCycle();
              },
            ),
          const SizedBox(height: 2),
          // 金额到六位数时用 FittedBox 收一点，保证永远单行
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            // 翻期/筛选时这一行是全场最大的数字，硬切最像「卡了一下」。
            // 新的从下方滑上来、旧的往上淡出，眼睛能跟上数字是怎么变的。
            child: AnimatedMoney(
              text: Fmt.money(expense),
              style: T.hero,
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
                // 下 2 是光学补偿：让「N 笔」的基线和左边两格的数字底部对齐，
                // 不是节奏值，不要收进 S 令牌
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '$count 笔',
                  style: T.caption,
                ),
              ),
            ],
          ),
          if (pacing != null) ...[
            const SizedBox(height: S.lg),
            Divider(height: 1, thickness: hairlineOf(context), color: C.line),
            const SizedBox(height: S.md),
            Row(
              children: [
                // 左边让出剩余宽度：金额到五位数（12,000.00）时，
                // 两段文字并排会把右边「剩多少」顶出卡片 —— 真机上表现为右侧被裁
                Expanded(
                  child: Text(
                    '本期预算 ${Fmt.money(s.expenseCents)} / '
                    '${Fmt.money(cap)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caption.copyWith(color: dim),
                  ),
                ),
                const SizedBox(width: S.sm),
                Text(
                  s.overBudget
                      ? '超支 ${Fmt.money(s.overBudgetCents)}'
                      : '剩 ${Fmt.money(s.budgetLeftCents)}',
                  style: T.caption.copyWith(
                    fontWeight: FontWeight.w500,
                    color: s.overBudget ? C.over : C.ink,
                  ),
                ),
              ],
            ),
            // 借入计入预算时，卡片上的大数字是「额度 + 借入」（9,000），
            // 这一行说明那 3,000 是哪来的 —— 借来的钱确实能花，
            // 大数字若还停在 6,000，用户会以为预算没变。存的额度不动，下期自动还原。
            //
            // 措辞按用户口径：**额度在前、借入在括号里**。6,000 是基准，3,000 是加成，
            // 上一行的 9,000 是结果，三个数一眼能对上；倒过来写（「含借入 3,000（额度 6,000）」）
            // 得倒着读一遍才知道 9,000 怎么来的。
            if (borrowed > 0) ...[
              const SizedBox(height: 4),
              Text(
                '额度 ${Fmt.money(budget!)}（含借入 ${Fmt.money(borrowed)}）',
                style: T.overline,
              ),
            ],
            const SizedBox(height: S.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: LinearProgressIndicator(
                value: pacing.usedRatio.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: C.line2,
                // 未超支时用强调色：黑白灰版 accent == ink（视觉不变），
                // 黑塔版是咒法橙 —— 概览卡上唯一的大面积彩色，正好压在进度上
                valueColor: AlwaysStoppedAnimation(
                  s.overBudget ? C.over : C.accent,
                ),
              ),
            ),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Text(
                  '还剩 ${pacing.remainDays} 天',
                  style: T.overline,
                ),
                const Spacer(),
                Text(
                  '每天可花 ${Fmt.money(pacing.canSpendPerDayCents)}',
                  style: T.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: C.ink,
                  ),
                ),
              ],
            ),
          ] else if (summary != null)
            _NoBudgetSummary(pacing: summary),
        ],
      ),
    );
  }
}

/// 没设预算的期，底栏的替身：日均 / 环比上一期 / 最大一笔。
///
/// 存在的理由是**别让卡片塌掉**。以前翻到没预算的期，这一整块消失，
/// 卡片矮一半、下面的列表跳一下，空出来的地方还不说明任何事。
///
/// 三个数字的分工：
/// - **日均**是这期最经得起横向比较的数（期长 28–31 天不等，比总额不公平）；
/// - **环比**用日均比，不用总额比 —— 上期 31 天、这期 28 天时总额比会骗人；
/// - **最大一笔**是唯一能让人想起「这个月钱花哪儿了」的单点信息，比笔数有内容。
class _NoBudgetSummary extends StatelessWidget {
  const _NoBudgetSummary({required this.pacing});

  final Pacing pacing;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final dim = C.ink2;

    // 最大一笔从**已加载的这一期流水**里取，不发查询。
    // 只认「支出 + 正数」：支出里的负数是交叉归集（退款冲抵），它不是一笔花销。
    Txn? biggest;
    for (final t in s.txns) {
      if (t.type != TxnType.expense || t.amountCents <= 0) continue;
      if (biggest == null || t.amountCents > biggest.amountCents) biggest = t;
    }
    final cat = biggest == null ? null : s.categoryOf(biggest.categoryId)?.name;

    // 「已过 N 天」只对正在过的期有意义；看已经过完的期说「整期 N 天」
    final dayText = pacing.finished
        ? '整期 ${pacing.totalDays} 天'
        : '已过 ${pacing.passedDays} 天';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: S.lg),
        Divider(height: 1, thickness: hairlineOf(context), color: C.line),
        const SizedBox(height: S.md),
        Row(
          children: [
            Text(
              '日均 ${Fmt.money(pacing.perDayRealCents)}',
              style: T.caption.copyWith(color: dim),
            ),
            const Spacer(),
            Text(
              _compare(s, pacing),
              style: T.caption,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                biggest == null
                    ? ''
                    : '最大一笔 ${Fmt.money(biggest.amountCents)}'
                          '${cat == null ? '' : ' · $cat'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.overline,
              ),
            ),
            const SizedBox(width: S.sm),
            // 只放天数，不再重复「N 笔」—— 上面那行右边本来就写着笔数，
            // 一屏里同一个数字出现两次，只会让人怀疑是不是两个数
            Text(dayText, style: T.overline),
          ],
        ),
      ],
    );
  }

  /// 环比上一期，比的是**日均**。
  ///
  /// 措辞的四种情况都要说人话：上一期压根没记账 ≠ 上一期花了 0 元 ≠ 持平。
  /// 只有上期有真实支出时才算百分比，否则会出现「多 100%」「除以零」这类假话。
  String _compare(Store s, Pacing pacing) {
    final prev = s.prevPeriod;
    if (prev == null || prev.count == 0) return '上一期没有记账';
    final prevDaily = prev.expense ~/ (prev.days == 0 ? 1 : prev.days);
    if (prevDaily <= 0) return '上一期没有支出';
    final pct = ((pacing.perDayRealCents - prevDaily) * 100 / prevDaily)
        .round();
    if (pct == 0) return '与上一期持平';
    return pct > 0 ? '比上一期多 $pct%' : '比上一期少 ${-pct}%';
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
        Text(label, style: T.overline),
        const SizedBox(height: 2),
        // 金额可能很长（收入五位数 + 结余带符号），等比缩一点保证单行
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: T.amount.copyWith(fontWeight: FontWeight.w500),
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
        Text('筛选结果', style: T.section),
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
