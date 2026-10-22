// 触感反馈开关的自检。
//
// 两层都要验，缺一层就等于没验：
// 1) **开关本身**能不能记住（落库 + 重启后还在）—— 纯状态，测数据层；
// 2) **关掉之后真的不震** —— 光有一个 bool 不算数，得看平台通道上还有没有
//    `HapticFeedback.vibrate` 调用。所以这里把通道 mock 掉数调用次数。
//
// 第 2 条里的「打开后必须有调用」是必须的：只断言「关掉 → 0 次」的话，
// mock 写错了（永远捕获不到）也会让用例通过，等于自证清白。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/design/haptics.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_haptics.db';

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
    Haptics.enabled = true;
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  test('默认是开的；关掉后落库，重新启动仍然是关的', () async {
    await Store.i.boot();
    expect(Store.i.hapticsEnabled, isTrue, reason: '老库没有这个键时应保持默认开');
    expect(Haptics.enabled, isTrue);

    await Store.i.setHapticsEnabled(false);
    expect(Store.i.hapticsEnabled, isFalse);
    expect(Haptics.enabled, isFalse, reason: '界面开关与执行点必须同步');
    expect(await Repo.getSetting('ui.haptics'), '0');

    // 模拟下次冷启动：boot 会重新读 setting
    await Store.i.boot();
    expect(Store.i.hapticsEnabled, isFalse);
    expect(Haptics.enabled, isFalse);

    // 再打开也要能记住
    await Store.i.setHapticsEnabled(true);
    await Store.i.boot();
    expect(Haptics.enabled, isTrue);
  });

  testWidgets('关掉之后平台通道上不再有震动调用；打开后有', (tester) async {
    final calls = <String>[];

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    // 关掉：四个入口一个都不该发
    Haptics.enabled = false;
    Haptics.success();
    Haptics.warn();
    Haptics.tap();
    Haptics.key();
    await tester.pump();
    expect(calls, isEmpty, reason: '关掉开关后仍然震了：$calls');

    // 打开：必须真的有调用，否则上面那条 isEmpty 是假的
    Haptics.enabled = true;
    Haptics.success();
    await tester.pump();
    expect(
      calls,
      isNotEmpty,
      reason: '打开后没有任何震动调用，说明通道 mock 没生效、这条用例等于没测',
    );
    expect(calls.first, contains('mediumImpact'));
  });
}
