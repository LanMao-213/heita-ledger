// 双轮盘（分类 + 子分类）的交互自检。
//
// 三个容易出错的地方：
// 1) 左轮换分类后，右轮的内容必须整条换掉、并且回到「不细分」，
//    否则会残留上一组的滚动位置，选出一个不属于当前分类的子分类；
// 2) 只选到一级时要返回 subId = null，交易直接挂父级（这是「不细分」的语义）；
// 3) 编辑老记录时传进来的是**子分类 id**，轮盘要能反查出它的一级，
//    并把右轮停在该子分类上，而不是从第一项开始。
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
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
    WidgetTester tester, {
    required ValueSetter<CatPick?> onPicked,
    int? selectedCategoryId,
  }) async {
    final cats = Store.i.expenseCats;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showCategoryWheel(
                    ctx,
                    cats: cats,
                    childrenOf: Store.i.childrenOf,
                    selectedCategoryId: selectedCategoryId ?? cats.first.id,
                  );
                  onPicked(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// 让左轮/右轮滚动 [steps] 格（itemExtent 52）
  Future<void> roll(WidgetTester tester, int wheel, int steps) async {
    await tester.drag(
      find.byType(CupertinoPicker).at(wheel),
      Offset(0, -52.0 * steps),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认停在第一个一级分类 + 不细分', (tester) async {
    await tester.runAsync(() => Store.i.boot());
    final cats = Store.i.expenseCats;
    final first = cats.first;

    CatPick? picked;
    await openWheel(tester, onPicked: (p) => picked = p);

    // 右轮首项是「不细分」，左轮停在第一个一级
    expect(find.text('不细分'), findsOneWidget);
    expect(find.text(first.name), findsWidgets);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.categoryId, first.id);
    expect(picked!.subId, isNull, reason: '没动右轮就该是不细分');
    expect(picked!.txnCategoryId, first.id);
  });

  testWidgets('选子分类后带回子分类 id', (tester) async {
    await tester.runAsync(() => Store.i.boot());
    final first = Store.i.expenseCats.first;
    final subs = Store.i.childrenOf(first.id);
    expect(subs, isNotEmpty, reason: '一级分类应该有种子子分类');

    CatPick? picked;
    await openWheel(tester, onPicked: (p) => picked = p);

    // 右轮往下滚一格：「不细分」→ 第一个子分类
    await roll(tester, 1, 1);
    expect(find.text(subs.first.name), findsWidgets);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(picked!.categoryId, first.id);
    expect(picked!.subId, subs.first.id);
    expect(picked!.txnCategoryId, subs.first.id);
  });

  testWidgets('换一级分类后右轮重建，回到不细分', (tester) async {
    await tester.runAsync(() => Store.i.boot());
    final cats = Store.i.expenseCats;
    expect(cats.length, greaterThan(1));

    CatPick? picked;
    await openWheel(tester, onPicked: (p) => picked = p);

    // 先选一个子分类
    await roll(tester, 1, 1);
    // 再换一级：右轮必须回到「不细分」
    await roll(tester, 0, 1);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(picked!.categoryId, cats[1].id);
    expect(
      picked!.subId,
      isNull,
      reason: '换分类后右轮应回到首项，不能残留上一组的子分类',
    );
  });

  testWidgets('传入子分类 id 时，右轮停在它上面', (tester) async {
    await tester.runAsync(() => Store.i.boot());
    final first = Store.i.expenseCats.first;
    final subs = Store.i.childrenOf(first.id);
    expect(subs.length, greaterThan(1));
    final target = subs[1];

    CatPick? picked;
    await openWheel(
      tester,
      selectedCategoryId: target.id,
      onPicked: (p) => picked = p,
    );

    // 不做任何滚动，直接确定：应该原样带回这个子分类
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(picked!.categoryId, first.id, reason: '要能反查出子分类属于哪个一级');
    expect(picked!.subId, target.id);
  });
}
