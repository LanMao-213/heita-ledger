import 'package:sqflite/sqflite.dart';

import '../../core/failure.dart';
import 'schema.dart';
import 'seeds.dart';

/// 当前 schema 版本。
///
/// 备份文件里会记下它，恢复时用它判断兼容性（`formatVersion` 管的是文件格式，
/// 这里管的是表结构，两者独立演进）。
///
/// 版本史（新项目从 v1 起，不再继承原版 1→7 的历史）：
/// - v1 = 全新 10 表 schema：`txn.period_start NOT NULL`、三条部分唯一索引、
///   删掉 4 个死列、`account` 拆成 `opening_cents` + `balance_cents`。
const int kSchemaVersion = 1;

/// 建表（不含播种）。`onCreate` 与测试共用同一份 DDL。
Future<void> createSchema(Database db) async {
  for (final String statement in kSchemaStatements) {
    await db.execute(statement);
  }
}

/// `onCreate`：建表 + 播种。
///
/// 播种放在**同一个回调里**而不是 `open()` 之后：`open()` 返回前库里的数据就
/// 应该是自洽的，否则任何「打开后立刻查分类」的代码路径都要自己判断要不要等播种。
Future<void> onCreate(Database db, int version) async {
  await createSchema(db);
  await seedFresh(db);
}

/// `onUpgrade` 骨架。
///
/// 新项目从 v1 起，暂时没有需要迁移的版本。这个函数存在的意义有两个：
/// ① **冻结调用形态** —— 加 v2 时只在末尾追加一个 `if (oldVersion < 2) {...}` 块，
///    永远不会出现「两处迁移顺序打架」；
/// ② 迁移链必须**单事务**执行（`sqflite` 的 `onUpgrade` 本身就在事务里），
///    中途抛异常整体回滚，不会留下半升级的库。
///
/// 铁律：**不允许**在这里改 `account.opening_cents` 的值做「顺手修数据」——
/// 那是 `integrity_service` 的活，且必须用户点。
Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion > newVersion) {
    // 正常不会走到这里（`onDowngrade` 会先抛），留作双保险。
    throw DbDowngradeException(oldVersion, newVersion);
  }
}

/// 补 `txn.period_start` 为空的行，返回补了几行。
///
/// v1 里 `period_start` 是 `NOT NULL`，所以正常库恒为 0 行。这个函数在启动序列
/// 第 3 步（架构设计 §4-⑦）被调用，作用是把「旧备份导入留下的空值」挡在
/// 视图之外；真正的现算要 `Period`（T01-3），本函数只负责**统计**，
/// 数量非 0 时由调用方决定怎么办（不静默改写数据）。
Future<int> backfillMissingPeriods(DatabaseExecutor db) async {
  final List<Map<String, Object?>> rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM ${Tables.txn} '
    "WHERE period_start IS NULL OR trim(period_start) = ''",
  );
  if (rows.isEmpty) return 0;
  return Sqflite.firstIntValue(rows) ?? 0;
}
