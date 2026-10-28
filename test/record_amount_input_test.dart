// 记一笔：金额区的**显示口径**自检。
//
// 用户反馈（2026-10-28）：「只输入 1，点数字再点小数点，数字变成 0，
// 要继续输入下一位才显现」。
//
// 根因不在键盘，而在金额区的取值口径：`_AmountDisplay` 用的是
// `Calc.cents`（「这个表达式能不能存」），`1.` 还没输完 → 返回 null →
// 显示兜底值 `0`。用户刚按完小数点，屏幕上的 1 却没了。
//
// 同一个错误在**按运算符**时也会犯：`12+` 同样是 null → 也显示 `0`。
// 所以这里钉两条：小数点、运算符之后，已经敲进去的数字必须还在。
//
// 口径分家（这是本次修法的核心）：
// - `Calc.cents`：能不能存。未输完 = null，确认键据此置灰。
// - `Calc.display`：已经敲了什么。`1.` 要显示 1 并标记「停在小数点」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/calc_keypad.dart';
import 'package:ledger/widgets/record_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_record_amount_input.db';

/// 金额区那颗大数字。键盘上也有数字键，不能靠 `find.text('0')` 认 —— 会撞上
/// 「0」键。所以金额区带一个 key，测试直接读它的文案。
const _amountKey = ValueKey('record_amount_value');

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 点一个键。键位表只有一个来源（[CalcKeypad]），这里按标签找，
/// 顺序与用户手指一致 —— 不去碰 `Calc.press`，否则测的是纯函数不是界面。
Future<void> _key(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(CalcKeypad), matching: find.text(label)),
  );
  await tester.pump();
}

String _amount(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_amountKey)).data!;

Future<void> _openSheet(WidgetTester tester) async {
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
}

void _screen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

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

  testWidgets('输入 1 后按小数点，1 不能消失成 0', (tester) async {
    _screen(tester);
    await _openSheet(tester);

    expect(_amount(tester), '0', reason: '什么都没输入时是 0');

    await _key(tester, '1');
    expect(_amount(tester), '1');

    await _key(tester, '.');
    expect(
      _amount(tester),
      '1.',
      reason: '按完小数点，已经敲进去的 1 必须还在（旧实现把它显示成 0）',
    );

    await _key(tester, '.');
    expect(_amount(tester), '1.', reason: '小数点按两次不该变成 1..');

    await _key(tester, '5');
    // 1.6.0 起不再补零：输入 1.5 就显示 1.5（旧口径一律两位小数 → 1.50）
    expect(_amount(tester), '1.5', reason: '小数位按用户敲的原样显示，不补零');
  });

  testWidgets('按运算符之后，已经敲进去的数字不能消失', (tester) async {
    _screen(tester);
    await _openSheet(tester);

    await _key(tester, '1');
    await _key(tester, '2');
    await _key(tester, '+');

    // 表达式那一行显示 `12+`，金额区仍应显示 12（旧实现显示 0）
    expect(find.text('12+'), findsOneWidget);
    expect(_amount(tester), '12');

    await _key(tester, '8');
    expect(_amount(tester), '20', reason: '12 + 8 应实时算出 20');
  });

  testWidgets('行首按小数点自动补 0，且能继续输', (tester) async {
    _screen(tester);
    await _openSheet(tester);

    await _key(tester, '.');
    expect(_amount(tester), '0.', reason: '行首按小数点自动补 0');

    await _key(tester, '5');
    expect(_amount(tester), '0.5', reason: '同样不补零');
  });

  testWidgets('负数：行首负号后仍能看到自己敲的数字', (tester) async {
    _screen(tester);
    await _openSheet(tester);

    await _key(tester, '-');
    expect(_amount(tester), '0', reason: '只有一个负号时还谈不上金额');

    await _key(tester, '2');
    expect(_amount(tester), '-2');
  });
}
