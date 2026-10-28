// 统计页「近 6 期」趋势卡：切换方式（2026-10-28 用户要求）。
//
// 原样：卡片右上角并排两枚胶囊「柱状 / 折线」，点胶囊切换。
// 要求：去掉那两枚选择，改成**点卡片**切换。
//
// 这里钉三件事：
// 1. 右上角那两枚胶囊真的没了（不是挪了个位置）；
// 2. 点卡片能切到折线，再点能切回来 —— 开关是**整卡**，不靠某个小按钮；
// 3. 「能切换」这件事仍然自解释：图下方有一句「点卡片切到 X」。
//
// 第 3 条不是凑数：两枚文字胶囊自带「这是什么」的说明，删掉它们之后
// 如果只剩一个可点区域，用户永远不知道折线还存在着。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/charts.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_boot.dart';

const _dbName = 'test_stats_trend_toggle.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 趋势卡要有东西可画：一笔支出 + 一笔收入，够它画出一根柱。
Future<void> _seed() async {
  final s = Store.i;
  final today = Fmt.today();
  final acc = s.accounts.first;
  await s.addTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.expense,
      amountCents: 3860,
      date: today,
      categoryId: s.expenseCats.first.id,
      accountId: acc.id,
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
    ),
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

  testWidgets('趋势卡：没有柱状/折线胶囊，点卡片切换', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await Store.i.boot();
      await _seed();
    });

    await tester.pumpWidget(const HeitaApp());
    await pumpUntilHome(tester);
    await tester.tap(find.text('图表'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    // 趋势卡在页面下方，先滚到它露出来。
    // 1.6.0 起卡片下面那句「点卡片切到柱状/折线」的常驻提示被去掉了，
    // 所以滚动与点击都以整卡为锚点（ValueKey），不再靠那句提示定位。
    const trendCard = ValueKey('stats_trend_card');
    await tester.scrollUntilVisible(
      find.byKey(trendCard),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // 1) 右上角那两枚胶囊没了
    expect(find.text('柱状'), findsNothing, reason: '右上角不该再有「柱状」选择');
    expect(find.text('折线'), findsNothing, reason: '右上角不该再有「折线」选择');

    // 2) 默认柱状；且**不再有任何操作提示文字**（1.6.0 用户要求取消）
    expect(find.byType(MonthTrendLine), findsNothing);
    expect(find.textContaining('点卡片切到'), findsNothing,
        reason: '常驻的切换提示已被移除');

    // 3) 点卡片 → 折线
    await tester.tap(find.byKey(trendCard));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(
      find.byType(MonthTrendLine),
      findsOneWidget,
      reason: '点卡片没切到折线 —— 开关没挂在整卡上',
    );
    expect(find.textContaining('点卡片切到'), findsNothing,
        reason: '切换后也不该冒出提示');
    expect(find.text('柱状'), findsNothing, reason: '切换后也不能冒出胶囊');
    expect(tester.takeException(), isNull);

    // 4) 再点回来（反向同样要能切，不然就是单向开关）
    await tester.tap(find.byKey(trendCard));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.byType(MonthTrendLine), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
