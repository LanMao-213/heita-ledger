import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../core/period.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../sheet_frame.dart';

/// 日历选择器（明细页单击概览卡时弹）。返回选中的日期；取消返回 `null`。
///
/// 只有「选一天跳到它所在的那一期」一个用途，所以：
/// - 不做区间选择（区间在筛选面板里）；
/// - 允许点未来（未来期会有预算但要能提前看 → 由调用方决定是否跳）；
/// - 今天的格子用 `todayMark` 圆点标出来。
Future<LocalDate?> showCalendarSheet(
  BuildContext context, {
  required LocalDate initial,
}) {
  return showModalBottomSheet<LocalDate>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _CalendarBody(initial: initial),
  );
}

class _CalendarBody extends StatefulWidget {
  const _CalendarBody({required this.initial});

  final LocalDate initial;

  @override
  State<_CalendarBody> createState() => _CalendarBodyState();
}

class _CalendarBodyState extends State<_CalendarBody> {
  late LocalDate _month = LocalDate(widget.initial.year, widget.initial.month, 1);

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final LocalDate today = LocalDate.today();
    final int days = LocalDate.daysInMonth(_month.year, _month.month);
    // 该月 1 号是周几（1=周一）；网格从周一开始
    final int lead = _month.weekday - 1;

    return SheetFrame(
      title: monthLabel(_month.ym),
      trailing: Row(
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('cal-prev'),
            onPressed: () => setState(() => _month = _month.addMonths(-1)),
            icon: Icon(Icons.chevron_left, size: 20, color: pal.ink2),
          ),
          IconButton(
            key: const ValueKey<String>('cal-next'),
            onPressed: () => setState(() => _month = _month.addMonths(1)),
            icon: Icon(Icons.chevron_right, size: 20, color: pal.ink2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final String w in <String>['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: Ts.badge.copyWith(color: pal.ink3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.sm),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.15,
            ),
            itemCount: lead + days,
            itemBuilder: (BuildContext ctx, int i) {
              if (i < lead) return const SizedBox.shrink();
              final LocalDate d = LocalDate(_month.year, _month.month, i - lead + 1);
              final bool isToday = d == today;
              final bool isSelected = d == widget.initial;
              return InkWell(
                key: ValueKey<String>('cal-day-${d.iso}'),
                onTap: () => Navigator.of(ctx).pop(d),
                borderRadius: R.rSm,
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? pal.surfaceAlt : null,
                    borderRadius: R.rSm,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        '${d.day}',
                        style: Ts.body2.copyWith(color: pal.ink),
                      ),
                      if (isToday)
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: pal.todayMark,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: S.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey<String>('cal-today'),
              onPressed: () => Navigator.of(context).pop(today),
              child: Text(
                '回今天',
                style: Ts.body.copyWith(color: pal.ink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
