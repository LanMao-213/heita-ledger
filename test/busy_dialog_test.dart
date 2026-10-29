// 阻塞式进度弹窗的自检。
//
// 它守的不是「好看」，是三条**会让用户做错事**的性质：
//
//   1. 任务跑着的时候弹窗必须在（否则界面一动不动，用户会再点一次 / 以为崩了）；
//   2. 任务结束（**包括失败**）弹窗必须消失（留着等于把可恢复的错误变成界面卡死）；
//   3. 返回键 / 点击遮罩都**不许**关掉它（关掉了任务还在跑，用户以为取消了）。
//
// 时间相关的断言全靠 `Completer` 卡住 task，不依赖真实耗时 —— 慢任务的测试
// 一旦靠 sleep，就会在 CI 上变成 flaky 的样板。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/widgets/busy_dialog.dart';

/// 一个能拿到 BuildContext 的最小宿主。
Future<BuildContext> _host(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const Scaffold(body: Center(child: Text('宿主页面')));
        },
      ),
    ),
  );
  return ctx;
}

void main() {
  testWidgets('任务未完成时弹窗在，文案与转圈都在', (tester) async {
    final ctx = await _host(tester);
    final gate = Completer<int>();

    final pending = runWithBusy<int>(
      ctx,
      message: '正在加密备份…（约几秒，请不要退出）',
      task: () => gate.future,
    );
    await tester.pump();

    expect(find.byType(BusyDialog), findsOneWidget);
    expect(find.text('正在加密备份…（约几秒，请不要退出）'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 任务还没完，future 不该完成
    var settled = false;
    unawaited(pending.then((_) => settled = true));
    await tester.pump();
    expect(settled, isFalse);

    gate.complete(42);
    expect(await pending, 42);
    await tester.pumpAndSettle();
    expect(find.byType(BusyDialog), findsNothing);
  });

  testWidgets('任务失败时弹窗也要消失，异常原样抛回调用方', (tester) async {
    final ctx = await _host(tester);
    final gate = Completer<void>();

    final pending = runWithBusy<void>(
      ctx,
      message: '正在恢复…',
      task: () => gate.future,
    );
    await tester.pump();
    expect(find.byType(BusyDialog), findsOneWidget);

    gate.completeError(StateError('写库失败'));
    await expectLater(pending, throwsStateError);
    await tester.pumpAndSettle();

    // 这一条是重点：失败时最容易被漏掉的清理就是「关掉那个转圈」
    expect(
      find.byType(BusyDialog),
      findsNothing,
      reason: '任务失败后弹窗还在 —— 用户看到的是一个永远转圈的界面，'
          '而实际错误已经被吞掉了',
    );
  });

  testWidgets('返回键关不掉弹窗（任务还在跑，不能让人以为取消了）', (tester) async {
    final ctx = await _host(tester);
    final gate = Completer<int>();

    final pending = runWithBusy<int>(
      ctx,
      message: '正在解密…',
      task: () => gate.future,
    );
    await tester.pump();
    expect(find.byType(BusyDialog), findsOneWidget);

    // 系统返回：PopScope(canPop: false) 应当吞掉这次 pop
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(
      find.byType(BusyDialog),
      findsOneWidget,
      reason: '返回键把进度弹窗关掉了 —— 任务还在跑，用户却失去了「它在跑」的信息',
    );
    // 宿主页面还在 widget 树里（弹窗是叠在上面的路由），所以要断的是
    // 「它没重新变成当前路由」—— 那才是「弹窗被弹掉了」的证据
    expect(
      ModalRoute.of(ctx)!.isCurrent,
      isFalse,
      reason: '返回键把进度弹窗弹掉了 —— 宿主页面重新成为当前路由',
    );

    gate.complete(1);
    await pending;
    await tester.pumpAndSettle();
    expect(find.byType(BusyDialog), findsNothing);
    expect(ModalRoute.of(ctx)!.isCurrent, isTrue);
  });

  testWidgets('点遮罩关不掉弹窗（barrierDismissible: false）', (tester) async {
    final ctx = await _host(tester);
    final gate = Completer<int>();

    final pending = runWithBusy<int>(
      ctx,
      message: '正在加密备份…',
      task: () => gate.future,
    );
    await tester.pump();
    expect(find.byType(BusyDialog), findsOneWidget);

    // 点左上角：那是遮罩层，不是弹窗本体
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(find.byType(BusyDialog), findsOneWidget);

    gate.complete(0);
    await pending;
    await tester.pumpAndSettle();
    expect(find.byType(BusyDialog), findsNothing);
  });

  testWidgets('弹窗永远没有「取消」按钮（取消是假的：任务停不下来）', (tester) async {
    final ctx = await _host(tester);
    final gate = Completer<int>();

    final pending = runWithBusy<int>(
      ctx,
      message: '正在恢复…',
      task: () => gate.future,
    );
    await tester.pump();

    expect(find.byType(TextButton), findsNothing);
    expect(find.text('取消'), findsNothing);

    gate.complete(0);
    await pending;
    await tester.pumpAndSettle();
  });
}
