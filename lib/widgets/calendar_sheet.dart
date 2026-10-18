import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/tokens.dart';
import '../store.dart';

/// 打开「本月日历」面板。
///
/// 每个月固定 6 行 × 7 列 —— 上下月补进来的日子也占格子，所以翻月时版式不会
/// 忽高忽低。格子里显示当天的支出金额（参考 app 的做法），点某天直接跳明细。
Future<void> showMonthCalendar(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const _MonthCalendar(),
  );
}

class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar();

  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  late String _month;
  Map<int, int> _expenseByDay = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 日历仍按月展示，但起点跟当前期走：翻到 9 月那期时不该还停在 10 月
    final from = Store.i.cycleFrom;
    _month = from.length >= 7 ? from.substring(0, 7) : Store.i.month;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await Repo.dailyTotals(Store.i.ledgerId, _month);
    if (!mounted) return;
    setState(() {
      _expenseByDay = {
        for (final (date, expense, _) in rows)
          if (expense > 0) int.parse(date.substring(8)): expense,
      };
      _loading = false;
    });
  }

  void _shift(int delta) {
    final y = int.parse(_month.substring(0, 4));
    final m = int.parse(_month.substring(5, 7));
    final next = DateTime(y, m + delta);
    _month = '${next.year}-${next.month.toString().padLeft(2, '0')}';
    _load();
  }

  void _pickDay(int day) {
    final date = '$_month-${day.toString().padLeft(2, '0')}';
    final s = Store.i;
    Navigator.pop(context);
    // 复用筛选那套：条件条、重置、与其它条件共存的行为都一致
    s.switchTab(0);
    s.applyFilter(TxnFilter(dateFrom: date, dateTo: date));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final y = int.parse(_month.substring(0, 4));
    final m = int.parse(_month.substring(5, 7));
    final totalDays = Fmt.daysInMonth(y, m);
    // 周日开头：DateTime.weekday 是 1(一)…7(日)
    final offset = DateTime(y, m, 1).weekday % 7;
    final today = Fmt.today();

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: C.bg3,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: C.line2,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: S.md),
            Row(
              children: [
                GestureDetector(
                  onTap: () => _shift(-1),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.chevron_left_rounded,
                        size: 22, color: C.ink2),
                  ),
                ),
                Expanded(
                  child: Text(
                    '$y年$m月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: C.ink,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _shift(1),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.chevron_right_rounded,
                        size: 22, color: C.ink2),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.close_rounded, size: 20, color: C.ink2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.sm),
            Row(
              children: [
                for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
                  Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: T.caption.copyWith(fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.xs),
            if (_loading)
              const SizedBox(
                height: 276,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: C.ink3),
                  ),
                ),
              )
            else
              SizedBox(
                height: 276, // 6 行 × 46
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 46,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: 42,
                  itemBuilder: (context, i) {
                    final day = i - offset + 1;
                    if (day < 1 || day > totalDays) {
                      return const SizedBox.shrink();
                    }
                    final date =
                        '$_month-${day.toString().padLeft(2, '0')}';
                    final isToday = date == today;
                    final amount = _expenseByDay[day];
                    return GestureDetector(
                      onTap: () => _pickDay(day),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isToday ? C.bg : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          border: isToday
                              ? Border.all(color: C.ink, width: 1.5)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.15,
                                fontWeight:
                                    isToday ? FontWeight.w600 : FontWeight.w400,
                                color: C.ink,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            if (amount != null)
                              Text(
                                Fmt.compact(amount).replaceAll('+', ''),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  height: 1.15,
                                  color: C.ink3,
                                  letterSpacing: -0.3,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: S.sm),
            Text(
              '点某一天，直接看那天的明细',
              style: T.caption.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
