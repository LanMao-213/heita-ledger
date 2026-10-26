// 明细页「横滑翻期」的自检（1.4.5，方案 B）。
//
// 方案 B 的全部价值就在一条边界上：**横向手势只归顶部概览卡，列表正文仍然归
// `PageView`**。所以这里验的不是「能翻期」，而是「翻期没有把切 Tab 吃掉」——
// 后者才是这条方案能被选中的理由。如果哪天有人把热区从概览卡放大到整页
// （方案 A），第 2 条用例会立刻红 —— 那是**故意**的，改之前先想清楚
// 「明细页还能不能横滑切 Tab」。
//
// 三条用例各自钉一件事：
//   1) 概览卡上**右滑** → 翻到上一期、**tabIndex 还是 0**、列表回顶；
//   1b) 停在本期时左滑 → 不动（1.4.6 的右边界：不许翻到未来期）；
//   2) 列表正文横滑 → 仍然切到图表页（方案 B 的边界）；
//   3) 筛选态下概览卡横滑 → 不翻期，且手势落回外层（tabIndex 变 1）。
//      这条是靠「不注册识别器」实现的，靠 return 拦会表现为「滑了没反应」。
//
// 另有两条小而关键的：双击回本期、期外不再自称「本期支出」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart';
import 'package:ledger/data/cycle.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/detail_page.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/detail/summary_card.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_detail_swipe.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  /// 建库 + 造 12 笔（够把列表撑到需要滚动）。
  ///
  /// 必须撑得过一屏：第 1 条用例要验「翻期后回顶」，列表不可滚的话
  /// 偏移恒为 0，那条断言就等于没写。
  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Db.close();
      final f = File(await _dbPath());
      if (f.existsSync()) f.deleteSync();

      await Store.i.boot();
      final s = Store.i;
      final catId = s.expenseCats.first.id;
      final accId = s.accounts.first.id;
      final today = DateTime.now();

      for (var i = 0; i < 12; i++) {
        await Repo.insertTxn(
          Txn(
            id: 0,
            ledgerId: s.ledgerId,
            type: TxnType.expense,
            amountCents: 100 + i,
            // 往前铺 12 天：同一天会合并成一张卡，撑不满屏
            date: Fmt.date(today.subtract(Duration(days: i))),
            categoryId: catId,
            accountId: accId,
            note: '第 $i 笔',
          ),
        );
      }
      await s.loadCycle();
      await s.loadStats();
      // Store 是单例：上一个用例留下的筛选态会带过来，这里必须清干净，
      // 否则概览卡是「筛选结果」态，横滑热区根本没注册。
      await s.clearFilter();
      // 同理，tabIndex 也会带过来。上一个用例横滑切到了图表页的话，
      // 这一条里「(195,70) 那一下」会落在统计页的周期条上 —— 那里的
      // 横滑是 shiftStat，会真的把期翻掉。踩过，别删。
      s.switchTab(0);
    });
  }

  /// 让真实查询回包（不用 pumpAndSettle：进度条一直在动，永远等不到静止）
  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 25 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const HeitaApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DetailPage())),
    );
    await tester.pump();
  }

  /// 概览卡在「正常态」下的中心点由 `getCenter` 现算，不写死坐标 ——
  /// 卡片高度随预算块、金额行数变化，写死一行数字迟早对不上。
  testWidgets('概览卡右滑：翻到上一期，不切 Tab，列表回顶', (tester) async {
    await seed(tester);
    await pumpApp(tester);
    final s = Store.i;
    final from = s.cycleFrom;

    final pos = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    // 往下挪 60：既让「回顶」有东西可验，又保证卡片中心还在可视区内
    // （滑太多卡片就整块滚出去了，没地方落手指）
    pos.jumpTo(60);
    await tester.pump();
    expect(pos.pixels, greaterThan(0), reason: '前提：列表得先滚下去');

    // 右滑 = 上一期。**不能用左滑**：1.4.6 起今天所在的期就是右边界，
    // 往未来翻被禁了（见下面那条用例），从本期左滑什么都不会发生。
    final card = tester.getCenter(find.byType(SummaryCard));
    await tester.flingFrom(card, const Offset(320, 0), 1200);
    // 等 isCurrentPeriod 变 false，而不是等 cycleFrom 变 ——
    // shiftCycle 先改 cycleFrom 再 await loadCycle，只等前者会读到旧的口径标志
    await waitUntil(tester, () => !s.isCurrentPeriod);

    expect(s.cycleFrom, isNot(from), reason: '右滑要翻到上一期');
    expect(s.tabIndex, 0, reason: '翻期不许把明细页的横滑切 Tab 一起吃掉');
    expect(s.isCurrentPeriod, isFalse);
    expect(pos.pixels, 0, reason: '翻期后必须回顶，否则会停在上一期的半截位置');
  });

  testWidgets('停在本期时左滑：不许翻到未来，什么都不变', (tester) async {
    await seed(tester);
    await pumpApp(tester);
    final s = Store.i;
    final from = s.cycleFrom;
    expect(s.isCurrentPeriod, isTrue, reason: '前提：从本期出发');

    final card = tester.getCenter(find.byType(SummaryCard));
    await tester.flingFrom(card, const Offset(-320, 0), 1200);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      s.cycleFrom,
      from,
      reason: '未来期不可能有账，翻过去只有一片 0.00，分不清「没记账」还是「翻过头了」',
    );
    expect(s.isCurrentPeriod, isTrue);
    expect(s.tabIndex, 0, reason: '翻不动也不能把这一下漏给外层去切 Tab');
  });

  testWidgets('列表正文横滑：仍然切到图表页（方案 B 的边界）', (tester) async {
    await seed(tester);
    await pumpApp(tester);
    final s = Store.i;
    final from = s.cycleFrom;

    // 正文区域的中心点：概览卡只占顶部一条，这里落不到它上面
    final body = tester.getCenter(find.byType(CustomScrollView));
    await tester.flingFrom(body, const Offset(-320, 0), 1200);

    await waitUntil(tester, () => s.tabIndex != 0);
    expect(s.tabIndex, 1, reason: '列表正文横滑还是切 Tab —— 这是选方案 B 的理由');
    expect(s.cycleFrom, from, reason: '正文横滑不该顺手翻期');
  });

  testWidgets('筛选态下概览卡横滑：不翻期，手势落回外层', (tester) async {
    await seed(tester);
    await pumpApp(tester);
    final s = Store.i;
    final from = s.cycleFrom;

    await tester.runAsync(() async {
      await s.applyFilter(const TxnFilter(type: TxnType.expense));
    });
    await tester.pump();
    expect(s.filter.active, isTrue, reason: '前提：得先进筛选态');

    // 筛选态下卡片矮了一截（周期条换成「筛选结果」），中心点要现算
    final card = tester.getCenter(find.byType(SummaryCard));
    await tester.flingFrom(card, const Offset(-320, 0), 1200);
    await waitUntil(tester, () => s.tabIndex != 0);

    expect(s.cycleFrom, from, reason: '筛选和「哪一期」是两个维度，不许互相带偏');
    expect(
      s.tabIndex,
      1,
      reason: '识别器没注册 → 手势应该落回 PageView；'
          '如果这里是 0，说明注册了却没处理，等于在这一块挖掉了切 Tab',
    );
  });

  testWidgets('双击周期文案：回到今天所在的期；期外不再自称「本期支出」', (tester) async {
    await seed(tester);
    await pumpDetail(tester);
    final s = Store.i;
    final current = s.cycleFrom;

    // 先翻到上一期（直接调 Store，手势本身在上面几条里验过了）
    await tester.runAsync(() => s.shiftCycle(-1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(s.isCurrentPeriod, isFalse);
    expect(
      find.text('本期支出'),
      findsNothing,
      reason: '翻到上一期还说「本期」就是错的，横滑之后这个问题天天出现',
    );

    // 双击周期文案回本期。单击与双击并存 → 要等 300ms 判定窗口。
    // 点的是那行文案本身（`_PeriodHead` 是私有的，按文字找更稳）
    final label = periodLabel(s.cycleFrom, s.cycleTo);
    await tester.tap(find.text(label));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text(label));
    await waitUntil(tester, () => s.isCurrentPeriod);

    expect(s.cycleFrom, current, reason: '双击要回到今天所在的期');
    expect(find.text('本期支出'), findsOneWidget);
  });
}
