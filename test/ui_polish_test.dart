// 本轮 UI 改动的交互自检：类型快捷筛选（D-03）与日历面板（D-06）。
//
// 这两处最容易断在「状态传递」上：
// 1) chips 只该改 type，用户已经设好的分类/金额/时间条件不能被顺手清掉；
// 2) 日历点某天要复用筛选那套（TxnFilter），否则条件条、重置、与其它条件
//    共存的行为会跟手动筛选不一致。
//
// ⚠️ 两个坑都踩过：
//   a) 建库/造数据/查库必须在 `tester.runAsync` 里 —— testWidgets 默认跑在假时钟，
//      直接 await 真实 I/O 会永久卡住（连超时都不触发）；
//   b) 不要用 pumpAndSettle 等加载圈：CircularProgressIndicator / 进度条一直在动，
//      永远等不到「静止」，整个测试会挂死。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/detail_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_ui_polish.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  late int ledgerId;
  late int foodId;
  late int salaryId;
  late int accId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  /// 建库 + 造三笔（2 支出 / 1 收入，都在今天）。必须在 runAsync 里跑。
  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Db.close();
      final f = File(await _dbPath());
      if (f.existsSync()) f.deleteSync();

      await Store.i.boot();
      final s = Store.i;
      ledgerId = s.ledgerId;
      foodId = s.expenseCats.first.id;
      salaryId = s.incomeCats.first.id;
      accId = s.accounts.first.id;

      final now = Fmt.today();
      await Repo.insertTxn(Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 1200,
        date: now,
        categoryId: foodId,
        accountId: accId,
        note: '午饭',
      ));
      await Repo.insertTxn(Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 800,
        date: now,
        categoryId: foodId,
        accountId: accId,
        note: '咖啡',
      ));
      await Repo.insertTxn(Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.income,
        amountCents: 500000,
        date: now,
        categoryId: salaryId,
        accountId: accId,
        note: '工资',
      ));
      await s.loadMonth();
      // Store 是单例：上一个测试留下的筛选状态会带过来，
      // 不清掉的话首页会停在「筛选结果」态，日历按钮就不在树里了
      await s.clearFilter();
    });
  }

  /// 让真实查询回包，再推两帧应用 setState（不用 pumpAndSettle，见文件头说明）
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
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

  testWidgets('类型 chips：只改 type，不清掉其它条件', (tester) async {
    await seed(tester);
    await pumpDetail(tester);
    final s = Store.i;

    // 初始：未筛选
    expect(s.filtering, isFalse);

    // 点「支出」→ 只剩 2 笔支出
    await tester.tap(find.widgetWithText(GestureDetector, '支出'));
    await settle(tester);
    expect(s.filtering, isTrue);
    expect(s.filter.type, TxnType.expense);
    expect(s.filteredTxns.length, 2);

    // 先设一个分类条件，再点「收入」—— 分类条件必须还在，只是 type 变了
    await tester.runAsync(() => s.applyFilter(TxnFilter(categoryId: foodId)));
    await settle(tester);
    expect(s.filter.categoryId, foodId);

    await tester.tap(find.widgetWithText(GestureDetector, '收入'));
    await settle(tester);
    expect(s.filter.type, TxnType.income);
    expect(s.filter.categoryId, foodId, reason: 'chips 不该清掉分类条件');

    // 点「全部」→ 只去掉 type，分类条件仍保留
    await tester.tap(find.widgetWithText(GestureDetector, '全部'));
    await settle(tester);
    expect(s.filter.type, isNull);
    expect(s.filter.categoryId, foodId);
    expect(s.filteredTxns.length, 2);
  });

  testWidgets('日历面板：显示当月金额，点某天跳到那天的筛选', (tester) async {
    await seed(tester);
    await pumpDetail(tester);
    final s = Store.i;
    final today = Fmt.today();

    // 打开日历（hero 右上角的按钮）。先推完弹出动画，再等查询回包
    await tester.tap(find.byIcon(Icons.calendar_month_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(find.text('点某一天，直接看那天的明细'), findsOneWidget);

    // 点「今天」那一格（限定在网格里找，避免命中列表里的日期文字）
    final day = int.parse(today.substring(8)).toString();
    await tester.tap(find.descendant(
      of: find.byType(GridView),
      matching: find.text(day),
    ));
    await settle(tester);

    expect(s.filtering, isTrue);
    expect(s.filter.dateFrom, today);
    expect(s.filter.dateTo, today);
    expect(s.filteredTxns.length, 3); // 三笔都在今天
  });
}
