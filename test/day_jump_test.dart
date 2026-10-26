// F2：统计页点趋势图某天 → 跳到明细页并只筛那天。
//
// 这条链路跨了三个地方（图表的命中 → Store 的筛选与 Tab → 明细页的条件条），
// 任何一环断了都表现为「点了没反应」，所以用一个端到端测试钉住。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/home_shell.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/charts.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_day_jump.db';

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

  testWidgets('图表点某天 → 明细页筛上那天', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final month = Fmt.month(DateTime.now());
    const targetDay = 3;

    await tester.runAsync(() async {
      await Store.i.boot();
      final cat = Store.i.expenseCats.first.id;
      final acc = Store.i.accounts.first.id;
      // 3 号两笔、10 号一笔 —— 3 号那根柱子有数据，才允许点
      for (final d in [targetDay, targetDay, 10]) {
        await Repo.insertTxn(
          Txn(
            id: 0,
            ledgerId: Store.i.ledgerId,
            type: TxnType.expense,
            amountCents: 1000,
            date: '$month-${d.toString().padLeft(2, '0')}',
            categoryId: cat,
            accountId: acc,
            note: '测试',
          ),
        );
      }
      await Store.i.afterTxnChange();
    });

    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();

    // 切到「图表」
    await tester.tap(find.text('图表'));
    await tester.pumpAndSettle();

    final bars = find.byType(DailyBars);
    expect(bars, findsOneWidget);
    await tester.ensureVisible(bars);
    await tester.pumpAndSettle();

    // 点第 3 天的柱子
    final rect = tester.getRect(bars);
    final slot = rect.width / 31;
    await tester.tapAt(
      Offset(rect.left + slot * (targetDay - 0.5), rect.center.dy),
    );
    await tester.pumpAndSettle();
    // 筛选要真查一次库：假时钟里 await 不到，先让真实事件循环跑一下
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    // 落到明细页，且条件条只筛那一天
    expect(Store.i.tabIndex, 0);
    expect(Store.i.filter.active, isTrue);
    expect(Store.i.filter.current.dateFrom, '$month-03');
    expect(Store.i.filter.current.dateTo, '$month-03');
    expect(find.text('筛选结果'), findsOneWidget);
  });
}
