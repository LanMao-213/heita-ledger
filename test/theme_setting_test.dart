// 主题开关的自检（我的 → 偏好 → 主题）。
//
// 要验的是三件事，缺一件就等于没验：
// 1) **默认**：老库没有 `ui.theme` 这个键时，默认是黑塔·永夜（深色），
//    而不是「顺手回落到列表第一套」；
// 2) **记住**：换完落库，模拟冷启动后还在 —— 否则用户每次打开都要重选；
// 3) **真的换到设计层**：`Store.themeId` 只是给界面读的副本，
//    真正决定颜色的是 `ThemeCtrl`。只改副本不改单例 = 界面不换色。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/theme_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_theme.db';

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
    ThemeCtrl.i.loadSilently(kDefaultTheme);
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  test('老库没有 ui.theme → 出厂默认圣地 · 审判白，且落到设计层', () async {
    await Store.i.boot();
    expect(Store.i.themeId, kDefaultTheme);
    expect(Store.i.themeId, HeitaThemeId.holy);
    expect(ThemeCtrl.i.id, HeitaThemeId.holy,
        reason: '设计层没跟上，界面就还是原来那套色');
    expect(ThemeCtrl.i.dark, isFalse);
    expect(C.bg, paletteOf(HeitaThemeId.holy).bg);
  });

  test('换肤后落库，冷启动仍然是换过的那一套', () async {
    await Store.i.boot();
    await Store.i.setTheme(HeitaThemeId.zeikin);

    expect(await Repo.getSetting('ui.theme'), 'zeikin');
    expect(ThemeCtrl.i.id, HeitaThemeId.zeikin, reason: '换肤必须同时改设计层');
    expect(C.bg, paletteOf(HeitaThemeId.zeikin).bg);

    // 模拟下次冷启动
    await Store.i.boot();
    expect(Store.i.themeId, HeitaThemeId.zeikin);
    expect(ThemeCtrl.i.id, HeitaThemeId.zeikin);
  });

  test('存了一个认不出的值 → 回落出厂默认，不白屏', () async {
    await Store.i.boot();
    await Repo.setSetting('ui.theme', 'no_such_theme');
    await Store.i.boot();
    expect(Store.i.themeId, kDefaultTheme);
    expect(ThemeCtrl.i.palette, paletteOf(kDefaultTheme));
  });

  test('六套都能换过去，且换过去后 C / kChart 都跟着变', () async {
    await Store.i.boot();
    final seen = <HeitaThemeId>{};
    for (final t in HeitaThemeId.values) {
      await Store.i.setTheme(t);
      expect(ThemeCtrl.i.id, t);
      expect(C.bg, paletteOf(t).bg);
      expect(C.ink, paletteOf(t).ink);
      expect(kChart, paletteOf(t).chart);
      seen.add(ThemeCtrl.i.id);
    }
    expect(seen.length, HeitaThemeId.values.length, reason: '有一套没换成功');
  });

  test('setTheme 只通知一次（换肤会重建整棵树，重复通知是白干）', () async {
    await Store.i.boot();
    var fired = 0;
    void onFire() => fired++;
    ThemeCtrl.i.addListener(onFire);
    addTearDown(() => ThemeCtrl.i.removeListener(onFire));

    await Store.i.setTheme(HeitaThemeId.cold);
    expect(fired, 1);
    // 重复设置同一个主题不该再触发重建
    await Store.i.setTheme(HeitaThemeId.cold);
    expect(fired, 1);
  });

  testWidgets('主题弹层列出全部六套，点一套把它返回出来', (tester) async {
    // 弹层自带主题色，所以外层必须给一个 MaterialApp（否则拿不到 Theme）
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: SizedBox()),
    ));

    // 在弹层推开之前抓 context（推开后会有两个 Scaffold，find 就要加 .first）
    final ctx = tester.element(find.byType(Scaffold));
    final picked = showThemeSheet(ctx, current: HeitaThemeId.cold);
    await tester.pumpAndSettle();

    // 六套的名字都在；当前那一套有勾（勾是图标，数的是行数不是勾）
    for (final p in kPalettes) {
      expect(find.text(p.name), findsOneWidget, reason: '${p.name} 没有出现在弹层里');
      expect(find.text(p.subtitle), findsOneWidget);
    }
    expect(find.byType(InkWell), findsNWidgets(kPalettes.length));

    await tester.tap(find.text(paletteOf(HeitaThemeId.tower).name));
    await tester.pumpAndSettle();
    expect(await picked, HeitaThemeId.tower);
  });
}
