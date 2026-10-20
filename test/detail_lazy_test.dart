// 明细列表懒加载的自检（1.4.5）。
//
// 为什么值得单独测：懒加载是**看不见**的 —— 界面长得一模一样，只有「实际建了
// 多少个 widget」能证明它生效。而这正是 1.4.4 把上限卡在 500 的原因：
// 当时 `ListView(children: [...])` 会把一期所有行一次建出来。
//
// 断言用「树上真实存在的 TxnRow 数量」：非懒加载时它等于总条数，
// 懒加载后只等于可视区域内的那些。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/detail_page.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/detail/txn_row.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_detail_lazy.db';

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
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  testWidgets('明细几百笔也只建可视区域那几张卡', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    const days = 20;
    const perDay = 10;
    const total = days * perDay; // 200 笔

    await tester.runAsync(() async {
      await Store.i.boot();
      final s = Store.i;
      final cat = (await Repo.listCategories(
        s.ledgerId,
        type: TxnType.expense,
      )).firstWhere((c) => c.name == '餐饮');
      final acc = (await Repo.listAccounts()).first.id;
      final month = Fmt.month(DateTime.now());

      // 按天铺开：一天一张卡，20 张卡、200 行
      for (var d = 0; d < days; d++) {
        final day = '$month-${(d + 1).toString().padLeft(2, '0')}';
        for (var i = 0; i < perDay; i++) {
          await Repo.insertTxn(
            Txn(
              id: 0,
              ledgerId: s.ledgerId,
              type: TxnType.expense,
              amountCents: 100 + i,
              date: day,
              categoryId: cat.id,
              accountId: acc,
            ),
            // 全部落到「今天所在期」，明细页才看得到
            liftToNext: false,
          );
        }
      }
      await s.afterTxnChange();
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DetailPage())),
    );
    await tester.pumpAndSettle();

    final built = find.byType(TxnRow).evaluate().length;

    expect(built, greaterThan(0), reason: '第一屏总得画出点东西');
    expect(
      built,
      lessThan(total),
      reason: '懒加载没生效：$total 行全被建出来了',
    );
    // 一屏大约能放两三张日卡（每张 10 行），留足余量但必须显著小于总数
    expect(
      built,
      lessThan(100),
      reason: '只该建可视区域内的行（实测 $built / $total）',
    );
  });
}
