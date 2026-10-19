// 「分类升级为两级」一次性提示的自检。
//
// 分类改名（交通→出行、学习→成长）并多出一层子分类之后，老用户打开会以为
// 数据被改乱了。提示只该出现一次：天天弹等于骚扰，一次不弹等于没说。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_upgrade_notice.db';

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

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  test('从老库升上来：提示一次，落标记，第二次不再提示', () async {
    // 模拟「打开的是 v5 老库」：onUpgrade 里会把这一位置真
    Db.upgradedToTwoLevel = true;

    await Store.i.boot();
    expect(Store.i.catsUpgradeJustDone, isTrue, reason: '升级后首次启动要提示');
    expect(
      await Repo.getSetting('ui.cats_two_level_notice'),
      '1',
      reason: '提示过的标记要落库，否则每次启动都会再弹',
    );

    // 第二次启动：标记已在，且本次没有真的迁移
    Store.i.catsUpgradeJustDone = false;
    Db.upgradedToTwoLevel = false;
    await Store.i.boot();
    expect(Store.i.catsUpgradeJustDone, isFalse);
  });

  test('全新安装：不提示', () async {
    Db.upgradedToTwoLevel = false;
    await Store.i.boot();
    expect(Store.i.catsUpgradeJustDone, isFalse);
  });
}
