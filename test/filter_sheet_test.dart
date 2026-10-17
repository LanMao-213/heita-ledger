// 筛选面板的交互自检：选条件 → 实时计数 → 查看结果 → 明细页切到筛选态。
//
// 数据层的条件组合在 filter_test.dart 里测过了，这里只钉「面板 → Store」的
// 那条线：底部按钮从「选一个条件」变成「查看 N 条结果」、点下去之后明细页
// 的头卡换成「筛选结果」。这段最容易断的地方是状态没传出去或者列表没重建。
//
// ⚠️ 面板里的实时计数会走真实数据库，而 testWidgets 默认在假时钟里跑：
//    先 pump 走完 200ms 去抖，再用 runAsync 让查询真的回包，最后 pump 一次
//    应用 setState。少一步都会看到「计数一直是 0」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/detail_page.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/pickers.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_filter_sheet.db';

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

  testWidgets('选分类后计数与明细页同步', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    late int foodId;
    await tester.runAsync(() async {
      await Store.i.boot();
      final cats = await Repo.listCategories(
        Store.i.ledgerId,
        type: TxnType.expense,
      );
      foodId = cats.firstWhere((c) => c.name == '餐饮').id;
      final acc = Store.i.accounts.isEmpty ? null : Store.i.accounts.first.id;
      final now = Fmt.today();
      for (final cents in [1200, 3500, 9900]) {
        await Repo.insertTxn(Txn(
          id: 0,
          ledgerId: Store.i.ledgerId,
          type: TxnType.expense,
          amountCents: cents,
          date: now,
          categoryId: foodId,
          accountId: acc,
          note: '测试',
        ));
      }
      await Store.i.afterTxnChange();
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DetailPage())),
    );
    await tester.pumpAndSettle();

    // 打开筛选面板
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryGrid), findsOneWidget);
    // 还没选条件时按钮是禁用的
    expect(find.text('选一个条件'), findsOneWidget);

    // 选「餐饮」
    await tester.tap(find.descendant(
      of: find.byType(CategoryGrid),
      matching: find.text('餐饮'),
    ));
    await tester.pump(const Duration(milliseconds: 260)); // 走完去抖
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();

    final apply = find.textContaining('条结果');
    expect(apply, findsOneWidget);
    expect(tester.widget<Text>(apply).data, '查看 3 条结果');

    // 应用（面板关闭后会真查一次库，同样需要 runAsync 让查询回包）
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    expect(Store.i.filtering, isTrue);
    expect(Store.i.filter.categoryId, foodId);
    expect(Store.i.filteredTxns.length, 3);
    // 明细页的头卡切成了筛选口径
    expect(find.text('筛选结果'), findsOneWidget);
    expect(find.byType(CategoryGrid), findsNothing);

    // 重置回到按月浏览
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(Store.i.filtering, isFalse);

    // ---- 筛选态下记一笔：走的是 afterTxnChange 重跑筛选这条路 ----
    // 不符合当前条件的记录不该混进结果，但必须进当月明细 ——
    // 漏掉这一步的表现是「删了/记了，列表还是旧的」。
    await tester.runAsync(() async {
      await Store.i.applyFilter(TxnFilter(categoryId: foodId));
    });
    await tester.pumpAndSettle();
    expect(Store.i.filteredTxns.length, 3);

    await tester.runAsync(() async {
      final cats = await Repo.listCategories(
        Store.i.ledgerId,
        type: TxnType.expense,
      );
      final other = cats.firstWhere((c) => c.id != foodId).id;
      await Repo.insertTxn(Txn(
        id: 0,
        ledgerId: Store.i.ledgerId,
        type: TxnType.expense,
        amountCents: 700,
        date: Fmt.today(),
        categoryId: other,
        note: '打车',
      ));
      await Store.i.afterTxnChange();
    });
    await tester.pumpAndSettle();

    expect(Store.i.filteredTxns.length, 3);
    expect(Store.i.filteredTxns.any((t) => t.note == '打车'), isFalse);
    expect(Store.i.monthTxns.any((t) => t.note == '打车'), isTrue);
    expect(find.text('3 笔'), findsOneWidget);
  });
}
