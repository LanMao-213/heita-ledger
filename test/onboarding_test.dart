// 首次使用引导的自检。
//
// 三件事必须分开验，因为它们坏掉的样子完全不同：
// 1) **什么时候自动出现** —— 判据是「库是不是这次新建的」+「有没有看过」。
//    只看后者，用了半年的老用户升级上来会被塞一份引导；只看前者，每次重建库都弹。
// 2) **走完之后不再出现** —— 标记要落库，冷启动之后仍然生效。
// 3) **流程本身可用** —— 下一步能翻、跳过能退、走完能退，且退出时标记已写。
//
// 第 1 条里「同一个库第二次启动不弹」这个用例是整套判据的核心：它绕开了
// 「清标记」这种不现实的模拟（用户不会去删这个键），直接用「库还是上次那个」
// 来代表老用户。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/onboarding_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_onboarding.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 有界 settle。
///
/// `pumpAndSettle()` 的默认上限是 **10 分钟**，一旦某段动画停不下来，整个测试
/// 文件会一直卡到进程被杀，报出来只有一句「did not complete」—— 既不知道卡在
/// 哪一步，也不知道为什么。3 秒足够走完这里任何一段路由或翻页动画，
/// 超了立刻失败，失败点就是出问题的那个动作。
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 50),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 3),
);

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
    // 自动弹出在所有测试里是关的（见 test/flutter_test_config.dart）；
    // 这里恢复默认值，好让「判据」本身被验到
    Onboarding.autoShow = true;
  });

  tearDown(() async {
    Onboarding.autoShow = false;
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  group('自动弹出的判据', () {
    test('全新安装（这次新建了库）→ 待引导', () async {
      await Store.i.boot();
      expect(Db.createdNow, isTrue, reason: '建库时没打标记，判据就永远为假');
      expect(Store.i.onboardingPending, isTrue);
      expect(await Repo.getSetting('onboarding.done'), isNull);
    });

    test('同一个库再次启动 → 不再待引导（老用户升级不会被塞引导）', () async {
      await Store.i.boot();
      expect(Store.i.onboardingPending, isTrue);

      await Db.close();
      await Store.i.boot();
      expect(Db.createdNow, isFalse);
      expect(
        Store.i.onboardingPending,
        isFalse,
        reason: '库是上一次建的，说明不是全新安装 —— 此时即使没有 done 标记也不该弹',
      );
    });

    test('走完引导 → 落库，冷启动后仍然不弹', () async {
      await Store.i.boot();
      await Store.i.finishOnboarding();
      expect(Store.i.onboardingPending, isFalse);
      expect(await Repo.getSetting('onboarding.done'), '1');

      await Db.close();
      await Store.i.boot();
      expect(Store.i.onboardingPending, isFalse);
    });

    test('finishOnboarding 幂等：没待弹出时是空操作', () async {
      await Store.i.boot();
      await Store.i.finishOnboarding();
      // 第二次调用不该再写库，也不该抛
      await Store.i.finishOnboarding();
      expect(await Repo.getSetting('onboarding.done'), '1');
    });
  });

  group('流程本身', () {
    /// 一个只有按钮的宿主：引导是 push 上来的整页，不需要主界面陪跑
    Future<void> pumpHost(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await Store.i.boot();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showOnboarding(ctx),
                  child: const Text('打开引导'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开引导'));
      await _settle(tester);
    }

    /// 让「点完之后发生的那次落库」真的写完。
    ///
    /// 假时钟推不动 sqlite：`finishOnboarding` 读写的都是真磁盘，必须让出
    /// 真实事件循环（`runAsync`）它才会回包。这一步不能省 —— 省了就会看到
    /// 「界面退了、标记没写」，而那不是 bug，是测试太快。
    Future<void> settleWrite(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await _settle(tester);
    }

    /// 读落库的标记。同样必须走 `runAsync`。
    Future<String?> doneFlag(WidgetTester tester) async =>
        await tester.runAsync<String?>(() => Repo.getSetting('onboarding.done'));

    testWidgets('下一步能翻到最后一步，「开始记账」退出并落库', (tester) async {
      await pumpHost(tester);

      expect(find.text('欢迎使用黑塔消费日记'), findsOneWidget);
      expect(find.text('开始记账'), findsNothing, reason: '第一页不该直接出现完成按钮');

      // 五步：点四次「下一步」
      for (var i = 0; i < 4; i++) {
        expect(find.text('下一步'), findsOneWidget, reason: '第 ${i + 1} 步没有下一步');
        await tester.tap(find.text('下一步'));
        await _settle(tester);
      }
      expect(find.text('数据在你手里'), findsOneWidget, reason: '没翻到最后一页');
      expect(find.text('下一步'), findsNothing);

      await tester.tap(find.text('开始记账'));
      await settleWrite(tester);

      expect(find.byType(OnboardingPage), findsNothing, reason: '走完没有退出');
      expect(Store.i.onboardingPending, isFalse);
      expect(
        await doneFlag(tester),
        '1',
        reason: '标记没落库，下次启动还会弹一遍',
      );
    });

    testWidgets('跳过：任何一步都能退，且同样算「看过」', (tester) async {
      await pumpHost(tester);
      await tester.tap(find.text('下一步'));
      await _settle(tester);

      await tester.tap(find.text('跳过'));
      await settleWrite(tester);

      expect(find.byType(OnboardingPage), findsNothing);
      expect(await doneFlag(tester), '1', reason: '跳过不等于「我没看过」');
    });

    testWidgets('「上一步」回到上一页；第一页没有上一步', (tester) async {
      await pumpHost(tester);
      expect(find.text('上一步'), findsNothing, reason: '第一页没有上一页可回');

      await tester.tap(find.text('下一步'));
      await _settle(tester);
      expect(find.text('记一笔：底部中间的 ＋'), findsOneWidget);

      await tester.tap(find.text('上一步'));
      await _settle(tester);
      expect(find.text('欢迎使用黑塔消费日记'), findsOneWidget);
    });

    testWidgets('系统返回键也算看过，不会下次再弹', (tester) async {
      await pumpHost(tester);
      await tester.binding.handlePopRoute();
      await settleWrite(tester);

      expect(find.byType(OnboardingPage), findsNothing);
      expect(await doneFlag(tester), '1');
    });
  });
}
