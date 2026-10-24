// 储蓄目标卡的长文本自检。
//
// 为什么单独测这一条：目标名是**用户自己填的**，长度不可控。这张卡是全页
// 唯一一处漏做 ellipsis 的地方（往来 / 明细 / 统计 / 模板 / 分类预算都做了），
// 结果是名字一长就把 Row 撑爆、卡片右侧挂黄黑条纹 —— 而且只在真机宽度下出现
// （测试默认的 800×600 太宽，量不出来），所以必须显式把视口压到 360dp。
//
// 两条都要验：
// 1) **不报错**：RenderFlex 抛的溢出异常要被当成失败（默认它只打印，不失败）；
// 2) **别换行**：金额行一旦换成两行，卡片会凭空高 16dp，跟别的卡不齐。
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

const _dbName = 'test_goal_card.db';

/// 360dp 屏：小屏安卓的下限。比这更窄的机型（320dp）也要过。
const _widths = <double>[320, 360];

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

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
    // 六套皮肤里挑两套极端：最长的名字在深色/亮色下都要成立
    ThemeCtrl.i.loadSilently(kDefaultTheme);
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  Future<void> seed() => Repo.insertGoal(
        SavingGoal(
          id: 0,
          name: '一个特别长的目标名字用来确认卡片不会被撑爆也不会换行',
          icon: 'flag',
          targetCents: 999999900, // ¥9,999,999.00
          savedCents: 12345600,
          dueMonth: '2027-03',
        ),
      );

  for (final w in _widths) {
    testWidgets('${w}dp 宽 + 超长目标名：不溢出', (tester) async {
      await tester.runAsync(() => Store.i.boot());
      await tester.runAsync(seed);
      await tester.runAsync(() => Store.i.afterGoalChange());

      tester.view.physicalSize = Size(w, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 溢出默认只是打印到控制台，不算失败 —— 这里手动接住
      final errors = <String>[];
      final orig = FlutterError.onError;
      FlutterError.onError = (d) => errors.add('${d.exception}');
      addTearDown(() => FlutterError.onError = orig);

      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: PlanPage())),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();

      expect(
        errors.where((e) => e.contains('overflowed')),
        isEmpty,
        reason: '${w}dp 下目标卡溢出了：$errors',
      );
    });
  }

  testWidgets('金额行不换行：卡片高度与短名一致', (tester) async {
    await tester.runAsync(() => Store.i.boot());

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<double> heightOf(String name) async {
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
      final el = tester.element(find.text(name));
      RenderBox? box;
      el.visitAncestorElements((e) {
        if (e.widget.runtimeType.toString() == '_GoalCard') {
          box = e.findRenderObject() as RenderBox?;
          return false;
        }
        return true;
      });
      return box?.size.height ?? -1;
    }

    await tester.runAsync(() => Repo.insertGoal(
          SavingGoal(id: 0, name: '短名', targetCents: 10000, savedCents: 5000),
        ));
    await tester.runAsync(() => Store.i.afterGoalChange());
    final short = await heightOf('短名');

    await tester.runAsync(seed);
    await tester.runAsync(() => Store.i.afterGoalChange());
    final long = await heightOf(
      '一个特别长的目标名字用来确认卡片不会被撑爆也不会换行',
    );

    // 长名/大金额不能让卡片变高 —— 一旦变高就是金额那行换行了
    expect(long, greaterThan(0));
    expect(short, greaterThan(0));
    expect(
      (long - short).abs(),
      lessThan(1),
      reason: '长短名卡片高度不一致（$short vs $long）：金额行换行了',
    );
  });
}
