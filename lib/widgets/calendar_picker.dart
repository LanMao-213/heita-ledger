import 'package:flutter/material.dart';

import '../data/cycle.dart';
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
/// 为什么是**一条连续的周列表**而不是一个个月块：
/// 按月分块时，块与块之间必然夹着「上月末半行空位 + 本月首半行空位」，
/// 同一个星期会被画两遍，日期读起来是断的。改成整条日历按周铺开之后，
/// 10 月 31 日（周六）下面紧接着就是 11 月 1 日（周日），中间不留缝。
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
    builder: (_) =>
        _CalendarPicker(from: from, to: to, initialMonth: initialMonth),
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
  /// 一行的固定高度。每格「日期 + 金额」都按这个高度绝对定位，
  /// 所以某个日期下面有没有金额，都不会把日期本身顶上去。
  static const _rowH = 52.0;

  /// 日历格子的边长（今天的实心圆就是这个尺寸）
  static const _dot = 30.0;

  late final String _anchorYm;
  late String _oldestYm;
  late String _newestYm;

  /// 第一格（最早那个月上月里的周日）—— 所有行号都相对它算
  late final DateTime _base;
  late final int _rowCount;

  late final ScrollController _ctl;

  /// 当前「当月」：滚动中心落在哪个月，哪个月就是黑的，其余灰
  late String _activeYm;

  /// 首帧跳转只做一次
  bool _jumped = false;

  /// ListView 上留白：让最早/最晚的月份也能滚到中间，不然首尾贴边
  double _topPad = 0;

  /// 日 → 当日支出（分）。打开后一次查完，滚动时只读不发请求
  Map<String, int> _daily = const {};

  final String _today = Fmt.today();

  @override
  void initState() {
    super.initState();
    _anchorYm = _monthOf(widget.initialMonth ?? widget.from);

    // 范围跟着「今天」走（往前两年、往后三个月），不是写死的上下限 ——
    // 到 2027 年 2 月再打开，上界自己就变成 2027-05
    final range = calendarRange(_anchorYm);
    _oldestYm = range.$1;
    _newestYm = range.$2;

    // 整条日历的起止：最早月 1 号所在周的周日 → 最晚月最后一天所在周的周六。
    // 用 UTC 做日加减，避免夏令时把「差几天」算错（国内没有，但别留坑）
    final firstDay = _utcOf(_oldestYm);
    final lastMonth = _utcOf(_newestYm);
    final lastDay = DateTime.utc(
      lastMonth.year,
      lastMonth.month,
      Fmt.daysInMonth(lastMonth.year, lastMonth.month),
    );
    _base = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final end = lastDay.add(Duration(days: 6 - lastDay.weekday % 7));
    _rowCount = end.difference(_base).inDays ~/ 7 + 1;

    _activeYm = _anchorYm;
    _ctl = ScrollController()..addListener(_syncActive);
    _loadDaily();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  static DateTime _utcOf(String ym) => DateTime.utc(
    int.parse(ym.substring(0, 4)),
    int.parse(ym.substring(5, 7)),
  );

  static String _monthOf(String ymd) =>
      ymd.length >= 7 ? ymd.substring(0, 7) : Fmt.month(DateTime.now());

  /// 第 [i] 格是哪天
  String _dateAt(int i) => Fmt.date(_base.add(Duration(days: i)));

  /// 某月 1 号落在第几行
  int _rowOf(String ym) => _utcOf(ym).difference(_base).inDays ~/ 7;

  /// 一次把这两年多的每日支出取完：一次查询，滚动时不再发请求
  Future<void> _loadDaily() async {
    final ledgerId = Store.i.ledgerId;
    final rows = await Repo.rangeDailyTotals(
      ledgerId,
      Repo.monthStart(_oldestYm),
      Repo.monthEnd(_newestYm),
      basis: DateBasis.date,
    );
    if (!mounted) return;
    setState(() => _daily = {for (final r in rows) r.$1: r.$2});
  }

  /// 视口里**格数最多**的那个月算当月。
  ///
  /// 不用「视口中心点落在哪」—— 滑到月界那一瞬间，中心点可能正好压在
  /// 下个月的第一天，可画面里九成还是上个月，结果整屏都是灰的、
  /// 只有露出五个格的下个月是黑的，读起来完全反了。按格数投票才跟眼睛一致。
  void _syncActive() {
    if (!_ctl.hasClients) return;
    final vh = _ctl.position.viewportDimension;
    if (vh <= 0) return;

    final first = ((_ctl.offset - _topPad) / _rowH).floor();
    final last = ((_ctl.offset + vh - _topPad) / _rowH).ceil();
    final counts = <String, int>{};
    for (var r = first; r <= last; r++) {
      if (r < 0 || r >= _rowCount) continue;
      for (var c = 0; c < 7; c++) {
        final ym = _dateAt(r * 7 + c).substring(0, 7);
        counts[ym] = (counts[ym] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return;

    var bestYm = _activeYm;
    var best = 0;
    for (final e in counts.entries) {
      if (e.value > best) {
        best = e.value;
        bestYm = e.key;
      }
    }
    if (bestYm != _activeYm) setState(() => _activeYm = bestYm);
  }

  /// 首帧把打开那个月摆到视口正中：上面露出上月末、下面露出下月头，
  /// 当月占满中间那一段，才能一眼看出「哪几行是黑的」。
  void _scheduleJump() {
    if (_jumped) return;
    _jumped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctl.hasClients) return;
      final vh = _ctl.position.viewportDimension;
      // 当月占的行区间是 [r0, r1)，取中点对齐视口中心
      final r0 = _rowOf(_anchorYm);
      final r1 = _rowOf(Fmt.shiftMonth(_anchorYm, 1));
      final target = _topPad + ((r0 + r1) / 2) * _rowH - vh / 2;
      _ctl.jumpTo(target.clamp(0.0, _ctl.position.maxScrollExtent));
      _syncActive();
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 高度只给「当月 + 上下各一行」：多出来的行只是灰色上/下月，
    // 占着屏幕不干活。月行数 4–6 不等，所以高度跟着当月走，不是写死的
    final rows = _rowOf(Fmt.shiftMonth(_anchorYm, 1)) - _rowOf(_anchorYm);
    final h = ((rows + 2) * _rowH).clamp(260.0, 470.0);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewPadding.bottom),
      child: Container(
        decoration: const BoxDecoration(
          // 抽屉面用「卡面」而不是「页面底」：露露缇雅版的底是天青，
          // 抽屉再铺一层天青就成了整片蓝；卡面是暖白，读起来才是「纸」
          color: C.cardBg,
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
            SizedBox(
              height: h,
              child: LayoutBuilder(
                builder: (context, cons) {
                  // 上下各留一行：滚到最早/最晚的那一端时，那个月刚好完整停住，
                  // 只多出一行灰的邻月 —— 和打开时的样子对称，不会露出半屏空白
                  _topPad = _rowH;
                  _scheduleJump();
                  return Stack(
                    children: [
                      // 水印在最底层，日期画在它上面
                      _watermark(),
                      ListView.builder(
                        controller: _ctl,
                        itemExtent: _rowH,
                        itemCount: _rowCount,
                        padding: EdgeInsets.only(top: _topPad, bottom: _rowH),
                        itemBuilder: (context, i) => _weekRow(i),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 吸顶头：年份 + 周几。两行都在滚动区外，滑到哪一年都看得见。
  /// 月份不再写成文字 —— 它由背后那个大水印和「当月变黑」共同表达。
  Widget _stickyHead() {
    final year = _activeYm.substring(0, 4);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, 2),
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
                    child: Text(w, style: T.caption.copyWith(fontSize: 11)),
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

  /// 背景月份：整块铺一个超大淡字。
  ///
  /// 不引外部字体 —— 系统字体换一套就跟着变，反而不好控。靠三件事把它做「胖」：
  /// 字重 w900、横向拉伸 18%、两位数字之间收负字距。浓度从 3% 提到 7.5%，
  /// 手机屏幕小、灰度层次本来就压缩，3% 基本看不见。
  ///
  /// 跟着当月区块走，而不是钉在屏幕中间：钉死的话它会同时压在上下两个月身上，
  /// 那些本来就淡（ink4）的日期被水印一盖就糊成一片。
  Widget _watermark() {
    final m = '${int.parse(_activeYm.substring(5, 7))}';
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctl,
          builder: (context, _) {
            if (!_ctl.hasClients) return const SizedBox.shrink();
            final vh = _ctl.position.viewportDimension;
            if (vh <= 0) return const SizedBox.shrink();
            final r0 = _rowOf(_activeYm);
            final r1 = _rowOf(Fmt.shiftMonth(_activeYm, 1));
            // 当月占 [r0, r1) 行，区块中心的 y 再补半行；
            // 数字字形的视觉重心比文字盒偏上，再往下压 16 才是「看着居中」
            final cy =
                _topPad + (r0 + r1) / 2 * _rowH + _rowH / 2 - _ctl.offset + 16;
            return Stack(
              children: [
                Positioned(
                  top: cy - 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: Transform(
                        key: ValueKey(m),
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(1.18, 1, 1),
                        child: Text(
                          m,
                          style: const TextStyle(
                            fontSize: 216,
                            fontWeight: FontWeight.w900,
                            // 月份水印：浅底是黑 6%，暗底是骨白 8%（C.inkWash）
                            color: C.inkWash,
                            height: 0.92,
                            letterSpacing: -6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _weekRow(int row) {
    return Row(
      children: [
        for (var c = 0; c < 7; c++)
          Expanded(child: _dayCell(_dateAt(row * 7 + c))),
      ],
    );
  }

  Widget _dayCell(String date) {
    final day = int.parse(date.substring(8, 10));
    final ym = date.substring(0, 7);
    final isToday = date == _today;
    final isActive = ym == _activeYm;
    // 这一期之外的日子再浅一档：不给整片涂底，也能看出期从哪天起
    final inPeriod =
        date.compareTo(widget.from) >= 0 && date.compareTo(widget.to) <= 0;
    final cents = _daily[date] ?? 0;

    // 三档灰度：当月+当期最黑 → 当月但不在期（深灰，仍读得出「这个月」）
    // → 不在当月（最淡）。当月那一档要压得住非当月，否则滚过月界时整屏
    // 会一起变浅，看不出「换月了」
    final Color fg;
    if (isToday) {
      fg = C.onTodayMark;
    } else if (!isActive) {
      fg = C.ink4;
    } else if (!inPeriod) {
      fg = C.ink2;
    } else {
      fg = C.ink;
    }

    return GestureDetector(
      // 带上日期的 key：同屏有上月末、本月、下月初三个「1」，
      // 测试（和将来的自动化）只能靠这个精确点名
      key: ValueKey('cal-$date'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context, date),
      child: Stack(
        children: [
          // 日期固定在行高顶部：下面有没有金额，它都在同一个位置
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: _dot,
                height: _dot,
                alignment: Alignment.center,
                decoration: isToday
                    ? const BoxDecoration(
                        color: C.todayMark,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 17.5,
                    height: 1,
                    letterSpacing: -0.4,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          if (cents > 0)
            Positioned(
              top: 34,
              left: 0,
              right: 0,
              child: Text(
                amountLabel(cents),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: isActive ? C.ink3 : C.ink4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
