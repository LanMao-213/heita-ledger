import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/tokens.dart';
import '../store.dart';

/// 打开日历卡片，返回用户点中的日期（`YYYY-MM-DD`，取消返回 null）。
///
/// 为什么是**上下滚动**而不是左右翻月：
/// 左右翻月要一次一次点，翻到三个月前得点三下，每翻一次整块日历都重画、
/// 眼睛还要重新定位。上下滚动把时间直接铺成一条线，一次滑动就能跨半年，
/// 而且「往上=更早、往下=更近」是所有人都熟悉的方向感。
Future<String?> showCalendarPicker(
  BuildContext context, {
  required String title,
  required String from,
  required String to,
  String? hint,
  String? initialMonth,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _CalendarPicker(
      title: title,
      from: from,
      to: to,
      hint: hint,
      initialMonth: initialMonth,
    ),
  );
}

/// 「点月份」的统一入口：弹日历，再把点中的日期换算成该跳的地方。
///
/// - [byMonth] 为 false（明细页 / 计划页 / 统计页的周期视图）→ 跳到那天所在的**期**
/// - [byMonth] 为 true（统计页的月份视图）→ 跳到那个**月**
Future<void> showCalendarAndGo(
  BuildContext context, {
  bool byMonth = false,
}) async {
  final s = Store.i;
  final from = byMonth ? Repo.monthStart(s.month) : s.cycleFrom;
  final to = byMonth ? Repo.monthEnd(s.month) : s.cycleTo;
  final date = await showCalendarPicker(
    context,
    title: byMonth ? '跳到哪个月' : '跳到哪一期',
    from: from,
    to: to,
    initialMonth: byMonth ? s.month : null,
    hint: byMonth
        ? null
        : '账单日 ${s.cycleStartDay} 号起算一期 · 点某天跳到它所在的期',
  );
  if (date == null) return;
  if (byMonth) {
    await s.goToMonth(date.substring(0, 7));
  } else {
    await s.goToCycleOf(date);
  }
}

class _CalendarPicker extends StatefulWidget {
  const _CalendarPicker({
    required this.title,
    required this.from,
    required this.to,
    this.hint,
    this.initialMonth,
  });

  final String title;

  /// 高亮区间（含两端）：周期视图给期首尾，月份视图给月初月末
  final String from;
  final String to;
  final String? hint;

  /// 打开时滚到哪个月，默认从高亮区间的第一天取
  final String? initialMonth;

  @override
  State<_CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends State<_CalendarPicker> {
  /// 每个月的块高固定 —— 只有定高，`initialScrollOffset` 才能一次算准，
  /// 否则要在首帧之后才知道要滚多远，打开时会闪一下。
  static const _blockH = 278.0;

  late final List<String> _months;
  late final ScrollController _ctl;
  late final int _initialIndex;

  @override
  void initState() {
    super.initState();
    final anchor = _monthOf(widget.initialMonth ?? widget.from);
    final thisMonth = Fmt.month(DateTime.now());

    // 往后留一个月（提前看下期），往前留两年（够翻回老账）
    final newest = _newer(thisMonth, anchor);
    final oldest = _older(thisMonth, anchor, 23);

    _months = [];
    var ym = newest;
    while (ym.compareTo(oldest) >= 0) {
      _months.add(ym);
      ym = _shiftYm(ym, -1);
    }
    _initialIndex = _months.indexOf(anchor).clamp(0, _months.length - 1);
    _ctl = ScrollController(initialScrollOffset: _initialIndex * _blockH);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  static String _monthOf(String ymd) =>
      ymd.length >= 7 ? ymd.substring(0, 7) : Fmt.month(DateTime.now());

  static String _shiftYm(String ym, int delta) {
    final y = int.parse(ym.substring(0, 4));
    final m = int.parse(ym.substring(5, 7));
    final d = DateTime(y, m + delta);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  static String _newer(String a, String b) => a.compareTo(b) > 0 ? a : b;

  static String _older(String a, String b, int months) {
    final base = a.compareTo(b) < 0 ? a : b;
    return _shiftYm(base, -months);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewPadding.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
        ),
        padding: const EdgeInsets.only(top: S.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: C.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.xl, S.md, S.sm, S.sm),
              child: Row(
                children: [
                  Text(widget.title, style: T.section),
                  const Spacer(),
                  TextButton(
                    // 没有左右翻月之后，滚远了要有个一键回到今天的出口
                    onPressed: () =>
                        Navigator.pop(context, Fmt.today()),
                    child: Text(
                      '今天',
                      style: T.caption.copyWith(
                        color: C.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(S.xl, 0, S.xl, S.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.hint!,
                    style: T.caption.copyWith(fontSize: 11.5),
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 430),
              child: ListView.builder(
                controller: _ctl,
                itemExtent: _blockH,
                itemCount: _months.length,
                padding: const EdgeInsets.symmetric(horizontal: S.md),
                itemBuilder: (context, i) => _monthBlock(_months[i]),
              ),
            ),
            const SizedBox(height: S.sm),
            Text(
              '点某一天，跳到它所在的期',
              style: T.caption.copyWith(fontSize: 11.5),
            ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }

  Widget _monthBlock(String ym) {
    final y = int.parse(ym.substring(0, 4));
    final m = int.parse(ym.substring(5, 7));
    final totalDays = Fmt.daysInMonth(y, m);
    // 周日开头：DateTime.weekday 是 1(一)…7(日)
    final offset = DateTime(y, m, 1).weekday % 7;
    final today = Fmt.today();

    return Column(
      children: [
        SizedBox(
          height: 30,
          child: Center(
            child: Text(
              Fmt.monthLabel(ym),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: C.ink,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
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
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 216, // 6 行 × 36
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 36,
              crossAxisSpacing: 2,
              mainAxisSpacing: 0,
            ),
            itemCount: 42,
            itemBuilder: (context, i) {
              final day = i - offset + 1;
              if (day < 1 || day > totalDays) return const SizedBox.shrink();

              final date = '$ym-${day.toString().padLeft(2, '0')}';
              final selected = date == widget.from;
              // 当前这一期铺一层浅灰，期有多长、跨了两个月哪几天，
              // 一眼就能看出来 —— 这是日历比列表多出来的那点信息。
              final inRange =
                  date.compareTo(widget.from) >= 0 && date.compareTo(widget.to) <= 0;
              final isToday = date == today;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context, date),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? C.ink
                        : (inRange ? C.bg2 : Colors.transparent),
                    borderRadius: BorderRadius.circular(10),
                    border: isToday && !selected
                        ? Border.all(color: C.ink, width: 1.4)
                        : null,
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: selected || isToday
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: selected ? C.bg : C.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: S.sm),
        Container(height: 1, color: C.line),
      ],
    );
  }
}
