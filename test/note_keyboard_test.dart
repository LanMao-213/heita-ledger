// 记一笔面板的键盘适配自检。
//
// 真机上的坑：点备注框后系统输入法弹出，把面板下半屏接管，备注框正好压在
// 它底下 —— 一边打字一边看不见自己写了什么。根因是面板整体没有让开
// `viewInsets.bottom`；而只加 padding 还不够：自绘数字键盘 274dp 高，
// 和 300dp 的系统键盘叠在一起会把可滚动区压成 0，备注框照样看不见。
//
// 所以这里钉两件事：
// 1) 备注框整体落在键盘上沿之上；
// 2) 写备注时数字键盘让位、出现「完成」，点完键盘回来（确认键不能丢）。
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

  testWidgets('备注聚焦时键盘不遮住输入框，且数字键盘让位', (tester) async {
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

    // 键盘让位：数字键盘收起，「完成」出现
    expect(find.byType(CalcKeypad), findsNothing);
    expect(find.text('完成'), findsOneWidget);

    // 备注框整个落在键盘上沿之上（844 − 300 = 544）
    final rect = tester.getRect(find.byType(TextField));
    expect(
      rect.bottom,
      lessThanOrEqualTo(_screenH - _keyboardH),
      reason: '备注框被输入法盖住了：底边 ${rect.bottom}，键盘上沿 ${_screenH - _keyboardH}',
    );
    expect(rect.height, greaterThan(0));

    // 点「完成」→ 收起输入法，数字键盘和确认键回来
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.byType(CalcKeypad), findsOneWidget);
    expect(find.text('完成'), findsNothing);
  });
}
