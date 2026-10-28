// 冷启动**没有品牌启动页**的契约。
//
// 2026-10-28 删除了启动页（_SplashScreen + kSplashMinVisible）。删掉之后有两件事
// 必须被测试钉住，否则很容易在后续重构里悄悄回来：
//
//   1. 等待期不能是「什么都不画」。`SizedBox.shrink()` 会让窗口底色（黑）露出来，
//      看起来像崩溃；必须是应用底色。
//   2. 不能再有定时停留。只要有人重新写 `Future.delayed`，本文件的第二个断言
//      就会红 —— 因为它是在**完全不推进假时钟**的情况下等主界面。
//
// 两件事写成同一条用例：它们都要求「Store 还没 ready」这个初始状态，
// 拆成两条就得依赖执行顺序（第一条跑完 Store 就 ready 了，第二条再也看不到
// 等待画面）。一条跑完整个时间线更稳，也更快。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/design/icons.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/pages/home_shell.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_boot_no_splash.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  testWidgets('冷启动：等待期只铺底色，boot 完成即进主界面（无最短停留）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const HeitaApp());
    await tester.pump();

    // —— 第一拍：库里还没开完，这一帧是等待画面 ——
    expect(find.byType(HomeShell), findsNothing, reason: '库没开完不该出现主界面');
    expect(
      find.byType(BrandMark),
      findsNothing,
      reason: '启动页已删除。这里出现 BrandMark 说明有人把开屏又加回来了',
    );
    expect(find.text('启动失败'), findsNothing, reason: '正常启动不该走错误分支');

    // 必须铺了应用底色：否则首帧露的是窗口默认底色（黑），看起来像崩溃
    final hasAppBg = find
        .byWidgetPredicate((w) => w is ColoredBox && w.color == C.bg)
        .evaluate()
        .isNotEmpty;
    expect(
      hasAppBg,
      isTrue,
      reason: '等待期没有铺 C.bg 底色。返回空 widget 会让窗口底色（黑）露出来',
    );

    // —— 第二拍：**假时钟一步都不走**，只让真实事件循环回包 ——
    //
    // 这是本用例的关键手法：任何 `Future.delayed` 都不会到期。于是"能进主界面"
    // 就等价于"启动路上没有定时停留"。若有人把 kSplashMinVisible 那类定时器
    // 加回来，这里会一直停在等待画面，最后 findsOneWidget 失败。
    var entered = false;
    for (var i = 0; i < 400; i++) {
      if (find.byType(HomeShell).evaluate().isNotEmpty) {
        entered = true;
        break;
      }
      await tester.pump(Duration.zero);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }

    expect(
      entered,
      isTrue,
      reason: '假时钟一步没走就进不了主界面，说明启动路上还有定时停留'
          '（原来那个 560ms 的 kSplashMinVisible）。启动页删掉后不该再等',
    );
    // boot 结束后仍不该出现品牌元素
    expect(find.byType(BrandMark), findsNothing);
  });
}
