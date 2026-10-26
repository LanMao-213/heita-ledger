part of '../repo.dart';

// ---------------------------------------------------------------------------
// 储蓄目标：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  // --------------------------------------------------------------- 储蓄目标
Future<List<SavingGoal>> _repoListGoals({
  bool includeArchived = false,
}) async {
  final db = await Db.open();
  final rows = await db.query(
    'saving_goal',
    where: includeArchived ? null : 'archived = 0',
    orderBy: 'sort_order, id',
  );
  return rows.map(SavingGoal.fromMap).toList();
}

Future<int> _repoInsertGoal(SavingGoal g) async {
  final db = await Db.open();
  return db.insert('saving_goal', g.toMap());
}

Future<void> _repoUpdateGoal(SavingGoal g) async {
  final db = await Db.open();
  await db.update(
    'saving_goal',
    g.toMap(),
    where: 'id = ?',
    whereArgs: [g.id],
  );
}

Future<void> _repoDeleteGoal(int id) async {
  final db = await Db.open();
  await db.delete('saving_goal', where: 'id = ?', whereArgs: [id]);
}

  /// 存钱 / 取钱（金额可为负）
Future<void> _repoAddFunds(int goalId, int deltaCents) async {
  final db = await Db.open();
  await db.rawUpdate(
    'UPDATE saving_goal SET saved_cents = MAX(0, saved_cents + ?) WHERE id = ?',
    [deltaCents, goalId],
  );
}
