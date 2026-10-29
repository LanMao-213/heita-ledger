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

const _slotKey = ValueKey('record_keypad_slot');
const _fadeKey = ValueKey('record_keypad_shatter_fade');

/// 数字键盘是不是「已经让开了」。
///
/// 1.6.0 起判据从「CalcKeypad 这个 widget 不在场」变成「露出来的部分全都不可读」：
///
/// - 槽高为 0 → 整块不出现，显然让开了；
/// - continuous 档 → 槽里只剩一条碎边，且这条碎边被渐隐盖满（`shatterFade`
///   == 槽高），也就是一个可读的键都没露出来；
/// - hardCut 档 → 退回旧判据，整块不在场。
///
/// 这样写而不是到处 `findsNothing`：契约变了（布局层不再分段），但用户看到的
/// 「键盘让开了」这件事没变。
bool _keypadYielded(WidgetTester tester) {
  final slot = find.byKey(_slotKey);
  if (slot.evaluate().isEmpty) return true;
  final slotH = tester.getSize(slot).height;
  expect(slotH, greaterThanOrEqualTo(0));
  if (kKeypadYield == KeypadYield.hardCut) return false;
  final fade = find.byKey(_fadeKey);
  if (fade.evaluate().isEmpty) return false;
  return tester.getSize(fade).height >= slotH - 0.5;
}

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

    // 键盘让位：露出来的部分全是渐隐（见 `_keypadYielded`）；不再有替代它的
    // 「完成」按钮
    expect(
      _keypadYielded(tester),
      isTrue,
      reason: '输入法升满之后数字键盘仍然可读 —— 用户会看到一排半截的键贴在输入法上沿',
    );
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

  // 真机上的第三个坑（1.4.1 用户反馈）：点备注卡片时，面板像「重新打开了一次」。
  // 根因是数字键盘要等输入法真的升起（`viewInsets > 0`）才收起 —— 输入法升起
  // 那几帧里面板正被顶高、而 290dp 的数字键盘还占着位置，可滚动区被压成 0，
  // 备注框先被挤没、再弹回来。所以这里钉住：**点下去的那一帧**键盘就让位，
  // 不等输入法。
  testWidgets('点备注的那一帧数字键盘就让位，不等输入法升起', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, _screenH * 2);
    tester.view.devicePixelRatio = 2.0;
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
    expect(find.byType(CalcKeypad), findsOneWidget);

    // 只点、只 pump 一帧：此时 viewInsets 还是 0（输入法还没起来）
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // ★ 1.5.0 起这条契约变了：数字键盘**不再自己收起**，而是「按输入法高度
    // 1:1 被顶出去」——所以点下去那一帧它当然还在（输入法还没占地方）。
    // 要钉的从「键盘没了」变成「键盘块的高度 = 自然高度 − 输入法高度」，
    // 以及面板不给键盘留空（见 record_note_layout_test 的逐帧断言）。
    //
    // 为什么改：AnimatedSize 的 150ms 和输入法升起的 200~300ms 永远对不齐，
    // 快了面板先塌、慢了可滚动区被压成 0，两种都是「面板跳了一下」（1.4.1 的
    // 用户反馈）。跟着输入法走之后，面板顶边在整段动画里不动。
    // 量「还剩多少露在外面」要量槽，不是量键盘：键盘自己的 rect 永远是自然
    // 高度（它被自己的排版尺寸撑开，只是被外层剪掉）。
    const slotKey = ValueKey('record_keypad_slot');
    final padFull = tester.getSize(find.byKey(slotKey)).height;
    expect(padFull, 324, reason: '56 键高 + 4 条缝 + 内边距 = 324');

    // 输入法升到 100dp：键盘块应剩 224dp（324 − 100）
    tester.view.viewInsets = const FakeViewPadding(bottom: 100 * 2);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(slotKey)).height,
      closeTo(padFull - 100, 0.5),
      reason: '键盘块没有按输入法高度 1:1 让位',
    );

    // 再升到 200dp：剩 124dp
    tester.view.viewInsets = const FakeViewPadding(bottom: 200 * 2);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(slotKey)).height,
      closeTo(padFull - 200, 0.5),
    );

    // 升满 300dp：324 − 300 = 24，槽里只剩一条碎边。
    //
    // 1.6.0 起这条契约变了。老口径是「碎边不到一排键就整块收掉」，那是用**布局**
    // 手段解决**视觉**问题：槽高在跨过 40dp 的那一帧从 39 掉到 0，面板顶边当场
    // 往上跳 40dp（2026-10 用户反馈的「抽搐」）。现在碎边留着，交给槽下沿的一条
    // 渐隐溶进卡面（`kKeypadShatterFade`），布局层保持连续。
    //
    // 下面按 `kKeypadYield` 分支：逃生阀切到 hardCut 时退回旧行为，这条测试跟着
    // 一起退，不需要改代码 —— 这也是那个常量存在的意义。
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardH * 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (kKeypadYield == KeypadYield.continuous) {
      expect(
        tester.getSize(find.byKey(slotKey)).height,
        closeTo(padFull - _keyboardH, 0.5),
        reason: '碎边应当留在槽里（324 − 300 = 24），而不是整块收掉',
      );
      final fade = tester.widget<Container>(
        find.byKey(const ValueKey('record_keypad_shatter_fade')),
      );
      expect(fade, isNotNull, reason: '碎边没有被溶掉 —— 会露出一排半截的键');
      expect(
        tester.getSize(find.byKey(const ValueKey('record_keypad_shatter_fade')))
            .height,
        24,
        reason: '24dp 的碎边应当整条被渐隐盖住',
      );
    } else {
      expect(
        find.byType(CalcKeypad),
        findsNothing,
        reason: 'hardCut 档：剩下的碎边不到一排键，整块让开',
      );
      expect(
        find.byKey(const ValueKey('record_keypad_shatter_fade')),
        findsNothing,
        reason: 'hardCut 档没有碎边可溶（槽高直接归零），不该画渐隐',
      );
    }

    // 收起键盘（输入法「完成」）→ 数字键盘和确认键回来
    await tester.testTextInput.receiveAction(TextInputAction.done);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.byType(CalcKeypad), findsOneWidget);
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
