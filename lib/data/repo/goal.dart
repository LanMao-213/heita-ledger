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
  // 流水是目标的子表（`goal_id` 软关联，没有外键级联），删目标必须连它一起删：
  // 留下孤儿流水会在「清空数据」之外留下永不消失的残渣，而备份里也会带着它。
  await db.transaction((txn) async {
    await txn.delete('goal_flow', where: 'goal_id = ?', whereArgs: [id]);
    await txn.delete('saving_goal', where: 'id = ?', whereArgs: [id]);
  });
}

/// 某个目标的存/取流水，最近的在最前。
Future<List<GoalFlow>> _repoListGoalFlows(int goalId) async {
  final db = await Db.open();
  final rows = await db.query(
    'goal_flow',
    where: 'goal_id = ?',
    whereArgs: [goalId],
    orderBy: 'date DESC, id DESC',
  );
  return rows.map(GoalFlow.fromMap).toList();
}

/// 所有目标的流水，一次查完。
///
/// 为什么不是「每个目标查一次」：计划页要同时给每张目标卡算预计达成时间，
/// 按目标循环查就是 N+1 次（N 通常 < 10，但每次都是独立的事务与磁盘往返）。
/// 一次性取回再在内存里分组，代价是一条 SQL。
Future<List<GoalFlow>> _repoListAllGoalFlows() async {
  final db = await Db.open();
  final rows = await db.query('goal_flow', orderBy: 'date DESC, id DESC');
  return rows.map(GoalFlow.fromMap).toList();
}

/// 存钱 / 取钱（金额可为负）。
///
/// 与 1.5.1 的区别只有一件事：**落一条流水**。旧实现是一句
/// `UPDATE saving_goal SET saved_cents = MAX(0, saved_cents + ?)`，
/// 没有时间也没有账户 —— 于是「按当前进度预计何时达成」根本算不出月均速率。
///
/// 两个容易写错的点：
/// 1. **流水金额必须等于实际变化量**。`saved_cents` 有 0 下限：想取 500 但只剩
///    300 时，只能取到 300，流水就必须记 -300。否则 `Σ(flow)` 与 `saved_cents`
///    对不上，预计达成时间会基于一个不存在的余额算下去。
/// 2. **整件事在一个事务里**。先读后写两条语句，中间若失败而 `saved_cents`
///    已提交，就会出现「钱存了但没流水」，比不存更糟。
///
/// ★ 1.6.0 收掉了 `accountId` 参数：它只往 `goal_flow.account_id` 写一个 id，
///   **却不改那个账户的余额** —— 库里于是留下「钱从 A 账户挪走了」这条假事实，
///   而账户余额一分没动，下次体检就会报一条对不上的账。要么两个都改（那是一次
///   真实的转账，需要用户确认从哪个账户出、以及余额够不够），要么都不改。
///   现在恒写 `NULL`：这一列留着不删（老库里的行还在、备份格式不动、不升 v11），
///   含义收窄成「不涉及账户」。真正需要记「从哪个账户出」时，那是一个独立的
///   转账流程，不是这里顺手加个参数。
Future<void> _repoAddFunds(
  int goalId,
  int deltaCents, {
  String? date,
  String note = '',
}) async {
  if (deltaCents == 0) return;
  final db = await Db.open();
  await db.transaction((txn) async {
    final rows = await txn.query(
      'saving_goal',
      columns: ['saved_cents'],
      where: 'id = ?',
      whereArgs: [goalId],
      limit: 1,
    );
    if (rows.isEmpty) return; // 目标已被删：静默退出，不写孤儿流水
    final current = (rows.first['saved_cents'] as int?) ?? 0;
    final floor = current + deltaCents < 0 ? 0 : current + deltaCents;
    final effective = floor - current;
    if (effective == 0) return; // 已经存不进去了（saved 被取到 0），不必记一笔 0
    await txn.update(
      'saving_goal',
      {'saved_cents': floor},
      where: 'id = ?',
      whereArgs: [goalId],
    );
    await txn.insert('goal_flow', {
      'goal_id': goalId,
      'date': date ?? Fmt.today(),
      'cents': effective,
      // 恒 NULL：见上面「1.6.0 收掉了 accountId」那段
      'account_id': null,
      'note': note,
    });
  });
}
