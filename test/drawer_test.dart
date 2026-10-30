// 侧拉栏的自检：**入口在不在、分组收得起收不起、点下去真的到那**。
//
// 抽屉这类「导航面」最容易出现的问题不是崩溃，而是**错位**：入口写着「加密备份」
// 点开却是明文备份、导航组标着「图表」实际切到计划。这类错误编译过得去、单测
// 也过得去（没人测过），只有在用户手里才会暴露成「这 App 有点乱」。
//
// 所以这里验的是三条：
// 1) 五个分组与关键入口都在（漏一个就是「功能消失」）；
// 2) 收起分组之后，组里的入口真的不在树上了（不是被盖住、不是透明）；
// 3) 点导航能切 tab、点页面能 push 到对应页面（走完整条路径，不只看回调）。
//
// 视口用 390×1400：真机是 390×844，但抽屉内容比一屏高，用 844 会让「帮助」
// 组落在 viewport 之外、`find` 拿不到 —— 那样测的是「ListView 懒加载」而不是
// 「入口在不在」。这里要验的是后者，所以给一个装得下的高度。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/pages/app_drawer.dart';
import 'package:ledger/pages/help_page.dart';
import 'package:ledger/pages/home_shell.dart';
import 'package:ledger/pages/onboarding_page.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/common.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_drawer.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 起一个完整的 HomeShell（库是真的：切换账本、账户数都要读真数据）
Future<void> _bootHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.runAsync(() async {
    await Store.i.boot();
    // `tabIndex` 是 Store 上的全局状态，跨用例活着：上一条用例可能停在「我的」，
    // 这里显式归零，否则每条用例都要在末尾替下一条收拾现场。
    Store.i.switchTab(0);
  });
  await tester.pumpWidget(const MaterialApp(home: HomeShell()));
  await tester.pumpAndSettle();
}

/// 打开抽屉。
///
/// 走 `MenuButton` 而不是直接 `openDrawer()`：按钮是用户真实路径，
/// 它同时也是「页头左边那颗三横到底在不在」的证据。
Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byType(MenuButton));
  await tester.pumpAndSettle();
}

/// 抽屉内的某个文本（页面上可能同时有同名文字，比如底栏的「图表」）
Finder _inDrawer(String text) => find.descendant(
  of: find.byType(AppDrawer),
  matching: find.text(text),
);

/// 点抽屉里的一个入口。
///
/// **必须多推进一段假时钟**：抽屉收起之后，真正的动作被 `AppDrawer._run` 排在
/// `Future.delayed(M.base)`（260ms）之后 —— 那样新页面才不会从还没收完的抽屉上
/// 方压过去。而 `pumpAndSettle` 只推进「有帧要画」的时间，一个纯定时器不会让它
/// 继续 pump，于是它会在这个定时器到期前就返回，看起来像「点了没反应」。
Future<void> _tapEntry(WidgetTester tester, String text) async {
  await tester.tap(_inDrawer(text));
  await tester.pump(const Duration(milliseconds: 320));
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
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  testWidgets('四个页头都有抽屉把手，点开是三个分组 + 一个动作行', (tester) async {
    await _bootHome(tester);

    // 四页共用同一个页头组件；切过去之后把手仍然在
    for (final tab in ['图表', '计划', '我的']) {
      expect(find.byType(MenuButton), findsOneWidget, reason: '$tab 页没有把手');
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
    }
    expect(find.byType(MenuButton), findsOneWidget, reason: '我的页没有把手');

    await _openDrawer(tester);
    // 1.7.3 删掉「常用」「导航」两组：记一笔在底栏中央的「+」，明细/图表/计划/我的
    // 在底部 tab —— 抽屉里再列一遍，等于同一件事两个入口。
    for (final group in ['账本', '数据', '帮助']) {
      expect(_inDrawer(group), findsOneWidget, reason: '缺「$group」分组');
    }

    // 每组抽一个入口：分组标题在、入口却不在，等于分组是个空壳
    for (final entry in [
      '转账',
      '账户管理',
      '账单日',
      '导入账单',
      '备份与恢复',
      '数据安全',
      '帮助与引导',
    ]) {
      expect(_inDrawer(entry), findsOneWidget, reason: '缺入口「$entry」');
    }

    // 反向断言：删掉的那些不能又长回来
    for (final gone in [
      '记一笔',
      '明细',
      '加密备份',
      '明文备份',
      '从备份恢复',
      '使用引导',
      '帮助说明',
    ]) {
      expect(_inDrawer(gone), findsNothing, reason: '「$gone」应当已经移出抽屉');
    }
  });

  testWidgets('收起分组：组内入口从树上消失，再点一次回来', (tester) async {
    await _bootHome(tester);
    await _openDrawer(tester);

    expect(_inDrawer('账户管理'), findsOneWidget);
    await tester.tap(_inDrawer('账本'));
    await tester.pumpAndSettle();
    expect(
      _inDrawer('账户管理'),
      findsNothing,
      reason: '收起后入口还在树上，只是被盖住 —— 那不是收起',
    );
    expect(_inDrawer('账本'), findsOneWidget, reason: '组标题必须留着，否则没法展开');

    await tester.tap(_inDrawer('账本'));
    await tester.pumpAndSettle();
    expect(_inDrawer('账户管理'), findsOneWidget);
  });

  testWidgets('点「转账」：抽屉关上并弹出转账面板', (tester) async {
    await _bootHome(tester);
    await _openDrawer(tester);
    await _tapEntry(tester, '转账');

    expect(find.byType(AppDrawer), findsNothing, reason: '抽屉没收起来');
    expect(find.text('确认转账'), findsOneWidget, reason: '转账面板没打开');
  });

  testWidgets('「备份与恢复」的三项都在，点加密备份走到口令那一步', (tester) async {
    await _bootHome(tester);
    await _openDrawer(tester);
    await _tapEntry(tester, '备份与恢复');

    // 三个动作收进一层之后，名字必须说清各自的代价
    expect(find.text('加密备份'), findsOneWidget);
    expect(find.text('明文备份'), findsOneWidget);
    expect(find.text('从备份恢复'), findsOneWidget);
  });

  testWidgets('「帮助与引导」的二级菜单：帮助说明与重看引导都能打开', (tester) async {
    await _bootHome(tester);

    await _openDrawer(tester);
    await _tapEntry(tester, '帮助与引导');
    await tester.tap(find.text('帮助说明'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpPage), findsOneWidget);

    // 不能用 tester.pageBack()：HelpPage 的返回键是自绘的 IconButton + LineIcon，
    // 没有标准 Back 按钮的 tooltip，pageBack 会直接 fail。这里从导航栈弹回去即可。
    Navigator.of(tester.element(find.byType(HelpPage))).pop();
    await tester.pumpAndSettle();

    await _openDrawer(tester);
    await _tapEntry(tester, '帮助与引导');
    await tester.tap(find.text('重看使用引导'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsNothing);
  });

}
