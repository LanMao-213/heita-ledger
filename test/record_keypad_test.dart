// 记一笔数字键盘的命中区自检。
//
// 曾经的真实 bug：每个键用 GestureDetector 默认的 deferToChild，而它的子节点
// 只有 SizedBox + Center + Text —— 命中区退化成数字字形那一小块（约 14×25），
// 键位格子里绝大部分区域点下去毫无反应，表现为「键盘很不灵敏，要按在笔画上」。
//
// 这个测试专门点「字形的左上角之外、但仍在键位格子内」的位置：
// 用 deferToChild 会失败，用 opaque 才会通过。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/calc_keypad.dart';
import 'package:ledger/widgets/record_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_record_keypad.db';

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

  testWidgets('点键位格子的边缘也能输入，并能保存', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());

    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    // 打开时金额为 0，键盘上的「5」应该只有一个（键盘本身）
    expect(find.text('5'), findsOneWidget);
    final glyph = tester.getRect(find.text('5'));

    // 往左偏 30 逻辑像素、高度对准字形中心：仍在键位格子内，但已经离开字形。
    // 用默认 deferToChild 时这一下会落空，改成 opaque 才会命中。
    await tester.tapAt(Offset(glyph.center.dx - 30, glyph.center.dy));
    await tester.pump();

    // 金额显示区也多了一个「5」
    expect(find.text('5'), findsNWidgets(2));

    // 能存下来才算真的通（确认键 = 结算并保存）
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    final rows = await tester.runAsync(() => Repo.listTxns(
          ledgerId: Store.i.ledgerId,
          month: Fmt.month(DateTime.now()),
        ));
    expect(rows, isNotNull);
    expect(rows!.length, 1);
    expect(rows.first.amountCents, 500);
    expect(rows.first.type, TxnType.expense);
  });

  testWidgets('行首负号能录入并落到数据库（净额记账）', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    // 按键要在键盘范围内找：金额显示区也会出现 '-' 和数字
    Finder key(String t) => find.descendant(
          of: find.byType(CalcKeypad),
          matching: find.text(t),
        );

    // 行首按减号 → 负数
    await tester.tap(key('-'));
    await tester.pump();
    await tester.tap(key('2'));
    await tester.tap(key('0'));
    await tester.pump();

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    final rows = await tester.runAsync(() => Repo.listTxns(
          ledgerId: Store.i.ledgerId,
          month: Fmt.month(DateTime.now()),
        ));
    expect(rows!.any((t) => t.amountCents == -2000), isTrue,
        reason: '应有一条 −20.00 的记录');
  });
}
