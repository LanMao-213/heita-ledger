// 记一笔面板：备注 / 数字键盘的键盘适配（2026-10-28 用户反馈的第 3 条）。
//
// 反馈原文两句：
//   「输入备注时，下方与键盘之间留白过高」
//   「返回输入金额时界面会『抽搐』一下」
//
// 两句话是同一个错误的两面：1.4.x 写备注时把面板钉在 0.9 屏高、又不给输入法
// 让位（reserved = 0），于是
//   1) 面板满高、内容顶对齐 —— 多出来的高度全堆在备注框下面（实测 102dp）；
//   2) 失焦那一帧 minHeight 从满高掉到 0，面板当场塌 380dp，数字键盘再用
//      150ms 长回来把内容顶回去 —— 一帧下坠 + 一段回升 = 抽搐。
//
// 现在的规则（见 record_sheet.dart 里 `_keypadSlotHeight`）：
// 数字键盘不再自己「收起」，而是**按输入法高度 1:1 被顶出去**。面板高度 =
// 内容 + 剩余键盘，底边 = 输入法上沿，两者相消 —— 顶边在整段动画里不动。
//
// 这里钉四条：
//   1. 备注框与输入法上沿的间距 ≤ 24dp（修好前是 102dp）；
//   2. 输入法从 0 升到 300 的每一帧，面板顶边偏离静止位不超过 40dp；
//   3. 退回金额输入时（300 → 0）同样不跳，且数字键盘完整回来；
//   4. 期间没有任何布局溢出（笔记里那一堆 RenderFlex overflow 都会抛异常）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/calc_keypad.dart';
import 'package:ledger/widgets/record_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_record_note_layout.db';

const _screenH = 844.0;
const _keyboardH = 300.0;
const _dpr = 3.0;

/// 面板顶边的容差。留 40 是因为「数字键盘还剩不到一排键」时会被整块收掉
/// （见 `_keypadSlotHeight` 的 40dp 门槛），那一下顶边会移动不到 40dp。
/// 修好前这里是 152dp（单帧跳变），留 40 才有意义。
const _topTolerance = 40.0;

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 面板顶边。用备注框上面那条「记一笔标题」当锚点：它离面板顶只有 30dp，
/// 且不随键盘高度改位置 —— 拿它代表面板顶边足够准，也不必依赖 ClipRRect 的层级。
double _panelTop(WidgetTester tester) =>
    tester.getRect(find.text('记一笔').last).top;

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  tearDownAll(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  test('键盘自然高度与排版公式一致（56 键高 = 324dp）', () {
    // 5 排键 280 + 4 条缝 24 + 内边距 20。这个数被 `_keypadSlotHeight` 用来
    // 决定「被输入法顶掉多少」，算错就是「确认键被切掉」或「键盘底下露白」。
    expect(CalcKeypad.heightOf(56), 324);
    expect(CalcKeypad.heightOf(52), 304);
  });

  testWidgets('备注聚焦：备注框贴着输入法上沿（原来空 102dp）', (tester) async {
    tester.view.physicalSize = const Size(390 * _dpr, _screenH * _dpr);
    tester.view.devicePixelRatio = _dpr;
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

    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardH * _dpr);
    await tester.pumpAndSettle();

    final note = tester.getRect(find.byType(TextField));
    final imeTop = _screenH - _keyboardH;
    final gap = imeTop - note.bottom;

    expect(
      gap,
      lessThanOrEqualTo(24),
      reason: '备注框与键盘之间留白 ${gap.toStringAsFixed(1)}dp —— 这块空白就是用户说的'
          '「留白过高」',
    );
    expect(gap, greaterThanOrEqualTo(0), reason: '备注框被输入法盖住了');
    expect(tester.takeException(), isNull);

    // 收尾：键盘退回去，确认数字键盘完整回来（不是被剪了一半）
    await tester.testTextInput.receiveAction(TextInputAction.done);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    final pad = tester.getRect(find.byType(CalcKeypad));
    expect(pad.height, CalcKeypad.heightOf(56), reason: '数字键盘没长回原高度');
    expect(pad.bottom, lessThanOrEqualTo(_screenH + 0.5));
  });

  testWidgets('输入法升旗 / 退旗：面板顶边不跳（逐帧量）', (tester) async {
    tester.view.physicalSize = const Size(390 * _dpr, _screenH * _dpr);
    tester.view.devicePixelRatio = _dpr;
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

    final restTop = _panelTop(tester);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    // 输入法按真机时序**逐帧**升起：6 帧走完 300dp
    var prev = _panelTop(tester);
    final rising = <double>[];
    for (var i = 1; i <= 6; i++) {
      tester.view.viewInsets = FakeViewPadding(
        bottom: _keyboardH * _dpr * i / 6,
      );
      await tester.pump(const Duration(milliseconds: 16));
      final top = _panelTop(tester);
      rising.add(top);
      expect(
        (top - prev).abs(),
        lessThanOrEqualTo(_topTolerance),
        reason: '第 $i 帧面板顶边从 ${prev.toStringAsFixed(1)} 跳到 '
            '${top.toStringAsFixed(1)} —— 这就是「抽搐」',
      );
      prev = top;
    }
    await tester.pumpAndSettle();

    for (final top in rising) {
      expect(
        (top - restTop).abs(),
        lessThanOrEqualTo(_topTolerance),
        reason: '输入法升起过程中面板顶边偏离静止位 ${(top - restTop).abs().toStringAsFixed(1)}dp',
      );
    }
    expect(tester.takeException(), isNull);

    // 退回金额输入：同样逐帧，同样不许跳
    await tester.testTextInput.receiveAction(TextInputAction.done);
    prev = _panelTop(tester);
    for (var i = 5; i >= 0; i--) {
      tester.view.viewInsets = FakeViewPadding(
        bottom: _keyboardH * _dpr * i / 6,
      );
      await tester.pump(const Duration(milliseconds: 16));
      final top = _panelTop(tester);
      expect(
        (top - prev).abs(),
        lessThanOrEqualTo(_topTolerance),
        reason: '退旗第 $i 帧面板顶边从 ${prev.toStringAsFixed(1)} 跳到 '
            '${top.toStringAsFixed(1)}',
      );
      expect(
        (top - restTop).abs(),
        lessThanOrEqualTo(_topTolerance),
        reason: '退旗过程中面板顶边偏离静止位 ${(top - restTop).abs().toStringAsFixed(1)}dp',
      );
      prev = top;
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      _panelTop(tester),
      closeTo(restTop, 0.5),
      reason: '键盘收起后没回到原位 —— 用户会看到面板「掉下去又回来」',
    );
    expect(find.byType(CalcKeypad), findsOneWidget);
  });
}
