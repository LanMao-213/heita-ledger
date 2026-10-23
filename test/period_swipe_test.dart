// 周期条的手势：左右轻扫换期、双击回到当前。
//
// 箭头去掉之后，「翻页」这件事只剩手势一条路 —— 一旦阈值或方向写错，
// 用户就没有别的办法翻期了，所以这几条要钉死。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/cycle.dart' as cyc;
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/common.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_period_swipe.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<void> _freshDb() async {
  await Db.close();
  Db.fileName = _dbName;
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();
  await Db.open();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  test('backToCurrentCycle：翻了三期之后一键回到今天所在的期', () async {
    await _freshDb();
    await Store.i.boot();
    final s = Store.i;
    final (todayFrom, _) = cyc.cycleRange(DateTime.now(), s.cycleStartDay);

    await s.shiftCycle(3);
    expect(s.cycleFrom, isNot(todayFrom));

    await s.backToCurrentCycle();
    expect(s.cycleFrom, todayFrom);
  });

  test('backToCurrentStat：本期口径回本期，月度口径回本月，互不干扰', () async {
    await _freshDb();
    await Store.i.boot();
    final s = Store.i;
    final (todayFrom, _) = cyc.cycleRange(DateTime.now(), s.cycleStartDay);
    final thisMonth = Fmt.month(DateTime.now());

    // 本期口径
    await s.shiftStat(-2);
    await s.backToCurrentStat();
    expect(s.statFrom, todayFrom);

    // 月度口径：只该动 month，不该把周期游标也拽回今天
    s.statBasis = StatBasis.month;
    await s.shiftCycle(2);
    final movedCycleFrom = s.cycleFrom;
    await s.shiftStat(-3);
    await s.backToCurrentStat();
    expect(s.month, thisMonth);
    expect(s.cycleFrom, movedCycleFrom, reason: '月度口径不该动周期游标');
  });

  testWidgets('周期条：没有箭头，左滑=下一期、右滑=上一期、双击=回本期', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // 手势只验「接线方向」：回调里不碰数据库。
    // 假时钟里 await 真实 I/O 会挂住（见交接说明第 4 节），
    // 所以翻期/回本期真正做了什么，由上面两条 Store 单测负责。
    var prev = 0, next = 0, reset = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CycleBar(
            from: '2026-10-15',
            to: '2026-11-14',
            onPrev: () => prev++,
            onNext: () => next++,
            onTapLabel: () {},
            onReset: () => reset++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 箭头已经去掉；区间用「至」
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    // 区间文案在 2026-10-23 从小号的「10-15 至 11-14」换成了大号中文
    // 「10月15日 – 11月14日」：升到 20px 之后，点分数字会被读成金额，
    // 而两个短横加一个「至」在一行里是三条分隔符。见 cycle.dart#longRangeLabel。
    expect(find.text('10月15日 – 11月14日'), findsOneWidget);

    // 左滑 → 下一期
    await tester.drag(find.byType(CycleBar), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(next, 1, reason: '左滑应该翻到下一期');
    expect(prev, 0);

    // 右滑 → 上一期
    await tester.drag(find.byType(CycleBar), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(prev, 1);
    expect(next, 1);

    // 轻点（位移和速度都不够）不算翻页
    await tester.drag(find.byType(CycleBar), const Offset(-12, 0));
    await tester.pumpAndSettle();
    expect(next, 1, reason: '手指抖一下不该翻页');

    // 双击 → 回到当前
    final label = find.text('10月15日 – 11月14日');
    await tester.tap(label);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(label);
    await tester.pump();
    expect(reset, 1, reason: '双击应该触发「回到当前」');

    // 双击识别器会挂一个 kDoubleTapTimeout 的判定窗口，跑完再结束用例
    await tester.pump(const Duration(milliseconds: 400));
  });
}
