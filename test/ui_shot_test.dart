// 界面截图自检。
//
// 为什么值得写：我无法上真机看效果，但可以在测试里把界面**真的渲染出来**
// 存成 PNG，然后逐张核对。更关键的是，Flutter 的布局溢出（RenderFlex
// overflow）在测试里会抛异常 —— 用 takeException() 断言就能自动兜住
// 「文字太长把卡片撑破」这类问题，比肉眼快得多。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart';
import 'package:ledger/data/cycle.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _shotKey = GlobalKey();

/// 测试环境默认字体没有中文字形，会全部渲染成方块。
/// 这里把系统「等线」加载成默认字体族，截图才看得出真实效果。
Future<void> _loadChineseFont() async {
  const candidates = [
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ];
  // Cupertino 的滚轮（CupertinoPicker）用的是它自己的默认字族，不是 Roboto。
  // 只注册 Roboto 的话，双轮盘截图里的中文会变成方块。
  const families = [
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    '.SF Pro Text',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    for (final family in families) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
        );
      await loader.load();
    }
    // ignore: avoid_print
    print('已加载中文字体：$path（$families）');
    return;
  }
  // ignore: avoid_print
  print('⚠️ 未找到中文字体，截图中的文字会显示为方块');
}

/// 图标字体在测试环境里不会自动加载，不补的话所有 Icon 都是方块。
Future<void> _loadIconFont() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(
      ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer),
    ));
  await loader.load();
}

Future<void> _shot(WidgetTester tester, String path) async {
  await tester.binding.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('截图 $path (${image.width}x${image.height})');
  });
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadChineseFont();
    await _loadIconFont();

    // 截图测试单独用一个库，跟其它测试文件并行跑时互不干扰
    Db.fileName = 'test_shot.db';

    // 从空库开始 —— 否则上一轮留下的演示数据会一层层累积，截图不可复现
    final dir = await databaseFactory.getDatabasesPath();
    final file = File(p.join(dir, Db.fileName));
    if (file.existsSync()) file.deleteSync();
  });

  testWidgets('主界面截图与布局自检', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // ⚠️ 开库与造数据必须放在 runAsync 里。
    // testWidgets 默认在「假时钟」里跑，sqflite 的查询结果在真实事件循环上回包，
    // 假时钟里 await 这些 Future 会永远等不到 —— 直接挂在第一行，连超时都触发不了。
    await tester.runAsync(() async {
      await Store.i.boot();
      await _seedDemoData();
    });

    await tester.pumpWidget(
      RepaintBoundary(key: _shotKey, child: const HeitaApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ---- 明细页 ----
    await _shot(tester, 'build/visual/shot_1_detail.png');
    expect(tester.takeException(), isNull, reason: '明细页有布局溢出');

    // ---- 日历卡片（上下滚动，没有左右翻月）----
    await tester.tap(find.text(cycleLabel(Store.i.cycleFrom, Store.i.cycleTo)));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    // 每日金额是一次异步查询回填的：假时钟里查库永远等不到，必须让出真实事件循环
    await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await _shot(tester, 'build/visual/shot_14_calendar.png');
    expect(tester.takeException(), isNull, reason: '日历卡片有布局溢出');
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();

    // ---- 图表页 ----
    await tester.tap(find.text('图表'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_2_stats.png');
    expect(tester.takeException(), isNull, reason: '图表页有布局溢出');

    // ---- 计划页 ----
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_3_plan.png');
    expect(tester.takeException(), isNull, reason: '计划页有布局溢出');

    // ---- 我的 ----
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_4_mine.png');
    expect(tester.takeException(), isNull, reason: '我的页有布局溢出');

    // ---- 模板管理 ----
    await tester.tap(find.text('记账模板'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_6_templates.png');
    expect(tester.takeException(), isNull, reason: '模板页有布局溢出');

    // ---- 模板编辑页 ----
    await tester.tap(find.text('早餐'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_7_template_editor.png');
    expect(tester.takeException(), isNull, reason: '模板编辑页有布局溢出');
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    // 回到「我的」
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    // ---- 记一笔面板 ----
    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    // 「＋」是圆形按钮，不是 Icon，用坐标点最稳（底栏 60 高，圆心在 802 附近）
    await tester.tapAt(const Offset(195, 802));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await _shot(tester, 'build/visual/shot_5_record.png');
    expect(tester.takeException(), isNull, reason: '记一笔面板有布局溢出');

    // ---- 记一笔：填了金额的样子（确认键变成可用的重色块）----
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_15_record_filled.png');
    expect(tester.takeException(), isNull, reason: '记一笔（有金额）有布局溢出');

    // ---- 分类 + 名目双轮盘 ----
    await tester.tap(find.text('选名目，或自己写备注'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_11_note_wheel.png');
    expect(tester.takeException(), isNull, reason: '双轮盘有布局溢出');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // ---- 日期选择 ----
    await tester.tap(find.byKey(const ValueKey('record_date_chip')));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await _shot(tester, 'build/visual/shot_12_date_picker.png');
    expect(tester.takeException(), isNull, reason: '日期选择有布局溢出');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // ---- 账户选择 ----
    await tester.tap(find.byKey(const ValueKey('record_account_chip')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_13_account_sheet.png');
    expect(tester.takeException(), isNull, reason: '账户选择有布局溢出');
    await tester.tapAt(const Offset(195, 80));
    await tester.pumpAndSettle();

    // ---- 筛选面板 ----
    // 先点遮罩把记一笔关掉（面板占了下半屏，顶部遮罩还能点到）
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await _shot(tester, 'build/visual/shot_8_filter_sheet.png');
    expect(tester.takeException(), isNull, reason: '筛选面板有布局溢出');

    // ---- 筛选生效后的明细页 ----
    // 面板里的实时计数会走真实数据库（假时钟里 await 不到），这里直接从
    // Store 应用条件，专门验证明细页筛选态的版式：条件条 + 结果摘要 + 列表
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final cats = await Repo.listCategories(
        Store.i.ledgerId,
        type: TxnType.expense,
      );
      final food = cats.firstWhere((c) => c.name == '餐饮').id;
      await Store.i.applyFilter(TxnFilter(
        categoryId: food,
        minCents: 2000,
        maxCents: 20000,
      ));
    });
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_9_filter_result.png');
    expect(tester.takeException(), isNull, reason: '筛选结果页有布局溢出');

    // ---- 筛选空结果态 ----
    await tester.runAsync(() async {
      await Store.i.applyFilter(const TxnFilter(minCents: 999999900));
    });
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_10_filter_empty.png');
    expect(tester.takeException(), isNull, reason: '筛选空结果页有布局溢出');
  });
}

/// 造一批贴近真实的演示数据：整月零散支出 + 两笔收入 + 一个超支分类
Future<void> _seedDemoData() async {
  final store = Store.i;
  final ledgerId = store.ledgerId;
  final month = Fmt.month(DateTime.now());

  Future<int?> cat(String name, TxnType type) async {
    final list = await Repo.listCategories(ledgerId, type: type);
    for (final c in list) {
      if (c.name == name) return c.id;
    }
    return null;
  }

  final food = await cat('餐饮', TxnType.expense);
  final transport = await cat('交通', TxnType.expense);
  final shopping = await cat('购物', TxnType.expense);
  final home = await cat('居住', TxnType.expense);
  final fun = await cat('娱乐', TxnType.expense);
  final salary = await cat('工资', TxnType.income);

  final accounts = store.accounts;
  final cash = accounts.isEmpty ? null : accounts.first.id;
  final alipay =
      accounts.length > 1 ? accounts[1].id : (accounts.isEmpty ? null : accounts.first.id);

  final rows = <(int, String, TxnType, int, int?, int?, String)>[
    (12, '$month-01', TxnType.expense, 2800, food, cash, '早餐'),
    (11, '$month-01', TxnType.expense, 600, transport, cash, '地铁'),
    (10, '$month-02', TxnType.expense, 12800, food, alipay, '和同事聚餐'),
    (9, '$month-03', TxnType.expense, 39900, shopping, alipay, '换了个键盘'),
    (8, '$month-05', TxnType.expense, 150000, home, alipay, '房租'),
    (7, '$month-06', TxnType.expense, 4500, transport, cash, '打车'),
    (6, '$month-08', TxnType.expense, 6800, fun, alipay, '电影票'),
    (5, '$month-09', TxnType.expense, 2350, food, cash, '午饭'),
    (4, '$month-10', TxnType.expense, 19900, shopping, alipay, '外套'),
    (3, '$month-11', TxnType.expense, 3200, food, cash, '奶茶'),
  ];

  for (final r in rows) {
    await Repo.insertTxn(Txn(
      id: 0,
      ledgerId: ledgerId,
      type: r.$3,
      amountCents: r.$4,
      date: r.$2,
      categoryId: r.$5,
      accountId: r.$6,
      note: r.$7,
    ));
  }

  await Repo.insertTxn(Txn(
    id: 0,
    ledgerId: ledgerId,
    type: TxnType.income,
    amountCents: 1280000,
    date: '$month-10',
    categoryId: salary,
    accountId: alipay,
    note: '10月工资',
  ));

  // 预算：总预算 + 一个必然超支的分类（用于验证红色警示）
  await Repo.setBudget(ledgerId: ledgerId, periodStart: '$month-01', amountCents: 600000);
  if (food != null) {
    await Repo.setBudget(
      ledgerId: ledgerId,
      periodStart: '$month-01',
      categoryId: food,
      amountCents: 120000,
    );
  }
  if (transport != null) {
    await Repo.setBudget(
      ledgerId: ledgerId,
      periodStart: '$month-01',
      categoryId: transport,
      amountCents: 30000,
    );
  }

  // 储蓄目标
  await Repo.insertGoal(const SavingGoal(
    id: 0,
    name: '旅行基金',
    icon: 'plane',
    targetCents: 2000000,
    savedCents: 850000,
    dueMonth: '2027-06',
  ));
  await Repo.insertGoal(const SavingGoal(
    id: 0,
    name: '换电脑',
    icon: 'laptop',
    targetCents: 800000,
    savedCents: 230000,
  ));
  await Repo.insertGoal(const SavingGoal(
    id: 0,
    name: '应急金',
    icon: 'wallet',
    targetCents: 3000000,
    savedCents: 1260000,
  ));

  // 记账模板：四张，「早餐」「地铁」用过几次 —— 顶部那排模板的排序靠它
  final tplBreakfast = await Repo.insertTemplate(TxnTemplate(
    id: 0,
    ledgerId: ledgerId,
    name: '早餐',
    icon: 'food',
    type: TxnType.expense,
    amountCents: 1200,
    categoryId: food,
    accountId: cash,
    note: '包子 + 豆浆',
  ));
  final tplMetro = await Repo.insertTemplate(TxnTemplate(
    id: 0,
    ledgerId: ledgerId,
    name: '地铁',
    icon: 'transport',
    type: TxnType.expense,
    amountCents: 600,
    categoryId: transport,
    accountId: cash,
  ));
  await Repo.insertTemplate(TxnTemplate(
    id: 0,
    ledgerId: ledgerId,
    name: '房租',
    icon: 'home',
    type: TxnType.expense,
    amountCents: 150000,
    categoryId: home,
    accountId: alipay,
    note: '每月 5 号',
  ));
  await Repo.insertTemplate(TxnTemplate(
    id: 0,
    ledgerId: ledgerId,
    name: '奶茶',
    icon: 'food',
    type: TxnType.expense,
    amountCents: 0,
    categoryId: food,
    accountId: alipay,
  ));
  for (var i = 0; i < 3; i++) {
    await Repo.touchTemplate(tplBreakfast);
  }
  await Repo.touchTemplate(tplMetro);

  await store.loadAll();
}
