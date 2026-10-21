import 'package:sqflite/sqflite.dart';

import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';

/// 储蓄目标 CRUD（全局，不按账本）。
///
/// `addFunds` 的语义是「存钱 / 取钱」：`saved = MAX(0, saved + delta)`，
/// **不生成流水**（否则存钱变成一笔支出，预算与统计全被污染）。
class GoalRepo {
  const GoalRepo();

  Future<List<SavingGoal>> all() async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.savingGoal,
      orderBy: '${GoalCols.sortOrder} ASC, ${GoalCols.id} ASC',
    );
    return rows.map(SavingGoal.fromMap).toList();
  }

  Future<int> insert(SavingGoal goal, {DatabaseExecutor? ex}) async {
    Future<int> run(DatabaseExecutor db) async {
      final int order =
          goal.sortOrder > 0 ? goal.sortOrder : await _nextOrder(db);
      return db.insert(
        Tables.savingGoal,
        goal.copyWith(sortOrder: order).toMap(),
      );
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  Future<void> update(SavingGoal goal, {DatabaseExecutor? ex}) async {
    final int? id = goal.id;
    if (id == null) throw ArgumentError('update 需要 id');
    Future<void> run(DatabaseExecutor db) async {
      await db.update(
        Tables.savingGoal,
        goal.toMap()..remove(GoalCols.id),
        where: '${GoalCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<void> delete(int id, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.delete(
        Tables.savingGoal,
        where: '${GoalCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 存钱（正数）/ 取钱（负数）。取超了按 0 兜底，不出现负存款。
  Future<int> addFunds(int id, int deltaCents, {DatabaseExecutor? ex}) async {
    Future<int> run(DatabaseExecutor db) async {
      final List<Map<String, Object?>> rows = await db.query(
        Tables.savingGoal,
        columns: <String>[GoalCols.savedCents],
        where: '${GoalCols.id} = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      final int current = asInt(rows.first[GoalCols.savedCents]);
      final int next = current + deltaCents;
      final int clamped = next < 0 ? 0 : next;
      await db.update(
        Tables.savingGoal,
        <String, Object?>{GoalCols.savedCents: clamped},
        where: '${GoalCols.id} = ?',
        whereArgs: <Object?>[id],
      );
      return clamped;
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  Future<void> reorder(List<int> ids, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      for (int i = 0; i < ids.length; i++) {
        await db.update(
          Tables.savingGoal,
          <String, Object?>{GoalCols.sortOrder: i},
          where: '${GoalCols.id} = ?',
          whereArgs: <Object?>[ids[i]],
        );
      }
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<int> _nextOrder(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(MAX(${GoalCols.sortOrder}), -1) AS m '
      'FROM ${Tables.savingGoal}',
    );
    if (rows.isEmpty) return 0;
    return asInt(rows.first['m']) + 1;
  }
}
