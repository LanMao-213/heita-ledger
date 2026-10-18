import 'package:flutter/material.dart';

import '../data/cycle.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/tokens.dart';
import '../store.dart';

/// 打开「跳到哪一期」面板。
///
/// 明细页的月份选择器换成这个：既然翻页是「一期一期」翻的，跳转也该按期列，
/// 列月份会让人以为还能按月跳。每行带当期支出，等于顺手做了个「哪期花了多少」
/// 的速览 —— 这也是原生日历面板在周期口径下唯一还讲得通的部分。
Future<void> showPeriodPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const _PeriodPicker(),
  );
}

class _PeriodPicker extends StatefulWidget {
  const _PeriodPicker();

  @override
  State<_PeriodPicker> createState() => _PeriodPickerState();
}

class _PeriodPickerState extends State<_PeriodPicker> {
  /// 往前 11 期、往后 2 期 —— 往后跳是为「提前看下期预算」，再远没意义
  static const _back = 11;
  static const _forward = 2;

  List<(String from, String to, int expense)> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = Store.i;
    final base = s.cycleFrom.isEmpty
        ? cycleRange(DateTime.now(), s.cycleStartDay).$1
        : s.cycleFrom;

    final out = <(String, String, int)>[];
    for (var i = -_back; i <= _forward; i++) {
      final from = shiftCycleDate(base, s.cycleStartDay, i);
      final to = Fmt.date(
        shiftCycle(DateTime.parse(from), s.cycleStartDay, 1)
            .subtract(const Duration(days: 1)),
      );
      final totals = await Repo.rangeTotals(s.ledgerId, from, to);
      out.add((from, to, totals.$1));
    }
    if (!mounted) return;
    setState(() {
      _rows = out.reversed.toList(); // 新的在上
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Container(
      decoration: const BoxDecoration(
        color: C.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
      ),
      padding: const EdgeInsets.only(top: S.md, bottom: S.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: C.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.xl, S.md, S.xl, S.sm),
            child: Row(
              children: [
                Text('跳到哪一期', style: T.section),
                const Spacer(),
                Text('账单日 ${s.cycleStartDay} 号', style: T.caption),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(
              height: 160,
              child: Center(child: Text('加载中…', style: T.caption)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: S.md),
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final r = _rows[i];
                  final on = r.$1 == s.cycleFrom;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.pop(context);
                      s.goToCycleOf(r.$1);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: S.md,
                        vertical: S.md,
                      ),
                      decoration: BoxDecoration(
                        color: on ? C.ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: Row(
                        children: [
                          Text(
                            cycleLabel(r.$1, r.$2),
                            style: T.body.copyWith(
                              color: on ? C.bg : C.ink,
                              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            r.$3 == 0 ? '—' : Fmt.money(r.$3),
                            style: T.amountSm.copyWith(
                              fontSize: 13,
                              color: on ? C.bg : C.ink2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
