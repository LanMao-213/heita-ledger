// 计划页各卡「必须同宽」自检。
//
// 起因：储蓄目标的空态卡比上面几张卡窄一截（缩到文字宽，约 240dp），
// 因为 `_Goals` 把卡片包在 Column 里，而 Column 默认居中 + 松宽度约束；
// 分类预算那张卡直接挂在 ListView 下拿到紧约束，所以是满宽。
//
// 这类问题的共同特征是「只在某一屏、某一状态下出现」，靠肉眼看单页很容易漏，
// 所以这里直接把「同宽」写成断言：任何一张卡只要宽度和邻居不同就红。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/pages/plan_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_plan_card_width.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

// ⚠️ 不能直接拿 `SectionCard` 元素的 renderObject：它是 `Container`，最外层
// 是 margin 变出来的 `Padding`，那一层永远铺满父级（360），量它等于什么都没量。
// 真正被填色 + 投影、用户看见的那张面是里面的 DecoratedBox。
//  `_RenderDecoratedBox` 在 Flutter 里已经是私有的，拿不到类型，
//  所以改在 element 树上找 `DecoratedBox` 这个 widget —— 卡自己的背景是
//  从外向内 DFS 遇到的第一个。
RenderBox _paintedBoxOf(Element card) {
  RenderBox? painted;
  void walk(Element e) {
    if (e.widget is DecoratedBox) {
      painted = (e as RenderObjectElement).renderObject as RenderBox;
      return;
    }
    e.visitChildren(walk);
  }

  walk(card);
  return painted!;
}

/// 取某个文本所在的那张卡的**可见宽度**
double _cardWidthOf(WidgetTester tester, String text) {
  final el = tester.element(find.text(text));
  Element? card;
  el.visitAncestorElements((e) {
    if (e.widget.runtimeType.toString() == 'SectionCard') {
      card = e;
      return false;
    }
    return true;
  });
  expect(card, isNotNull, reason: '「$text」外面没有 SectionCard');
  return _paintedBoxOf(card!).size.width;
}

/// 这一屏上**每一张卡**的可见宽度 —— 通用防线，不用猜哪张将来会出问题
List<double> _allCardWidths(WidgetTester tester) {
  final cards = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'SectionCard',
  );
  return tester
      .elementList(cards)
      .map((e) => _paintedBoxOf(e).size.width)
      .toList();
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

  testWidgets('空态：储蓄目标卡与分类预算卡同宽，且等于屏宽减去两边边距', (tester) async {
    await tester.runAsync(() => Store.i.boot());

    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: PlanPage()),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();

    final goal = _cardWidthOf(tester, '还没有储蓄目标');
    final cat = _cardWidthOf(tester, '还没有分类预算或支出');

    // 两张卡都是 SectionCard 默认 margin（左右各 S.lg）
    expect(goal, closeTo(360 - S.lg * 2, 0.5), reason: '储蓄目标空态卡没有铺满');
    expect(cat, closeTo(360 - S.lg * 2, 0.5));
    expect(goal, closeTo(cat, 0.5), reason: '储蓄目标卡比分类预算卡窄/宽了');
  });

  testWidgets('有目标时：目标卡与空态卡同宽（同一个 Column 里）', (tester) async {
    await tester.runAsync(() => Store.i.boot());
    await tester.runAsync(() => Repo.insertGoal(
          SavingGoal(id: 0, name: '旅行基金', targetCents: 2000000),
        ));
    await tester.runAsync(() => Store.i.afterGoalChange());

    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: PlanPage()),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();

    final goal = _cardWidthOf(tester, '旅行基金');
    expect(goal, closeTo(360 - S.lg * 2, 0.5), reason: '目标卡没有铺满');
  });

  // 跑空态：这是用户截图里的状态，也是唯一会走到 EmptyHint 那张卡的状态。
  // 有目标时的 _GoalCard 由上面那条用例守着。
  testWidgets('计划页上出现的每一张卡都必须同宽（空态）', (tester) async {
    await tester.runAsync(() => Store.i.boot());

    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: PlanPage()),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();

    final widths = _allCardWidths(tester);
    expect(widths, isNotEmpty, reason: '计划页一张卡都没渲染出来');
    for (final w in widths) {
      expect(w, closeTo(360 - S.lg * 2, 0.5), reason: '有卡宽度不对：$widths');
    }
  });
}
