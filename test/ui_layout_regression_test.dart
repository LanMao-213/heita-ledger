// 界面布局回归网（P2-2 的**替代方案**，原因见下）。
//
// ## 为什么不是像素 golden
//
// 计划里写的是「6 个页面 × 明暗两套 = 12 张 `matchesGoldenFile`」。落地时发现
// 一个硬冲突：本仓库的截图测试靠**加载 Windows 系统字体**（`C:\Windows\Fonts\
// Deng.ttf`）才能渲染中文，CI 跑在 ubuntu 上，那些路径不存在。
//
// - 在 Windows 上生成的 golden，在 ubuntu 上必然对不上（字形回退成方块）；
// - 要让两边一致，得把字体文件（约 10 MB）提交进仓库并在 CI 里注册 ——
//   这违反「零新依赖 / 仓库不塞二进制资源」的既有取舍。
//
// 所以这里换一种**与平台无关**的护栏：断言布局不变量。它能抓住「拆 build
// 方法、调整卡片层级」时真正的回归（溢出、零尺寸、区块消失），而这些断言
// 在任何平台上结果都一样。
//
// ## 为什么带两个字号
//
// 中文 + 大字号是最容易撑破卡片的组合，而 `textScaler` 是系统级设置，真实用户
// 里并不罕见。1.0 与 1.3 各跑一遍，等于用最小的成本覆盖「字变大了还画不画得下」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_layout_regression.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 造一份「每种界面都有东西可画」的最小数据。
///
/// 走的是 `Store` 的用例方法（`addTxn` / `setBudget` / `saveGoal`），
/// 顺带证明这些方法在真实界面里能跑通 —— 只用 Repo 造数据的话，
/// 「用例方法少调了一次刷新」在这里就看不见。
Future<void> _seed() async {
  final s = Store.i;
  final today = Fmt.today();
  final food = s.expenseCats.first;
  final acc = s.accounts.first;

  await s.addTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.expense,
      amountCents: 3860,
      date: today,
      categoryId: food.id,
      accountId: acc.id,
      note: '午饭',
    ),
  );
  await s.addTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.expense,
      amountCents: 12800,
      date: today,
      categoryId: food.id,
      accountId: acc.id,
      note: '一周的菜钱，顺便买了点水果和牛奶',
    ),
  );
  await s.addTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.income,
      amountCents: 800000,
      date: today,
      categoryId: s.incomeCats.first.id,
      accountId: acc.id,
      note: '工资',
    ),
  );
  await s.setBudget(periodStart: s.cycleFrom, amountCents: 300000);
  await s.setBudget(
    periodStart: s.cycleFrom,
    categoryId: food.id,
    amountCents: 80000,
  );
  await s.saveGoal(
    const SavingGoal(id: 0, name: '换台相机', icon: 'gift', targetCents: 600000),
  );
}

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  // 开库与造数据必须在 runAsync 里：testWidgets 的假时钟等不到 sqflite 的回包
  await tester.runAsync(() async {
    await Store.i.boot();
    await _seed();
  });

  await tester.pumpWidget(const HeitaApp());
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

/// 切到某个 Tab 并断言「没有布局溢出」。
Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  expect(
    tester.takeException(),
    isNull,
    reason: '「$label」页在字号 ${tester.platformDispatcher.textScaleFactor} 下有布局溢出',
  );
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

  // 默认字号：一次跑完四个 Tab，省一次开库 + 造数据
  testWidgets('四个 Tab 在默认字号下都没有溢出', (tester) async {
    await _pumpApp(tester);

    for (final label in ['明细', '图表', '计划', '我的']) {
      await _tab(tester, label);
    }
  });

  // 大字号：最容易撑破卡片的情形
  testWidgets('四个 Tab 在 1.3 倍字号下都没有溢出', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpApp(tester);

    for (final label in ['明细', '图表', '计划', '我的']) {
      await _tab(tester, label);
    }
  });

  testWidgets('记一笔面板在默认字号与 1.3 倍字号下都不溢出', (tester) async {
    await _pumpApp(tester);

    // 底栏「＋」是自绘圆形按钮，不是 Icon，用坐标最稳（同 ui_shot_test）
    await tester.tapAt(const Offset(195, 802));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: '记一笔面板（默认字号）溢出');

    // 关掉面板再换字号重开：字号是平台级状态，改完要重建整棵树
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.tapAt(const Offset(195, 802));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: '记一笔面板（1.3 倍字号）溢出');
  });

  testWidgets('统计页的两个口径都能给出数字（视图接错会在这里露头）', (tester) async {
    await _pumpApp(tester);
    final s = Store.i;

    // 造了 3 笔（2 支 1 收）+ 一个总预算，统计视图必须读得到
    expect(s.stats.expenseCents, 3860 + 12800);
    expect(s.stats.incomeCents, 800000);
    expect(s.stats.byPeriod, isTrue);
    expect(s.stats.trend, isNotEmpty);

    await _tab(tester, '图表');
    // 环图中心写的是支出合计；这里只要求「有内容」，不锁具体格式
    expect(find.byType(CustomPaint), findsWidgets);

    // 切到「本月」口径后区间应变成自然月
    await tester.runAsync(() => s.setStatBasis(StatBasis.month));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(s.stats.byPeriod, isFalse);
    expect(s.stats.from, endsWith('-01'));
  });
}
