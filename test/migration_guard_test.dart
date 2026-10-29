// v10 迁移的「缺表守卫」的**指名**用例。
//
// 为什么值得单独一条：`Db._addGoalFlowTable` 里那句「`saving_goal` 不存在就
// 跳过加列」原来只被 `period_test.dart` 的 v3 夹具**顺带**覆盖 —— 那套夹具
// 恰好没建 `saving_goal`，于是守卫一被删掉，红的是「归属期」那三条用例。
// 看名字完全联想不到迁移，很容易被当成不相关的失败忽略过去（这一轮就是这么
// 漏的：全量测试报 `+598 -11`，红的是 period / integrity / budget_period）。
//
// 这里按**指名**的方式构造那个状态：建到 v10 → 删掉 goal_flow 与 saving_goal
// → 把 user_version 退回 9 → 重新打开。守卫在，这一次打开就不会抛异常。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_migration_guard.db';

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

  test('v9 库没有 saving_goal：升到 v10 不抛异常，goal_flow 照建', () async {
    // 1. 建到当前版本（v10），拿到一份完整 schema
    final db = await Db.open();
    // 2. 造出「极简老库」：这两张表都不在（真实场景是只含若干张表的库，
    //    测试里是直接 drop —— 效果一样：PRAGMA table_info 会返回空）
    await db.execute('DROP TABLE goal_flow');
    await db.execute('DROP TABLE saving_goal');
    await db.execute('PRAGMA user_version = 9');
    await Db.close();

    // 3. 重新打开：onUpgrade(9 → 10) 会调 _addGoalFlowTable。
    //    没有守卫时这里抛 `no such table: saving_goal`，整台机器就卡在启动页。
    final again = await Db.open();

    final tables = await again.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('goal_flow', 'saving_goal') ORDER BY name",
    );
    expect(
      tables.map((r) => r['name']).toList(),
      ['goal_flow'],
      reason: 'goal_flow 与 saving_goal 无关，缺表也要建出来；saving_goal 不该被凭空造出',
    );
    expect(
      await again.getVersion(),
      Db.schemaVersion,
      reason: '版本要升到位，否则每次启动都会重跑一遍迁移',
    );
  });
}
