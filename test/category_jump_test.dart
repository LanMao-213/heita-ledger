// 分类排行下钻：点某项 → 明细页只留这个分类。
//
// 和 day_jump_test 同一条链路（命中 → Store 筛选与 Tab → 明细页条件条），
// 但多一个坑要钉住：排行榜按**根分类**聚合，筛选必须连带子分类一起命中，
// 否则点「餐饮」会看到 0 条（子分类的交易 parent 不是餐饮自己）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/home_shell.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_category_jump.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  tearDownAll(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  testWidgets('图表点排行里的分类 → 明细页筛上该分类（含子分类）', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final month = Fmt.month(DateTime.now());
    late int foodId;
    late int transportId;

    await tester.runAsync(() async {
      await Store.i.boot();
      // 餐饮下面挂两个子分类：交易记在子分类上，排行按根分类聚合
      final food = Store.i.expenseCats.firstWhere((c) => c.name == '餐饮');
      foodId = food.id;
      transportId = Store.i.expenseCats.firstWhere((c) => c.name == '出行').id;
      final subs = Store.i.childrenOf(foodId);
      final acc = Store.i.accounts.first.id;

      Future<void> add(int catId, int cents) => Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: Store.i.ledgerId,
          type: TxnType.expense,
          amountCents: cents,
          date: '$month-05',
          categoryId: catId,
          accountId: acc,
          note: '测试',
        ),
      );

      await add(subs.first.id, 3000);
      await add(subs.last.id, 2000);
      await add(transportId, 1000);
      await Store.i.afterTxnChange();
    });

    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('图表'));
    await tester.pumpAndSettle();

    // 点到「餐饮」那一行（图例里也有同名的「餐饮」，所以按 key 定位）
    final row = find.byKey(ValueKey('freq-$foodId'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    // 筛选要真查一次库：假时钟里 await 不到
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    expect(Store.i.tabIndex, 0, reason: '落到明细页');
    expect(Store.i.filter.active, isTrue);
    expect(Store.i.filter.current.categoryId, foodId, reason: '筛的是根分类');
    expect(Store.i.filter.current.type, TxnType.expense);
    expect(
      Store.i.filter.txns.length,
      2,
      reason: '两笔记在子分类上的交易都要命中（连带子分类）',
    );
    expect(
      Store.i.filter.count,
      2,
      reason: '合计也只算这两笔，不能把出行的 1000 算进来',
    );
    expect(find.text('筛选结果'), findsOneWidget);

    // 区间跟统计页走，否则图表数字和明细对不上
    expect(Store.i.filter.current.dateFrom, Store.i.stats.from);
    expect(Store.i.filter.current.dateTo, Store.i.stats.to);
  });
}
