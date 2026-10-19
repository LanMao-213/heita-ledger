// 分类详情字段（出发地 / 目的地 / 对象 / 名称）的自检。
//
// 三件容易做错的事：
// 1) 只有登记过的子分类才该出现详情框 —— 给每个分类都塞四个空框等于把
//    录入面板撑长一倍，而 80% 的分类一个字段都用不上；
// 2) 出行类默认折叠、人情/成长类平铺：折叠的那些如果直接平铺，用户会把
//    「出发地/目的地」当成必填而卡住；
// 3) 存进库的值要能再读回来（编辑老记录时四个框得带着原值）。
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/category_seed.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/calc_keypad.dart';
import 'package:ledger/widgets/record_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_txn_detail.db';

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

  test('字段表只认登记过的子分类', () {
    expect(fieldsOfSub('公共交通'), [TxnField.from, TxnField.to]);
    expect(fieldsOfSub('打车'), [TxnField.from, TxnField.to]);
    expect(fieldsOfSub('红包份子'), [TxnField.person]);
    expect(fieldsOfSub('公益捐赠'), [TxnField.person]);
    expect(fieldsOfSub('课程培训'), [TxnField.subject]);
    expect(fieldsOfSub('书籍'), [TxnField.subject]);

    // 没登记的（含用户自建、以及一级分类名）一律不要详情框
    expect(fieldsOfSub('正餐'), isEmpty);
    expect(fieldsOfSub('餐饮'), isEmpty);
    expect(fieldsOfSub('我自己加的分类'), isEmpty);
    expect(fieldsOfSub(null), isEmpty);
  });

  test('折叠只作用于出行两类', () {
    expect(kFoldedSubs, {'公共交通', '打车'});
    for (final name in kFoldedSubs) {
      expect(fieldsOfSub(name), isNotEmpty, reason: '$name 折叠了却没字段可填');
    }
  });

  testWidgets('出行：默认折叠，展开后能填并落库', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showRecordSheet(ctx),
                child: const Text('记一笔'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    // 先选到「出行 / 公共交通」：左轮吃一次滚动（餐饮→出行），右轮一次（不细分→公共交通）
    await tester.tap(find.text('餐饮').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).at(0), const Offset(0, -52));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).at(1), const Offset(0, -52));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('公共交通'), findsWidgets);
    // 折叠状态：两个地点框都不在屏幕上
    expect(find.text('＋ 添加详情'), findsOneWidget);
    expect(find.text('出发地'), findsNothing);

    await tester.tap(find.text('＋ 添加详情'));
    await tester.pumpAndSettle();

    expect(find.text('出发地'), findsOneWidget);
    expect(find.text('目的地'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '从哪出发'), '家');
    await tester.enterText(find.widgetWithText(TextField, '到哪去'), '公司');
    await tester.pump();

    await tester.tap(
      find.descendant(of: find.byType(CalcKeypad), matching: find.text('5')),
    );
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );

    final rows = await tester.runAsync(
      () => Repo.listTxns(
        ledgerId: Store.i.ledgerId,
        month: Fmt.month(DateTime.now()),
      ),
    );
    expect(rows, isNotEmpty);
    final t = rows!.first;
    expect(t.placeFrom, '家');
    expect(t.placeTo, '公司');
    expect(t.person, isNull, reason: '没用到的字段要存 NULL，不能存空串');
    expect(t.detailSummary, '家 → 公司');
  });

  testWidgets('人情：对象直接平铺，编辑时带出原值', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());

    // 造一条「人情 / 红包份子 · 对象=张三」的记录，直接进编辑面板看回显
    final gift = Store.i.expenseCats.firstWhere((c) => c.name == '人情');
    final sub = Store.i.childrenOf(gift.id).firstWhere((c) => c.name == '红包份子');
    final id = await tester.runAsync(
      () => Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: Store.i.ledgerId,
          type: TxnType.expense,
          amountCents: 20000,
          date: Fmt.today(),
          categoryId: sub.id,
          accountId: Store.i.accounts.first.id,
          person: '张三',
        ),
      ),
    );
    final saved = (await tester.runAsync(
      () => Repo.listTxns(
        ledgerId: Store.i.ledgerId,
        month: Fmt.month(DateTime.now()),
      ),
    ))!.firstWhere((t) => t.id == id);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showRecordSheet(ctx, editing: saved),
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // 平铺：不用点「＋ 添加详情」就能看到对象框，且连着原值
    expect(find.text('＋ 添加详情'), findsNothing);
    expect(find.text('对象'), findsOneWidget);
    expect(find.widgetWithText(TextField, '张三'), findsOneWidget);
  });
}
