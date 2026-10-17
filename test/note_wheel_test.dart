// 双轮盘（分类 + 名目）的交互自检。
//
// 两个容易出错的地方：
// 1) 左轮换分类后，右轮的内容必须整条换掉、并且回到第一项，
//    否则会残留上一个分类的滚动位置，选出一个不存在的名目；
// 2) 备注对不上任何名目时（含空），右轮要停在「自定义…」，
//    确定时不能把备注覆盖成某个名目。
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/note_hints.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/picker_wheels.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_note_wheel.db';

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

  /// 打开双轮盘，并把用户的选择交给 [onPicked]
  Future<void> openWheel(
    WidgetTester tester,
    List<Category> cats, {
    String note = '',
    required ValueSetter<NotePick?> onPicked,
    int? categoryId,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await showCategoryNoteWheel(
                  ctx,
                  cats: cats,
                  categoryId: categoryId ?? cats.first.id,
                  type: TxnType.expense,
                  note: note,
                );
                onPicked(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('备注为空时停在「自定义…」，确定不覆盖备注', (tester) async {
    await tester.runAsync(() => Store.i.boot());
    final cats = Store.i.expenseCats;

    NotePick? picked;
    await openWheel(tester, cats, onPicked: (p) => picked = p);

    expect(find.text('自定义…'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.categoryId, cats.first.id);
    expect(picked!.note, isNull);
  });

  testWidgets('换分类后右轮联动，确定带回新分类与首个名目', (tester) async {
    await tester.runAsync(() => Store.i.boot());
    final cats = Store.i.expenseCats;
    final traffic = cats.firstWhere((c) => c.name == '交通');

    NotePick? picked;
    // 备注「午饭」命中餐饮的名目，右轮初始应停在那里
    await openWheel(tester, cats, note: '午饭', onPicked: (p) => picked = p);
    expect(find.text('午饭'), findsWidgets);

    // 左轮往下滚一格：餐饮 → 交通（itemExtent 40）
    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, -40));
    await tester.pumpAndSettle();

    expect(find.text('地铁'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.categoryId, traffic.id);
    expect(picked!.note, noteHintsFor(TxnType.expense, '交通').first);
  });
}
