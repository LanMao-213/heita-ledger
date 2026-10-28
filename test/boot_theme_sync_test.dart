// 冷启动时 ThemeData 必须与色板同源。
//
// 起因（用户截图）：页面是「露露缇雅·泽金」（天青底、绯紫字），但点开
// 「账户管理」这层弹层却是**深紫黑底** —— 那是出厂「黑塔·永夜」的卡面色。
//
// 根因：`MaterialApp` 在 `_BootGate` 之前就建好了，用的是出厂色板；主题是
// boot 过程中才从库里读出来的，而 `loadSilently` 刻意不通知 —— 于是
//   页面：`C.xxx` 是 getter，永远读当前色板 → 泽金 ✓
//   ThemeData：弹层底/对话框/AppBar 走它 → 永远停在永夜 ✗
//
// 这个测试**不能**在 `pumpWidget` 之前 boot：那样主题在建 MaterialApp 时
// 就已经载入，正好绕过整条出问题的路径（这也是为什么之前所有测试都是绿的）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/pages/home_shell.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_boot_theme_sync.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  testWidgets('库里存的是泽金 → 冷启动后 ThemeData 也必须是泽金', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 上一轮用户选了泽金，库里记着。这里只写 setting，**不 boot**
    await tester.runAsync(() async {
      await Db.open();
      await Repo.setSetting('ui.theme', HeitaThemeId.zeikin.name);
    });

    await tester.pumpWidget(const HeitaApp());
    // boot 在 `_BootGate.initState` 里跑真实数据库 I/O，假时钟下 pumpAndSettle
    // 等不到它 —— 真实时间与 pump 交替，直到首屏出来。
    //
    // 注意每次 pump 必须**推进假时钟**：启动页有最短停留时长
    // （`kSplashMinVisible`，一个 `Future.delayed`），只 pump 零时长的话
    // 定时器永远不响，循环跑满 120 次也到不了主界面。
    for (var i = 0; i < 120 && find.byType(HomeShell).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final gold = paletteOf(HeitaThemeId.zeikin);
    final theme = Theme.of(tester.element(find.byType(HomeShell).first));

    expect(
      ThemeCtrl.i.id,
      HeitaThemeId.zeikin,
      reason: '色板没载入成功，后面的断言就没有意义了',
    );
    expect(
      theme.brightness,
      Brightness.light,
      reason: '整屏是亮色皮肤，ThemeData 却还是深色 —— 弹层会变成深底配深字',
    );
    expect(
      theme.bottomSheetTheme.backgroundColor,
      gold.cardBg,
      reason: '弹层底没有跟着皮肤走（用户看到的就是这一条）',
    );
    expect(theme.dialogTheme.backgroundColor, gold.cardBg);
    expect(theme.scaffoldBackgroundColor, gold.bg);

    // 真开一次弹层，量它实际画出来的底色
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('账户管理'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('账户管理'));
    await tester.pumpAndSettle();

    final sheetColors = tester
        .widgetList<Material>(find.byType(Material))
        .map((m) => m.color)
        .toList();
    expect(
      sheetColors,
      contains(gold.cardBg),
      reason: '账户管理弹层没有用当前皮肤的卡面色',
    );
  });

  // 上面那条守「冷启动会把主题通知出去」；这条守「通知到了之后，ThemeData
  // 里每一个从色板派生的面/字确实取自同一块色板」。两条合起来才闭环：
  // 只守前者，改坏 buildAppTheme 也测不出来。
  test('每套皮肤：ThemeData 的面与字必须与色板同源', () {
    final saved = ThemeCtrl.i.id;
    addTearDown(() => ThemeCtrl.i.loadSilently(saved));

    for (final p in kPalettes) {
      ThemeCtrl.i.loadSilently(p.id);
      final t = buildAppTheme();
      final why = '（${p.name}）';
      expect(t.brightness, p.dark ? Brightness.dark : Brightness.light,
          reason: '明暗方向反了$why');
      expect(t.scaffoldBackgroundColor, p.bg, reason: '页面底色$why');
      expect(t.appBarTheme.backgroundColor, p.bg, reason: '页头底色$why');
      expect(t.bottomSheetTheme.backgroundColor, p.cardBg,
          reason: '弹层底色$why'); // ← 用户截图里错的就是这一条
      expect(t.dialogTheme.backgroundColor, p.cardBg, reason: '对话框底色$why');
      expect(t.cardTheme.color, p.cardBg, reason: '卡片底色$why');
      expect(t.dividerColor, p.line, reason: '分隔线$why');
    }
  });
}
