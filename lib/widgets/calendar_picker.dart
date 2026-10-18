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
///
/// 顶上是**真正吸顶**的两行（年份 + 周几）：它们不在滚动区里，滑多远都在。
Future<String?> showCalendarPicker(
  BuildContext context, {
  required String from,
  required String to,
  String? initialMonth,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _CalendarPicker(
      from: from,
      to: to,
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
    from: from,
    to: to,
    initialMonth: byMonth ? s.month : null,
  );
  if (date == null) return;
  if (byMonth) {
    await s.goToMonth(date.substring(0, 7));
  } else {
    await s.goToCycleOf(date);
  }
}

/// 日历里一天的金额怎么显示：格子只有 44 宽，整元/千位要压缩，
/// 否则「1,234.00」会把格子撑破。
String amountLabel(int cents) {
  final yuan = cents / 100;
  if (yuan >= 1000) return '${(yuan / 1000).toStringAsFixed(1)}k';
  if (yuan >= 100) return yuan.round().toString();
  // 34.00 → 34；12.50 → 12.5（末尾的零全部去掉，不只去一个）
  var s = yuan.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

class _CalendarPicker extends StatefulWidget {
  const _CalendarPicker({
    required this.from,
    required this.to,
    this.initialMonth,
  });

  /// 高亮区间（含两端）：周期视图给期首尾，月份视图给月初月末
  final String from;
  final String to;

  /// 打开时滚到哪个月，默认从高亮区间的第一天取
  final String? initialMonth;

  @override
  State<_CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends State<_CalendarPicker> {
  /// 每个月的块高固定 —— 只有定高，`initialScrollOffset` 才能一次算准，
  /// 否则要在首帧之后才知道要滚多远，打开时会闪一下。
  /// 34（月份标签带）+ 6 行 × 50 + 8 余量。
  static const _blockH = 342.0;

  late final List<String> _months;
  late final ScrollController _ctl;
  late final int _initialIndex;

  /// 吸顶那一行显示哪一年 —— 跟着滚动走，不是写死的今年
  late String _visibleYm;

  /// 日 → 当日支出（分）。打开后一次查完，滚动时只读不发请求
  Map<String, int> _daily = const {};

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
    _visibleYm = _months[_initialIndex];
    _ctl = ScrollController(initialScrollOffset: _initialIndex * _blockH)
      ..addListener(_onScroll);
    _loadDaily();
  }

  void _onScroll() {
    final i = (_ctl.offset / _blockH).round().clamp(0, _months.length - 1);
    final ym = _months[i];
    if (ym != _visibleYm) setState(() => _visibleYm = ym);
  }

  /// 一次把这两年多的每日支出取完：一次查询，滚动时不再发请求
  Future<void> _loadDaily() async {
    final ledgerId = Store.i.ledgerId;
    final rows = await Repo.rangeDailyTotals(
      ledgerId,
      Repo.monthStart(_months.last),
      Repo.monthEnd(_months.first),
      basis: DateBasis.date,
    );
    if (!mounted) return;
    setState(() => _daily = {for (final r in rows) r.$1: r.$2});
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
            _stickyHead(),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (media.size.height * 0.58).clamp(320.0, 470.0),
              ),
              child: ListView.builder(
                controller: _ctl,
                itemExtent: _blockH,
                itemCount: _months.length,
                padding: EdgeInsets.zero,
                itemBuilder: (context, i) => _monthBlock(_months[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 吸顶头：年份 + 周几。两行都在滚动区外，滑到哪一年都看得见
  Widget _stickyHead() {
    final year = _visibleYm.substring(0, 4);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              year,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: C.ink,
                letterSpacing: 0.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.lg),
          child: Row(
            children: [
              for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: T.caption.copyWith(fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: S.sm),
        Container(height: 1, color: C.line),
      ],
    );
  }

  Widget _monthBlock(String ym) {
    final y = int.parse(ym.substring(0, 4));
    final m = int.parse(ym.substring(5, 7));
    final totalDays = Fmt.daysInMonth(y, m);
    // 周日开头：DateTime.weekday 是 1(一)…7(日)
    final offset = DateTime(y, m, 1).weekday % 7;
    final today = Fmt.today();
    final cells = <int>[
      ...List.filled(offset, 0),
      for (var d = 1; d <= totalDays; d++) d,
    ];
    while (cells.length < 42) {
      cells.add(0);
    }

    return SizedBox(
      height: _blockH,
      child: Stack(
        children: [
          // 月份做背景：整块铺一个超大淡字，日期压在上面。
          // 2% 的浓度只提供「现在是几月」的空间感，不参与读数。
          Positioned.fill(
            child: Center(
              child: Text(
                '$m',
                style: const TextStyle(
                  fontSize: 190,
                  fontWeight: FontWeight.w700,
                  color: Color(0x0814161A),
                  height: 1,
                ),
              ),
            ),
          ),
          Column(
            children: [
              SizedBox(
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.lg, 14, S.lg, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$m 月',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: C.ink2,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              for (var w = 0; w < 6; w++)
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: cells[w * 7 + i] == 0
                            ? const SizedBox(height: 50)
                            : _dayCell(ym, cells[w * 7 + i], today),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(String ym, int day, String today) {
    final date = '$ym-${day.toString().padLeft(2, '0')}';
    final isToday = date == today;
    // 这一期之外的日子用浅一档的字色：不给整片涂底，也能看出期从哪天起
    final inPeriod =
        date.compareTo(widget.from) >= 0 && date.compareTo(widget.to) <= 0;
    final cents = _daily[date] ?? 0;

    return SizedBox(
      height: 50,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context, date),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: isToday
                  ? const BoxDecoration(color: C.ink, shape: BoxShape.circle)
                  : null,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 16.5,
                  height: 1.1,
                  fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                  color: isToday ? C.bg : (inPeriod ? C.ink : C.ink3),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (cents > 0)
              Text(
                amountLabel(cents),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 9.5,
                  height: 1.3,
                  color: C.ink4,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
