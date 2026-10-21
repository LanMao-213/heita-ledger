import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/app.dart';
import 'package:heita_ledger/core/failure.dart';
import 'package:heita_ledger/stores/shell_store.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/ui/boot/boot_error.dart';
import 'package:heita_ledger/ui/boot/boot_gate.dart';
import 'package:heita_ledger/ui/boot/splash.dart';
import 'package:heita_ledger/ui/pages/detail/detail_page.dart';
import 'package:heita_ledger/ui/pages/mine/mine_page.dart';
import 'package:heita_ledger/ui/pages/plan/plan_page.dart';
import 'package:heita_ledger/ui/pages/record/record_keypad.dart';
import 'package:heita_ledger/ui/pages/stats/stats_page.dart';
import 'package:heita_ledger/ui/shell/home_shell.dart';

/// 应用壳：启动闸三态、5 槽底栏、四页横滑与保活、配色切换。
///
/// 启动序列用假 runner 替掉（不碰 SQLite），这样这组用例只测「壳」。
Future<void> _fakeBoot(ShellStore shell) async => shell.markReady();

Future<ShellStore> _pumpApp(
  WidgetTester tester, {
  BootRunner? runner,
  ShellStore? store,
}) async {
  final ShellStore shell = store ?? ShellStore();
  await tester.pumpWidget(
    HeitaApp(shell: shell, bootRunner: runner ?? _fakeBoot),
  );
  await tester.pumpAndSettle();
  return shell;
}

/// 取某页里 `Scrollable` 的滚动位置 —— 保活断言的观测点。
double _offsetOf(WidgetTester tester, Finder page) {
  final Finder scrollable = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .first;
  return tester.state<ScrollableState>(scrollable).position.pixels;
}

void main() {
  group('启动闸', () {
    testWidgets('首帧只画开屏，跑完序列才进壳', (WidgetTester tester) async {
      final ShellStore shell = ShellStore();
      await tester.pumpWidget(HeitaApp(shell: shell, bootRunner: _fakeBoot));

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('ready 为真时跳过重复 boot（热重载安全）', (WidgetTester tester) async {
      final ShellStore shell = ShellStore()..markReady();
      int calls = 0;
      await tester.pumpWidget(
        HeitaApp(
          shell: shell,
          bootRunner: (ShellStore _) async => calls++,
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('启动失败 → 失败页给三个出口：重试 / 导出数据库文件 / 显示数据库路径', (
      WidgetTester tester,
    ) async {
      final ShellStore shell = ShellStore();
      await tester.pumpWidget(
        HeitaApp(
          shell: shell,
          bootRunner: (ShellStore _) async => throw const DbFailure('磁盘满了'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BootErrorView), findsOneWidget);
      expect(find.text('账本没能打开'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('boot-retry')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('boot-export-db')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('boot-show-path')), findsOneWidget);
      // 用户看的是中文文案，不是异常原文
      expect(find.textContaining('SqliteException'), findsNothing);
      expect(shell.ready, isFalse);
      expect(shell.bootError, isA<DbFailure>());
    });

    testWidgets('失败页「显示数据库路径」能展开路径区', (WidgetTester tester) async {
      await tester.pumpWidget(
        HeitaApp(
          shell: ShellStore(),
          bootRunner: (ShellStore _) async => throw const DbFailure('磁盘满了'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('（数据库还没有打开，路径未知）'), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('boot-show-path')));
      await tester.pumpAndSettle();
      expect(find.text('（数据库还没有打开，路径未知）'), findsOneWidget);
    });

    testWidgets('点「重试」重跑序列，第二次成功后进壳', (WidgetTester tester) async {
      int calls = 0;
      final ShellStore shell = ShellStore();
      await tester.pumpWidget(
        HeitaApp(
          shell: shell,
          bootRunner: (ShellStore s) async {
            calls++;
            if (calls == 1) throw const DbFailure('临时故障');
            s.markReady();
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BootErrorView), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('boot-retry')));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(shell.ready, isTrue);
    });
  });

  group('五槽底栏与四页横滑', () {
    testWidgets('四个 tab + 中央「记一笔」浮钮都在，默认在明细页', (WidgetTester tester) async {
      final ShellStore shell = await _pumpApp(tester);

      expect(find.byType(DetailPage), findsOneWidget);
      for (final String label in <String>['明细', '图表', '计划', '我的']) {
        expect(
          find.byKey(ValueKey<String>('nav-$label')),
          findsOneWidget,
          reason: '底栏缺「$label」',
        );
      }
      expect(find.byKey(const ValueKey<String>('fab-record')), findsOneWidget);
      expect(shell.tabIndex, ShellStore.tabDetail);
    });

    testWidgets('点底栏 → 页面切过去且 Store 同步', (WidgetTester tester) async {
      final ShellStore shell = await _pumpApp(tester);

      await tester.tap(find.byKey(const ValueKey<String>('nav-图表')));
      await tester.pumpAndSettle();

      expect(shell.tabIndex, ShellStore.tabStats);
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page!.round(),
        ShellStore.tabStats,
      );
    });

    testWidgets('横滑页面 → 底栏高亮同步（双向）', (WidgetTester tester) async {
      final ShellStore shell = await _pumpApp(tester);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(shell.tabIndex, ShellStore.tabStats);
      expect(find.byType(StatsPage), findsOneWidget);
    });

    testWidgets('点当前 tab 不重放翻页动画、不发通知', (WidgetTester tester) async {
      final ShellStore shell = await _pumpApp(tester);
      int notified = 0;
      shell.addListener(() => notified++);

      await tester.tap(find.byKey(const ValueKey<String>('nav-明细')));
      // 只 pump 一帧：如果真起了 260ms 的动画，这一帧就会看到位置在动
      await tester.pump(const Duration(milliseconds: 16));

      expect(notified, 0);
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page!.round(),
        ShellStore.tabDetail,
      );
    });

    testWidgets('四页都保活：切走再回来状态还是同一个', (WidgetTester tester) async {
      await _pumpApp(tester);

      // 空库时明细页没有内容可滚（滚动位置的守恒由下一条「计划」用例盯着），
      // 这里守的是更根本的一条：切走再回来 State 没被重建。
      final State<StatefulWidget> before = tester.state(find.byType(DetailPage));

      await tester.tap(find.byKey(const ValueKey<String>('nav-我的')));
      await tester.pumpAndSettle();
      expect(find.byType(MinePage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('nav-明细')));
      await tester.pumpAndSettle();

      expect(
        identical(tester.state(find.byType(DetailPage)), before),
        isTrue,
        reason: 'State 换人 = 保活失效，列表滚动位置会跟着丢',
      );
      expect(find.byType(DetailPage), findsOneWidget);
    });

    testWidgets('四页各自独立滚动位置，互不串台', (WidgetTester tester) async {
      await _pumpApp(tester);

      await tester.tap(find.byKey(const ValueKey<String>('nav-计划')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PlanPage), const Offset(0, -180));
      await tester.pumpAndSettle();
      final double planOffset = _offsetOf(tester, find.byType(PlanPage));
      expect(planOffset, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey<String>('nav-明细')));
      await tester.pumpAndSettle();

      // 明细页没被计划页的滚动带偏
      expect(_offsetOf(tester, find.byType(DetailPage)), 0);
      // 回计划页，它自己的位置还在
      await tester.tap(find.byKey(const ValueKey<String>('nav-计划')));
      await tester.pumpAndSettle();
      expect(_offsetOf(tester, find.byType(PlanPage)), closeTo(planOffset, 0.5));
    });
  });

  group('配色运行时切换', () {
    testWidgets('在「我的」页切到 aurora → 主题与页面底色立刻变，无需重启', (
      WidgetTester tester,
    ) async {
      final ShellStore shell = await _pumpApp(tester);
      expect(shell.palette.id, 'ink');

      await tester.tap(find.byKey(const ValueKey<String>('nav-我的')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('palette-aurora')));
      await tester.pumpAndSettle();

      expect(shell.palette.id, 'aurora');
      final MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme!.extension<AppPalette>(), same(paletteAurora()));
      // 页面底色真的换了（不是只改了 ThemeData）
      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, paletteAurora().bg);
      expect(tester.takeException(), isNull);
    });

    testWidgets('切回 ink 也立刻生效（可来回切）', (WidgetTester tester) async {
      final ShellStore shell = await _pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey<String>('nav-我的')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('palette-aurora')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('palette-ink')));
      await tester.pumpAndSettle();

      expect(shell.palette.id, 'ink');
      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, paletteInk().bg);
    });

    testWidgets('配色落库：切换会把 id 交给持久化回调', (WidgetTester tester) async {
      final List<String> persisted = <String>[];
      final ShellStore shell = ShellStore(
        persistPalette: (String id) async => persisted.add(id),
      );
      await _pumpApp(tester, store: shell);

      await tester.tap(find.byKey(const ValueKey<String>('nav-我的')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('palette-aurora')));
      await tester.pumpAndSettle();

      expect(persisted, <String>['aurora']);
    });

    testWidgets('浮钮 → 真的打开记一笔面板（阶段 2 已接上）', (WidgetTester tester) async {
      await _pumpApp(tester);

      await tester.tap(find.byKey(const ValueKey<String>('fab-record')));
      await tester.pumpAndSettle();

      expect(find.text('记一笔'), findsOneWidget);
      expect(find.byType(RecordKeypad), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey<String>('record-close')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordKeypad), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget, reason: '关掉面板不会把关壳带走');
    });
  });
}
