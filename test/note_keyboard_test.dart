// 记一笔面板的键盘适配自检。
//
// 真机上的两个坑：
// 1) 点备注框后系统输入法弹出，把面板下半屏接管，备注框正好压在它底下；
// 2) 写备注时下面又冒出一颗「完成」按钮 —— 面板高度来回变、内容重排，
//    看起来像「又打开了一个新页面」。用户明确要求去掉它：输入法自带的
//    「完成」或直接收起键盘，就是这个意思。
//
// 所以这里钉四件事：
// 1) 备注框整体落在键盘上沿之上；
// 2) 写备注时数字键盘让位，且**没有**「完成」按钮；
// 3) 输入法点「完成」→ 收起键盘 → 数字键盘和确认键回来；
// 4) 键盘收起后，最后一排（0 / . / 确认）没有被屏幕底边裁掉。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/calc_keypad.dart';
import 'package:ledger/widgets/record_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_note_keyboard.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 屏幕逻辑高度与模拟的输入法高度（逻辑像素）
const _screenH = 844.0;
const _keyboardH = 300.0;

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

  testWidgets('备注聚焦时键盘不遮住输入框，数字键盘让位且没有「完成」', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, _screenH * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await Store.i.boot();
    });

    // 走真实路径：showRecordSheet 用的是 showModalBottomSheet
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Center(
            child: TextButton(
              onPressed: () => showRecordSheet(c),
              child: const Text('记一笔'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    // 还没碰备注框：数字键盘在场
    expect(find.byType(CalcKeypad), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // 点下去之后系统输入法才弹出来（按真实时序：先聚焦，再收到 insets 变化）
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardH * 2);
    await tester.pumpAndSettle();

    // 键盘让位：数字键盘收起；不再有替代它的「完成」按钮
    expect(find.byType(CalcKeypad), findsNothing);
    expect(find.text('完成'), findsNothing);

    // 备注框整个落在键盘上沿之上（844 − 300 = 544）
    final rect = tester.getRect(find.byType(TextField));
    expect(
      rect.bottom,
      lessThanOrEqualTo(_screenH - _keyboardH),
      reason: '备注框被输入法盖住了：底边 ${rect.bottom}，键盘上沿 ${_screenH - _keyboardH}',
    );
    expect(rect.height, greaterThan(0));

    // 用输入法自带的「完成」：收起键盘，数字键盘和确认键回来
    await tester.testTextInput.receiveAction(TextInputAction.done);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(find.byType(CalcKeypad), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
  });

  testWidgets('小屏 + 底部手势条：键盘最后一排不会被裁掉', (tester) async {
    // 360 × 740 是那台真机的逻辑尺寸量级；底部 24 是手势条的高度。
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(bottom: 24 * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24 * 3);
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Center(
            child: TextButton(
              onPressed: () => showRecordSheet(c),
              child: const Text('记一笔'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    // 没有溢出异常（溢出只会表现为最后一排被裁，debug 里是 RenderFlex overflow）
    expect(tester.takeException(), isNull);

    // 数字键盘整体得让开手势条：底部 24 是系统条，压上去就等于「确认」被裁
    final pad = tester.getRect(find.byType(CalcKeypad));
    expect(
      pad.bottom,
      lessThanOrEqualTo(740 - 24 + 0.5),
      reason: '键盘落进了手势条区域：底边 ${pad.bottom}',
    );
  });
}
