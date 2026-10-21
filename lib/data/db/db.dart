import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/failure.dart';
import '../models/setting.dart';
import 'migrations.dart';
import 'schema.dart';
import 'seeds.dart';

/// 本地 SQLite 存储的唯一入口。
///
/// ★ 单机红线：**不发任何 HTTP 请求、不接任何统计/崩溃上报/广告 SDK**。
///   数据只进本地 SQLite，不出去（`tools/check_no_network.sh` 强制）。
///
/// ★ 金额统一 `INTEGER` 存「分」；日期统一 `TEXT` `YYYY-MM-DD`。
///
/// 库文件位置：`getDatabasesPath()/heita_ledger.db`（应用私有目录，卸载即清空）。
/// 这个路径会显示在「启动失败页」和「数据安全页」上 —— 用户要能自己找到它。
class Db {
  Db._();

  static Database? _db;
  static String? _openPath;

  /// 库文件名。测试会改成别的名字或 `:memory:`。
  ///
  /// `flutter test` 会并行跑多个测试文件，共用一个文件名时两个进程抢同一个
  /// sqlite 文件（Windows 上直接删不掉）。所以测试必须能改这里。
  static String fileName = 'heita_ledger.db';

  /// 打开后的真实路径。未打开时是空串。
  static String get filePath => _openPath ?? '';

  static bool get isOpen => _db != null;

  /// 测试用故障注入：`wipeAllData` 在「删完、播种前」调用它，抛异常即验证回滚
  /// （不变量 I17）。生产代码永远不设置它。
  static Future<void> Function(DatabaseExecutor db)? wipeAllDataFaultForTest;

  /// 打开库（幂等）。第一次打开会建表 + 播种，之后直接返回同一实例。
  static Future<Database> open() async {
    final Database? existing = _db;
    if (existing != null) return existing;

    final String path = fileName == inMemoryDatabasePath
        ? fileName
        : p.join(await getDatabasesPath(), fileName);

    try {
      _db = await openDatabase(
        path,
        version: kSchemaVersion,
        onConfigure: (Database db) async {
          // 外键必须每次连接都开（SQLite 的默认值是 OFF，且是连接级设置）
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        onDowngrade: (Database db, int oldVersion, int newVersion) async {
          throw DbDowngradeException(oldVersion, newVersion);
        },
      );
    } on DbDowngradeException {
      rethrow;
    } catch (error) {
      throw DbFailure('open($path) 失败：$error');
    }
    _openPath = path;
    return _db!;
  }

  /// 关库。清空/恢复之后要 `close` + `open` 才能让连接看到新数据以外的状态
  /// （例如重建过的库文件、被外部删掉的文件）。
  static Future<void> close() async {
    final Database? current = _db;
    _db = null;
    _openPath = null;
    await current?.close();
  }

  /// 关库再打开。
  static Future<Database> reopen() async {
    await close();
    return open();
  }

  /// 单事务助手。**写操作一律走它**，任何一步抛异常整体回滚。
  static Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action,
  ) async {
    final Database db = await open();
    return db.transaction<T>(action);
  }

  /// 当前连接（只读查询用）。
  static Future<Database> database() async => open();

  /// 危险操作：清空全部业务数据，并在**同一个事务里**重建默认账本/账户/分类。
  ///
  /// ★ 删除与重建必须同事务。原版 1.4.1 及以前是「事务里只删、事务外再播种」，
  /// 播种撞主键抛异常而删除已经提交 —— 数据被删了一半、界面还挂着旧快照，
  /// 用户看到的就是「点了没反应、数据还在」。事务化之后任何一步失败都整体回滚，
  /// 调用方可以放心对用户说「数据未改动」。
  ///
  /// `setting` **不在清空范围内**：它只放机器状态与用户偏好（当前账本指针会在
  /// 播种时被覆盖成新账本，配色/触感要留着）。
  static Future<void> wipeAllData() async {
    final Database db = await open();
    await db.transaction((Transaction txn) async {
      for (final String table in Tables.wipeOrder) {
        await txn.delete(table);
      }
      final Future<void> Function(DatabaseExecutor db)? fault =
          wipeAllDataFaultForTest;
      if (fault != null) await fault(txn);
      await seedFresh(txn);
    });
  }

  /// 给指定账本补种两级分类（**不清业务数据**，幂等）。
  ///
  /// 用途：恢复旧备份后、老库补齐、或发现某本账本一个分类都没有时兜底。
  /// 已有分类的账本**不动**（返回它现有的计数），否则会把用户改过名的分类
  /// 又塞回来一份。
  ///
  /// 约定：这里只补「一本账本完全没分类」的情况；单条缺失的补齐由
  /// `ledger_repo.ensureSeedCategories` 负责（T01-4）。
  static Future<SeedResult> rebuildSeed(int ledgerId) async {
    final Database db = await open();
    return db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.category} WHERE ledger_id = ?',
        <Object?>[ledgerId],
      );
      final int existing = rows.isEmpty
          ? 0
          : (Sqflite.firstIntValue(rows) ?? 0);
      if (existing == 0) {
        return seedCategories(txn, ledgerId);
      }
      return SeedResult(
        ledgerId: ledgerId,
        topCount: 0,
        subCount: existing,
      );
    });
  }

  /// 全量替换（恢复备份 / 导入旧备份用）。
  ///
  /// 一个事务内：子表先删（[Tables.wipeOrder]）、父表先插（[Tables.all]）。
  /// 顺序错任何一步都会撞 `PRAGMA foreign_keys = ON`。
  ///
  /// `payload` 的键是表名，值是该表的行（行内键是列名）。**没提供的表按空处理**
  /// （即被清空）。`setting` 里哪些键可搬由调用方筛（机器状态不许被旧备份覆盖，
  /// 见架构设计 §4-③ 第 5 步）。
  static Future<void> replaceAll(
    Map<String, List<Map<String, Object?>>> payload, {
    Future<void> Function(DatabaseExecutor db)? afterInsert,
  }) async {
    final Database db = await open();
    await db.transaction((Transaction txn) async {
      for (final String table in Tables.wipeOrder) {
        await txn.delete(table);
      }
      await txn.delete(Tables.setting);
      for (final String table in Tables.all) {
        final List<Map<String, Object?>> rows =
            payload[table] ?? const <Map<String, Object?>>[];
        for (final Map<String, Object?> row in rows) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      // 同一个事务里跑「导入后必须做的事」（例如按流水重算余额）：
      // 放到事务外做的话，中途失败会留下「余额与流水不一致」的半截库。
      if (afterInsert != null) await afterInsert(txn);
    });
  }

  /// 读一个设置项。缺失返回 `null`（**不返回空串**，两者语义不同）。
  static Future<String?> readSetting(String key) async {
    final Database db = await open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.setting,
      columns: <String>['v'],
      where: 'k = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['v'] as String?;
  }

  /// 写一个设置项（覆盖写，立即提交，不参与外层事务）。
  static Future<void> writeSetting(String key, String value) async {
    final Database db = await open();
    await db.insert(
      Tables.setting,
      <String, Object?>{'k': key, 'v': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 取当前账本 id，**带自愈**（架构设计 §4-⑦ 第 6 步）。
  ///
  /// 三种情况：
  /// 1. 指针有效 → 直接用；
  /// 2. 指针为空或指向已删除的账本 → 回第一本（`sort_order, id` 升序）；
  /// 3. 库里一本账本都没有 → 建一本并播种，指针指向它。
  ///
  /// 自愈必须写回 `setting`，否则下次启动还要再算一遍，且明细页可能读到空账本。
  static Future<int> ensureCurrentLedgerId() async {
    final String? raw = await readSetting(SettingKeys.currentLedgerId);
    final int? pointed = raw == null ? null : int.tryParse(raw);
    if (pointed != null && await _ledgerExists(pointed)) return pointed;

    final Database db = await open();
    final List<Map<String, Object?>> first = await db.query(
      Tables.ledger,
      columns: <String>['id'],
      orderBy: 'sort_order ASC, id ASC',
      limit: 1,
    );

    final int ledgerId;
    if (first.isNotEmpty) {
      ledgerId = first.first['id']! as int;
    } else {
      final SeedResult seeded = await db.transaction(seedFresh);
      ledgerId = seeded.ledgerId;
    }
    await writeSetting(SettingKeys.currentLedgerId, '$ledgerId');
    return ledgerId;
  }

  static Future<bool> _ledgerExists(int id) async {
    final Database db = await open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.ledger,
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 表行数（体检 / 测试用）。表名必须是 [Tables.all] 里的常量。
  static Future<int> rowCount(String table) async {
    assert(Tables.all.contains(table), '未知表：$table');
    final Database db = await open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table',
    );
    if (rows.isEmpty) return 0;
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
