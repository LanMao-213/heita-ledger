// 计划页设预算的端到端自检。
//
// 为什么单独测这一条：预算改成按归属期存之后，写入用的是 `cycleFrom`，
// 读取也用 `cycleFrom` —— 这两处只要有一处用了别的期，界面上就是「设了没反应」，
// 而且不报错、不崩溃，很难从日志里看出来。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/plan_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_budget_flow.db';

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

  test('afterBudgetChange 能读回刚写的那一期预算', () async {
    await Store.i.boot();
    final s = Store.i;
    await Repo.setBudget(
      ledgerId: s.ledgerId,
      periodStart: s.cycleFrom,
      amountCents: 300000,
    );
    await s.afterBudgetChange();
    expect(s.totalBudgetCents, 300000,
        reason: '写入与读取用的必须是同一个期');
    expect(await Repo.totalBudgetCents(s.ledgerId, s.cycleFrom), 300000);
  });

  testWidgets('Store 里的预算变了，卡片必须跟着变（const 陷阱回归）', (tester) async {
    await tester.runAsync(() => Store.i.boot());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PlanPage())));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
    await tester.pump();
    expect(find.textContaining('还没有设预算'), findsOneWidget);

    // 模拟「用户设了预算」：直接写库 + 刷新 Store，然后推一帧
    final s = Store.i;
    await tester.runAsync(() async {
      await Repo.setBudget(
        ledgerId: s.ledgerId,
        periodStart: s.cycleFrom,
        amountCents: 300000,
      );
      await s.afterBudgetChange();
    });
    await tester.pump();

    // 曾经因为 `const _TotalBudgetCard()` 是规范化实例，Store 通知后 Element
    // 判定「同一个 widget」直接跳过 build，卡片一直停在「还没有设预算」。
    expect(
      find.textContaining('还没有设预算'),
      findsNothing,
      reason: '组件用 const 实例化时，Store 通知不会触发重建（数字停在旧值）',
    );
    expect(s.totalBudgetCents, 300000);
  });
}
