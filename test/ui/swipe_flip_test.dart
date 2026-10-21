import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/ui/widgets/swipe_flip.dart';

import '../support/ui_fixture.dart';

/// 手势：左右滑动翻期、双击回今天、单击弹选择器、禁用时不抢手势。
void main() {
  int prev = 0;
  int next = 0;
  int today = 0;
  int pick = 0;

  Widget swipe({bool enabled = true}) => host(
    SwipeFlip(
      enabled: enabled,
      onPrev: () => prev++,
      onNext: () => next++,
      onToday: () => today++,
      onPick: () => pick++,
      child: const SizedBox(width: 300, height: 120),
    ),
  );

  setUp(() {
    prev = 0;
    next = 0;
    today = 0;
    pick = 0;
  });

  testWidgets('⑥ 左滑（≥48px）→ 下一期', (WidgetTester tester) async {
    await UiHarness().pump(tester, swipe());

    await tester.drag(find.byType(SwipeFlip), const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(next, 1, reason: '手指往左滑 = 看下一期');
    expect(prev, 0);
  });

  testWidgets('⑥ 右滑（≥48px）→ 上一期', (WidgetTester tester) async {
    await UiHarness().pump(tester, swipe());

    await tester.drag(find.byType(SwipeFlip), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(prev, 1);
    expect(next, 0);
  });

  testWidgets('⑥ 位移不足 48px 不翻期（防误触）', (WidgetTester tester) async {
    await UiHarness().pump(tester, swipe());

    await tester.drag(find.byType(SwipeFlip), const Offset(-20, 0));
    await tester.pumpAndSettle();

    expect(next, 0);
  });

  testWidgets('⑥ 快速滑动（速度够）即使位移小也算翻期', (WidgetTester tester) async {
    await UiHarness().pump(tester, swipe());

    // 不用 `tester.fling`：它在 FakeAsync 下把事件时间戳全压成 0，
    // DragEndDetails 的 velocity 恒为 0，测不出「靠速度翻期」这条路。
    // 手动合成三次带时间戳的移动：位移 30px（不到 48）+ 24ms ≈ 1250px/s。
    final TestGesture g = await tester.startGesture(
      tester.getCenter(find.byType(SwipeFlip)),
    );
    await g.moveBy(const Offset(-15, 0), timeStamp: const Duration(milliseconds: 8));
    await g.moveBy(const Offset(-15, 0), timeStamp: const Duration(milliseconds: 16));
    await g.up(timeStamp: const Duration(milliseconds: 24));
    await tester.pumpAndSettle();

    expect(next, 1, reason: '位移不到 48，但速度过了 260px/s 的线');
  });

  testWidgets('⑥ 双击 → 回今天', (WidgetTester tester) async {
    await UiHarness().pump(tester, swipe());

    final Offset center = tester.getCenter(find.byType(SwipeFlip));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    expect(today, 1);
  });

  testWidgets('⑥ 单击 → 弹选择器', (WidgetTester tester) async {
    await UiHarness().pump(tester, swipe());

    await tester.tap(find.byType(SwipeFlip));
    // 单击要等双击判定窗口过去才触发
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(pick, 1);
    expect(today, 0);
  });

  testWidgets('⑥ enabled=false → 不注册横向识别器（手势让给外层）', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(tester, swipe(enabled: false));

    await tester.drag(find.byType(SwipeFlip), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(next, 0);
    expect(prev, 0);
    expect(
      find.byType(GestureDetector),
      findsNothing,
      reason: '禁用时连 GestureDetector 都不套，外层 PageView 才能拿到手势',
    );
  });

  test('⑪ SwipeFlip.callSites == 源码里真实的调用点数（不许填假数字）', () {
    // 数法子：扫 lib/ 下所有非声明文件里 `SwipeFlip(` 的出现次数。
    // 这是**唯一**能防住「原版 PeriodChip 零调用活到 1.4.5」的门禁 ——
    // 常量填假数字等于把门禁自己废掉，所以这里不是断言 `>= 1`。
    int real = 0;
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll('\\', '/');
      if (path.endsWith('ui/widgets/swipe_flip.dart')) continue;
      real += RegExp(r'\bSwipeFlip\(').allMatches(e.readAsStringSync()).length;
    }
    expect(
      SwipeFlip.callSites,
      real,
      reason: '加了/删了调用点就要同步 callSites（当前源码 $real 处）',
    );
    expect(SwipeFlip.callSites, greaterThanOrEqualTo(3));
  });
}
