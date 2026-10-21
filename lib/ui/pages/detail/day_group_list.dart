import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// 一天的分组（日卡）。
///
/// 当日小计用 [TxnSum.bySide] 现算，**借贷流水不进小计**（口径 3.5）：
/// 借出去的钱不是消费，混进「今日支出」会让用户以为今天花多了。
class DayGroup {
  const DayGroup({
    required this.date,
    required this.items,
    required this.expenseCents,
    required this.incomeCents,
  });

  final LocalDate date;
  final List<Txn> items;
  final int expenseCents;
  final int incomeCents;

  bool get hasIncome => incomeCents != 0;
  bool get hasExpense => expenseCents != 0;
}

/// 按日分组。日期倒序、同日内 id 倒序（与 keyset 的排序键一致）。
List<DayGroup> groupByDay(Iterable<Txn> txns) {
  final Map<LocalDate, List<Txn>> buckets = <LocalDate, List<Txn>>{};
  for (final Txn t in txns) {
    buckets.putIfAbsent(t.date, () => <Txn>[]).add(t);
  }
  final List<LocalDate> days = buckets.keys.toList()..sort((LocalDate a, LocalDate b) => b.compareTo(a));
  return <DayGroup>[
    for (final LocalDate d in days)
      DayGroup(
        date: d,
        items: buckets[d]!..sort(
          (Txn a, Txn b) => (b.id ?? 0).compareTo(a.id ?? 0),
        ),
        expenseCents: TxnSum.bySide(buckets[d]!, TxnType.expense),
        incomeCents: TxnSum.bySide(buckets[d]!, TxnType.income),
      ),
  ];
}

/// 日卡头：`10-16 周五` + 右侧「收入 X / 支出 Y」。
///
/// 「收入 X / 支出 Y」**有才显示** —— 只有支出的日子多写一个「收入 0.00」
/// 纯属噪音。
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.group});

  final DayGroup group;

  static const List<String> _week = <String>['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String left =
        '${group.date.month.toString().padLeft(2, '0')}-${group.date.day.toString().padLeft(2, '0')}'
        ' 周${_week[group.date.weekday - 1]}';

    final List<String> parts = <String>[
      if (group.hasIncome) '收入 ${_yuan(group.incomeCents)}',
      if (group.hasExpense) '支出 ${_yuan(group.expenseCents)}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.page, S.md, S.page, 2),
      child: Row(
        children: <Widget>[
          Text(left, style: Ts.caption.copyWith(color: pal.ink3)),
          const Spacer(),
          if (parts.isNotEmpty)
            Text(
              parts.join(' / '),
              key: ValueKey<String>('day-subtotal-${group.date.iso}'),
              style: Ts.caption.copyWith(color: pal.ink2),
            ),
        ],
      ),
    );
  }

  static String _yuan(int cents) {
    final int v = cents.abs();
    return '${cents < 0 ? '-' : ''}¥${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
  }
}
