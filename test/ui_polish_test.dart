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
import 'package:ledger/app.dart';
import 'package:ledger/data/cycle.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/pages/detail_page.dart';
import 'package:ledger/pages/mine_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'support/app_boot.dart';
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
      await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.expense,
          amountCents: 1200,
          date: now,
          categoryId: foodId,
          accountId: accId,
          note: '午饭',
        ),
      );
      await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.expense,
          amountCents: 800,
          date: now,
          categoryId: foodId,
          accountId: accId,
          note: '咖啡',
        ),
      );
      await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.income,
          amountCents: 500000,
          date: now,
          categoryId: salaryId,
          accountId: accId,
          note: '工资',
        ),
      );
      await s.loadCycle();
      await s.loadStats();
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

  // 原来这条点的是明细页顶部那排「全部/支出/收入/转账」chips ——
  // 1.4.5 把它们撤了（跨全部历史，和概览卡的本期口径冲突），类型筛选搬到筛选面板。
  // **语义没变**，所以断言保留，只把驱动方式换成同一层的 API：
  // 改类型时，其它条件（分类/金额/时间）必须原样保留。
  testWidgets('类型筛选：只改 type，不清掉其它条件', (tester) async {
    await seed(tester);
    await pumpDetail(tester);
    final s = Store.i;

    expect(s.filter.active, isFalse);

    await tester.runAsync(
      () => s.applyFilter(TxnFilter.none.withType(TxnType.expense)),
    );
    await settle(tester);
    expect(s.filter.active, isTrue);
    expect(s.filter.current.type, TxnType.expense);
    expect(s.filter.txns.length, 2);

    // 先设一个分类条件，再改类型 —— 分类条件必须还在
    await tester.runAsync(() => s.applyFilter(TxnFilter(categoryId: foodId)));
    await settle(tester);
    expect(s.filter.current.categoryId, foodId);

    await tester.runAsync(
      () => s.applyFilter(s.filter.current.withType(TxnType.income)),
    );
    await settle(tester);
    expect(s.filter.current.type, TxnType.income);
    expect(s.filter.current.categoryId, foodId, reason: '改类型不该清掉分类条件');

    // 回到「不限类型」：同样只去掉 type
    await tester.runAsync(() => s.applyFilter(s.filter.current.withType(null)));
    await settle(tester);
    expect(s.filter.current.type, isNull);
    expect(s.filter.current.categoryId, foodId);
    expect(s.filter.txns.length, 2);
  });

  testWidgets('明细顶部只有周期、没有左右翻期，点它弹日历', (tester) async {
    await seed(tester);
    await pumpDetail(tester);
    final s = Store.i;

    // 周期还在
    expect(find.text(periodLabel(s.cycleFrom, s.cycleTo)), findsOneWidget);
    // 但**永远不给左右箭头**：翻期靠横滑概览卡与日历两个入口，
    // 箭头一次只挪一期，还得盯着数字确认翻到哪（D-11 / D-24）。
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    // 点这行日期文字 → 日历卡片（上下滚动，不是左右翻月）
    await tester.tap(find.text(periodLabel(s.cycleFrom, s.cycleTo)));
    await tester.pump();
    // 1.4.5 起这行同时挂了双击（回本期），单击要先等一个 300ms 的双击判定窗口
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 400));

    // 不加标题、不加提示、不给「回到今天」按钮 —— 顶上只剩年份和周几
    expect(find.text('跳到哪一期'), findsNothing);
    expect(find.text('今天'), findsNothing);
    expect(find.textContaining('账单日'), findsNothing);
    expect(find.text(DateTime.now().year.toString()), findsWidgets);
    expect(find.byType(ListView), findsWidgets);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
  });

  testWidgets('日历吸顶的年份跟着滚动走，不写死今年', (tester) async {
    await seed(tester);
    await pumpDetail(tester);
    final s = Store.i;

    await tester.tap(find.text(periodLabel(s.cycleFrom, s.cycleTo)));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    final thisYear = DateTime.now().year;
    expect(find.text('$thisYear'), findsOneWidget);

    // 整条日历按周铺开（一行 52 高），12 个月约 52 行。
    // 手指下移 = 回到更早的月份；页面里还有明细的 ListView，
    // 从日历这一层（后插入的那个）起手
    await tester.drag(find.byType(ListView).last, const Offset(0, 52.0 * 52));
    await tester.pumpAndSettle();
    expect(find.text('$thisYear'), findsNothing);
    expect(find.text('${thisYear - 1}'), findsOneWidget);
  });

  testWidgets('日历滚到下个月，黑的那一档跟着换过去', (tester) async {
    await seed(tester);
    await pumpDetail(tester);
    final s = Store.i;

    await tester.tap(find.text(periodLabel(s.cycleFrom, s.cycleTo)));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    // 往下滚 5 行（一行 52）≈ 跨进下个月。按「画面里格数最多的月」判当月，
    // 不能按视口中心那一格：跨月行（29 30 | 1 2 3 4 5）的第 4 格其实是下月，
    // 中心点一落进去，整屏就跟着反了
    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await tester.pumpAndSettle();

    Color? colorOf(String date) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(ValueKey('cal-$date')),
                matching: find.byType(Text),
              )
              .first,
        )
        .style
        ?.color;

    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 15);
    // 下个月整月都在本期之外，用 ink2 —— 深灰，和「不在当月」的 ink4 拉开
    expect(colorOf(Fmt.date(nextMonth)), C.ink2, reason: '当月要压得住非当月');
    expect(
      colorOf(Fmt.date(DateTime(now.year, now.month + 1, 0))),
      C.ink4,
      reason: '已经划走的上个月要退到最淡',
    );
  });

  testWidgets('日历里点上个月的 1 号 → 明细跳到那一期', (tester) async {
    await seed(tester);
    await pumpDetail(tester);
    final s = Store.i;

    await tester.tap(find.text(periodLabel(s.cycleFrom, s.cycleTo)));
    await tester.pump();
    // 1.4.5 起这行同时挂了双击（回本期），单击要等 300ms 的双击判定窗口；
    // 再等面板动画走完 —— 日历是「先布局、再滚到今天」，动画中途量高度
    // 会滚到一个离谱的位置（实测滚到 5200，整个列表飞出屏幕）。
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 400));

    // 上月 1 号在初始视口上方（打开时只露出上月末两行多），
    // 先往回滚一点让它进入可点范围，再按日期 key 精确点名 ——
    // 同屏有上月末、本月、下月初三个「1」，靠文字找不准
    final prev = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
    final prevYm = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';

    await tester.drag(find.byType(ListView).last, const Offset(0, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('cal-$prevYm-01')));
    await settle(tester);

    expect(s.cycleFrom, '$prevYm-01');
    expect(s.cycleTo, Fmt.date(DateTime(prev.year, prev.month + 1, 0)));
    // loadCycle 里有 5 次串行查询，一次 settle 不一定跑完 —— 等它落地再断言
    for (var i = 0; i < 10 && s.isCurrentPeriod; i++) {
      await settle(tester);
    }
    expect(s.isCurrentPeriod, isFalse);
    // 上个月没有记录，明细清空但不该顺手筛出东西来
    expect(s.txns, isEmpty);
    expect(s.filter.active, isFalse);
  });

  testWidgets('底部 tab 能点，也能左右滑', (tester) async {
    await seed(tester);
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const HeitaApp());
    // 等 boot 走完才看得到底部 tab（启动页删除后已无最短停留）。
    await pumpUntilHome(tester);
    expect(Store.i.tabIndex, 0);

    // 点「图表」
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(Store.i.tabIndex, 1, reason: '点 tab 要切页');

    // 手指往右滑 = 回上一页（明细）
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(Store.i.tabIndex, 0, reason: '横滑也要能换页，并且和 tab 状态是同一个');
  });

  testWidgets('我的页只剩「数据 + 偏好 + 危险操作 + 关于」，设置入口不再重复', (tester) async {
    await seed(tester);
    tester.view.physicalSize = const Size(390 * 2, 1600 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MinePage())),
    );
    await tester.pump();

    // 1.7.3 起设置类入口统一收进侧拉栏，「我的」页不再重复列一遍。
    //
    // 之前这里断言「加密备份 / 明文备份 / 从备份恢复」三行都在本页 —— 那条
    // 断言的**意图**（换手机不能只能丢数据）仍然成立，但落点搬到了抽屉，
    // 由 drawer_test「「备份与恢复」的三项都在」继续守。本页现在要守的是
    // **不要长回去**：两个入口指向同一件事，用户会以为它们是两件事。
    for (final gone in [
      '加密备份',
      '明文备份',
      '从备份恢复',
      '导入账单',
      '账户管理',
      '分类管理',
      '账本管理',
      '数据安全',
      '周期账单',
      '账单日',
      '帮助说明',
    ]) {
      expect(
        find.text(gone),
        findsNothing,
        reason: '「$gone」应当只在侧拉栏出现，不该在「我的」页重复',
      );
    }

    // 留下的四块：上下文动作 + 个人偏好 + 单向门 + 关于
    for (final keep in ['导出当前筛选结果', '主题', '触感反馈', '清空全部数据']) {
      expect(find.text(keep), findsOneWidget, reason: '「我的」页丢了「$keep」');
    }
  });
}
