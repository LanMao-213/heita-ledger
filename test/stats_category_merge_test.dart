// 统计页「各分类消费统计」：合并后的口径自检。
//
// 1.5.2 把原来两张卡（「记得最多」按**笔数** + 「预算 vs 实际」按**金额**）
// 并成一张。合并之后有三处容易错、而且错了不会崩的地方：
//   1) 排序口径 —— 已拍板**按金额降序**（不是笔数）。用户看这一屏要回答的是
//      「钱花在哪」，不是「哪类记得最多」；
//   2) 两张卡里出现过的信息不能丢 —— 笔数还在、预算进度还在；
//   3) 下钻入口还在（点一行 → 明细只筛这个分类，见 category_jump_test）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
import 'package:ledger/pages/home_shell.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_stats_merge.db';

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
    ThemeCtrl.i.loadSilently(kDefaultTheme);
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  testWidgets('按金额降序、笔数与预算都在、两张旧卡消失', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    late int bigId;
    late int manyId;

    await tester.runAsync(() async {
      await Store.i.boot();
      final s = Store.i;
      final acc = s.accounts.first.id;
      final big = s.expenseCats.firstWhere((c) => c.name == '出行');
      final many = s.expenseCats.firstWhere((c) => c.name == '餐饮');
      bigId = big.id;
      manyId = many.id;

      // 出行：1 笔大额；餐饮：3 笔小额 —— 金额与笔数的排序结果**相反**，
      // 这样"按金额"和"按笔数"才区分得开。
      Future<void> add(int catId, int cents) => Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.expense,
          amountCents: cents,
          date: Fmt.today(),
          categoryId: catId,
          accountId: acc,
        ),
      );
      await add(bigId, 100000); // ¥1,000.00
      for (var i = 0; i < 3; i++) {
        await add(manyId, 1000); // 3 × ¥10.00
      }
      // 餐饮设一个**低于**实际支出的预算：进度条要转红并写出「超 X」
      await Repo.setBudget(
        ledgerId: s.ledgerId,
        periodStart: s.cycleFrom,
        categoryId: manyId,
        amountCents: 2000,
      );
      await s.afterTxnChange();
    });

    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图表'));
    await tester.pumpAndSettle();

    // 旧的「两张卡」必须真的没了，而不只是挪了位置
    expect(find.text('各分类消费统计'), findsOneWidget);
    expect(find.text('记得最多'), findsNothing);
    expect(find.text('预算 vs 实际'), findsNothing);

    final bigRow = find.byKey(ValueKey('freq-$bigId'));
    final manyRow = find.byKey(ValueKey('freq-$manyId'));
    expect(bigRow, findsOneWidget);
    expect(manyRow, findsOneWidget);

    // 按金额降序：1 笔 ¥1,000 排在 3 笔 ¥30 前面
    expect(
      tester.getTopLeft(bigRow).dy,
      lessThan(tester.getTopLeft(manyRow).dy),
      reason: '合并不是按笔数排 —— 口径已拍板为按金额降序',
    );

    // 笔数作为次要信息保留
    expect(find.text('1 笔'), findsWidgets);
    expect(find.text('3 笔'), findsWidgets);
    // 超支的预算进度以「超 X」写在行内
    expect(find.textContaining('超 '), findsWidgets);
  });
}
