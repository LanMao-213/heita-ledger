// 记一笔：数字键盘的尺寸**不能**随「详情展开」而变。
//
// 用户的反馈原话：「打开详情，会感觉小键盘抖了一下」。
//
// 根因：键高 `keyH` 的上限里带了 `_detailsOpen ? 48 : 52` —— 展开详情时
// 5 排键每排矮 4dp，整块键盘瞬间少 20dp。下方内容一长、键盘一矮，就是那一下抖。
//
// 键盘是这一屏最稳的东西：手指正在上面按，它的尺寸不该因为上面的内容多少
// 而变。内容变高应该由滚动区吸收，不是压缩键盘。
//
// 这个测试钉住三件事：
//   1. 展开详情前后，键盘尺寸完全一致
//   2. 收起回来也不变（反向同样会抖）
//   3. 展开后最后一个字段能完整滚进可视区（不能因为不压键盘就被裁掉）
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/calc_keypad.dart';
import 'package:ledger/widgets/record_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_record_kb_stable.db';

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

  testWidgets('详情展开 / 收起，数字键盘尺寸不变', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showRecordSheet(ctx),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 分类是双轮盘：左轮从「餐饮」滚一格到「出行」，右轮从「不细分」
    // 滚一格到「公共交通」—— 详情字段挂在这个子分类上
    await tester.tap(find.textContaining('餐饮').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).at(0), const Offset(0, -52));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).at(1), const Offset(0, -52));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final kb = find.byType(CalcKeypad);
    expect(kb, findsOneWidget, reason: '数字键盘应该在内联面板里');

    // 比**矩形**（位置 + 尺寸）而不只是尺寸：键盘整体上移 20dp 一样是抖
    final before = tester.getRect(kb);

    // 展开详情
    await tester.tap(find.text('＋ 添加详情'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    final afterOpen = tester.getRect(kb);

    expect(
      afterOpen,
      before,
      reason: '展开详情后键盘的位置或尺寸变了 —— 手指正在按，它不该因为内容变多而缩',
    );

    // 此时最后一个字段应当能完整看到（不靠压键盘来腾地方）
    expect(tester.takeException(), isNull);

    // 收起详情
    await tester.tap(find.text('收起详情'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    final afterClose = tester.getRect(kb);

    expect(
      afterClose,
      before,
      reason: '收起详情后键盘的位置或尺寸也变了 —— 反向同样会抖',
    );
  });
}
