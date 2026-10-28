// 分类预算的**空态入口**守卫。
//
// 起因（2026-10-28，QA 独立验收打回）：计划页「分类预算」有两条空态分支 ——
// `budgeted.isEmpty`（有支出、但一个额度都没设）与 `rows.isEmpty`（新库、
// 还没有任何流水）。前者的卡里有「为分类设置额度」按钮，后者**只有一句话**，
// 却写着「点下方「为分类设置额度」开始」。
//
// 也就是说：**全新安装**的用户看到的是一句指着不存在按钮的提示，而他又没有别的
// 入口去建第一条分类预算 —— 必须先随手记一笔，按钮才会长出来。
//
// 修法是把两条分支收成同一张 `_emptyBudgetCard`。这个文件守两件事：
//   1. 空态卡里**必须真有**那颗按钮（文案不许高于现实）；
//   2. 点得动，能走到「选择分类」那一步（按钮不是个摆设）。
//
// 为什么单独一个文件：它守的是「入口存在性」，而 `plan_card_width_test` 守的是
// 「卡片同宽」，两件事将来会朝不同方向演进，混在一起改哪件都要动同一个文件。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
import 'package:ledger/pages/plan_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_plan_budget_entry.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 把计划页立起来 —— 空库、不放任何流水，等价于「全新安装」。
Future<void> _pumpPlanPage(WidgetTester tester) async {
  await tester.runAsync(() => Store.i.boot());

  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: const Scaffold(body: PlanPage())),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
    ThemeCtrl.i.loadSilently(kDefaultTheme);
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  testWidgets('全新安装（无流水）：空态卡里必须有可点的「为分类设置额度」', (tester) async {
    await _pumpPlanPage(tester);

    // 前提：确实落在空态上，否则下面两条断言测的是另一个分支
    expect(
      find.text('还没有设置分类预算'),
      findsWidgets,
      reason: '没有进入分类预算空态，这条用例证明不了什么',
    );

    // ① 按钮必须存在 —— 这是被 QA 打回的那条：文案说有，界面却没有
    expect(
      find.widgetWithText(TextButton, '为分类设置额度'),
      findsOneWidget,
      reason: '空态里没有「为分类设置额度」按钮：'
          '全新安装的用户没有任何入口建第一条分类预算（文案还指着它）',
    );

    // ② 文案不许再指着「下方」这种位置指代 —— 两个空态的布局已经一样，
    //    改用「设一个额度会得到什么」的说法。留着"下方"这种词，下次改布局又会撒一次谎。
    expect(
      find.textContaining('点下方'),
      findsNothing,
      reason: '空态文案在指一个位置，而按钮就在卡里；这类指代最容易随布局过期',
    );

    // ③ 点得动，且真的走到「选择分类」
    await tester.tap(find.widgetWithText(TextButton, '为分类设置额度'));
    await tester.pumpAndSettle();
    expect(
      find.text('选择分类'),
      findsOneWidget,
      reason: '点了「为分类设置额度」没有弹出分类选择 —— 按钮是摆设',
    );
    expect(tester.takeException(), isNull);
  });
}
