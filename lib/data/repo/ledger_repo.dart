import 'package:sqflite/sqflite.dart';

import '../db/db.dart';
import '../db/schema.dart';
import '../db/seeds.dart';
import '../models/models.dart';
import 'setting_repo.dart';

/// 账本 CRUD + 当前账本指针自愈。
class LedgerRepo {
  const LedgerRepo();

  /// 全部账本（按 `sort_order, id`）。
  Future<List<Ledger>> all() async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.ledger,
      orderBy: '${LedgerCols.sortOrder} ASC, ${LedgerCols.id} ASC',
    );
    return rows.map(Ledger.fromMap).toList();
  }

  /// 当前账本 id（含自愈：指针指错 → 回第一本；一本都没有 → 建一本并播种）。
  Future<int> currentId() => Db.ensureCurrentLedgerId();

  /// 当前账本对象。
  Future<Ledger?> current() async {
    final int id = await currentId();
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.ledger,
      where: '${LedgerCols.id} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Ledger.fromMap(rows.first);
  }

  /// 新建账本，**同一个事务里灌完整两级分类**（I6 / 原版 c-5、b-1 的正面修复）。
  ///
  /// 返回新账本 id 与播种计数。历史上那个洞是「新建账本只灌旧的扁平 10/6 分类，
  /// 且没有测试钉住」—— 所以这里把计数做成返回值，调用方与测试都能直接断言。
  Future<({int id, SeedResult seed})> insertLedger({
    required String name,
    String icon = 'book',
    bool makeCurrent = true,
  }) async {
    final Database db = await Db.open();
    final ({int id, SeedResult seed}) result = await db.transaction((
      Transaction txn,
    ) async {
      final int maxOrder =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COALESCE(MAX(${LedgerCols.sortOrder}), -1) AS m '
              'FROM ${Tables.ledger}',
            ),
          ) ??
          -1;
      final int id = await txn.insert(Tables.ledger, <String, Object?>{
        LedgerCols.name: name.trim().isEmpty ? '未命名账本' : name.trim(),
        LedgerCols.icon: icon,
        LedgerCols.sortOrder: maxOrder + 1,
        LedgerCols.createdAt: DateTime.now().toIso8601String(),
      });
      final SeedResult seed = await seedCategories(txn, id);
      if (makeCurrent) {
        await txn.insert(
          Tables.setting,
          <String, Object?>{SettingCols.k: 'current_ledger_id', SettingCols.v: '$id'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return (id: id, seed: seed);
    });
    return result;
  }

  Future<void> rename(int id, String name) async {
    final String v = name.trim();
    if (v.isEmpty) return;
    final Database db = await Db.open();
    await db.update(
      Tables.ledger,
      <String, Object?>{LedgerCols.name: v},
      where: '${LedgerCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 删账本：外键 `ON DELETE CASCADE` 会连带分类与流水（`PRAGMA foreign_keys = ON`）。
  ///
  /// 删的是**当前账本**时，把指针自愈到第一本（一本都没有则重建）。
  /// ★ 事务内**不许**调 `SettingRepo`（它自己会 `Db.open()` + 查询，
  ///   与外层事务抢锁 → 数据库锁死 10 秒后超时）。所有读写都走 `txn`。
  Future<void> deleteLedger(int id) async {
    final Database db = await Db.open();
    await db.transaction((Transaction txn) async {
      await txn.delete(
        Tables.ledger,
        where: '${LedgerCols.id} = ?',
        whereArgs: <Object?>[id],
      );

      final List<Map<String, Object?>> currentRows = await txn.query(
        Tables.setting,
        columns: <String>[SettingCols.v],
        where: '${SettingCols.k} = ?',
        whereArgs: <Object?>[SettingKeys.currentLedgerId],
        limit: 1,
      );
      final int? current = currentRows.isEmpty
          ? null
          : int.tryParse(asString(currentRows.first[SettingCols.v]));
      if (current != id) return;

      final List<Map<String, Object?>> left = await txn.query(
        Tables.ledger,
        columns: <String>[LedgerCols.id],
        orderBy: '${LedgerCols.sortOrder} ASC, ${LedgerCols.id} ASC',
        limit: 1,
      );
      final int next = left.isEmpty
          ? (await seedFresh(txn)).ledgerId
          : left.first[LedgerCols.id]! as int;
      await txn.insert(
        Tables.setting,
        <String, Object?>{SettingCols.k: 'current_ledger_id', SettingCols.v: '$next'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// 切换账本（只写指针；四个 Store 的重载由 `BookStore.switchLedger` 编排）。
  Future<void> switchTo(int id) async {
    await const SettingRepo().setCurrentLedgerId(id);
  }

  /// 该账本下的分类数（体检/测试用）。
  Future<int> categoryCount(int ledgerId) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.category} '
      'WHERE ${CategoryCols.ledgerId} = ?',
      <Object?>[ledgerId],
    );
    if (rows.isEmpty) return 0;
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
