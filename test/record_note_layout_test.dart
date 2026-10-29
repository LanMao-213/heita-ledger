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
// 现在的规则（见 record_sheet/layout.dart 的 `solveKeypadSlot`）：
// 数字键盘不再自己「收起」，而是**按输入法高度 1:1 被顶出去**。面板高度 =
// 内容 + 剩余键盘，底边 = 输入法上沿，两者相消 —— 顶边在整段动画里不动。
//
// 这里钉四条：
//   1. 备注框与输入法上沿的间距 ≤ 24dp（修好前是 102dp）；
//   2. 输入法从 0 升到 300 的**每一帧**（每帧 5dp），面板顶边逐帧位移 ≤ 2dp，
//      且全程不偏离静止位超过 2dp；
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

/// 面板顶边的容差。
///
/// 曾经是 40：因为 `_keypadSlotHeight` 里有一条 `left < 40 ? 0 : left` 的
/// 门槛 —— 数字键盘还剩不到一排键时整块收掉，那一下顶边会移动不到 40dp，
/// 于是容差只能放宽到 40 才不红。
///
/// **40 这个数字是尺子跟着实现弯的产物**：它宽到足以吞掉整条门槛（39.99dp），
/// 于是「顶边抽搐」这件事再也测不出来了。顶边是用户唯一真正看见的东西，
/// 它的容差必须按**人眼**定，不按实现的分段点定 —— 2dp。修完这条门槛，
/// 顶边在整个升降过程中应当恒定（恒等式见 `record_sheet.dart`）。
const _topTolerance = 2.0;

/// 输入法升旗 / 退旗每帧走多少 dp。
///
/// 原来是 6 帧 × 50dp。50dp 的步长本身就是一个失明点：任何 < 50dp 的单帧
/// 跳变都会被「一帧走 50」的采样吞掉。5dp 才对得起 2dp 的容差。
const _imeStepDp = 5.0;
const _imeSteps = 60;

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
    // 5 排键 280 + 4 条缝 24 + 内边距 20。这个数被 `solveKeypadSlot` 用来
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

    // 1.6.0 起这个间距多了一截：输入法完全升起时，键盘槽里还留着
    // `自然高度 − 输入法高度`（324 − 300 = 24dp）的碎边 —— 留着它是为了让面板
    // 顶边不动（见 record_sheet/layout.dart 的恒等式），碎边本身被渐隐溶掉。
    //
    // 所以判据分两条，缺一条都可以糊弄过去：
    //   1) 总留白 ≤ 24 + 碎边（碎边之外不许再有别的白）；
    //   2) **把碎边减掉之后**的留白 ≤ 24 —— 这条才是用户原话「留白过高」
    //      真正针对的东西（修好前是 102dp）。
    final slotFinder = find.byKey(const ValueKey('record_keypad_slot'));
    final slotH = slotFinder.evaluate().isEmpty
        ? 0.0
        : tester.getSize(slotFinder).height;
    expect(
      slotH,
      closeTo(CalcKeypad.heightOf(56) - _keyboardH, 0.5),
      reason: '槽高应当是「自然高度 − 输入法高度」，实际 $slotH',
    );
    expect(
      gap,
      lessThanOrEqualTo(24 + slotH),
      reason: '备注框与键盘之间留白 ${gap.toStringAsFixed(1)}dp（槽高 $slotH）',
    );
    expect(
      gap - slotH,
      lessThanOrEqualTo(24),
      reason: '减掉碎边之后还留白 ${(gap - slotH).toStringAsFixed(1)}dp —— 这块空白'
          '就是用户说的「留白过高」',
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

    // 输入法按真机时序**逐帧**升起：60 帧走完 300dp（每帧 5dp）
    var prev = _panelTop(tester);
    final rising = <double>[];
    for (var i = 1; i <= _imeSteps; i++) {
      tester.view.viewInsets = FakeViewPadding(
        bottom: _imeStepDp * _dpr * i,
      );
      await tester.pump(const Duration(milliseconds: 16));
      final top = _panelTop(tester);
      rising.add(top);
      expect(
        (top - prev).abs(),
        lessThanOrEqualTo(_topTolerance),
        reason: '第 $i 帧（输入法 ${(_imeStepDp * i).toStringAsFixed(0)}dp）'
            '面板顶边从 ${prev.toStringAsFixed(1)} 跳到 '
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
    for (var i = _imeSteps - 1; i >= 0; i--) {
      tester.view.viewInsets = FakeViewPadding(
        bottom: _imeStepDp * _dpr * i,
      );
      await tester.pump(const Duration(milliseconds: 16));
      final top = _panelTop(tester);
      expect(
        (top - prev).abs(),
        lessThanOrEqualTo(_topTolerance),
        reason: '退旗第 $i 步（输入法 ${(_imeStepDp * i).toStringAsFixed(0)}dp）'
            '面板顶边从 ${prev.toStringAsFixed(1)} 跳到 '
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
