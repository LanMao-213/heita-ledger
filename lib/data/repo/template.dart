part of '../repo.dart';

// ---------------------------------------------------------------------------
// 记账模板：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  // ------------------------------------------------------------------- 模板

  /// 管理页用的顺序：用户拖出来的顺序优先
Future<List<TxnTemplate>> _repoListTemplates(int ledgerId) async {
  final db = await Db.open();
  final rows = await db.query(
    'txn_template',
    where: 'ledger_id = ?',
    whereArgs: [ledgerId],
    orderBy: 'sort_order, id',
  );
  return rows.map(TxnTemplate.fromMap).toList();
}

  /// 记一笔面板顶部那排「常用模板」：用得多的在前，同频次看最近用过谁
Future<List<TxnTemplate>> _repoRecentTemplates(
  int ledgerId, {
  int limit = 3,
}) async {
  final db = await Db.open();
  final rows = await db.query(
    'txn_template',
    where: 'ledger_id = ?',
    whereArgs: [ledgerId],
    orderBy:
        "use_count DESC, COALESCE(last_used_at, '') DESC, sort_order, id",
    limit: limit,
  );
  return rows.map(TxnTemplate.fromMap).toList();
}

Future<int> _repoInsertTemplate(TxnTemplate t) async {
  final db = await Db.open();
  // 新模板排到最后
  final r = await db.rawQuery(
    'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM txn_template WHERE ledger_id = ?',
    [t.ledgerId],
  );
  final order = (r.first['n'] as int?) ?? 0;
  return db.insert('txn_template', t.copyWith(sortOrder: order).toMap());
}

Future<void> _repoUpdateTemplate(TxnTemplate t) async {
  final db = await Db.open();
  await db.update(
    'txn_template',
    t.toMap(),
    where: 'id = ?',
    whereArgs: [t.id],
  );
}

Future<void> _repoDeleteTemplate(int id) async {
  final db = await Db.open();
  await db.delete('txn_template', where: 'id = ?', whereArgs: [id]);
}

  /// 用了一次模板 —— 只动统计列，不动用户填的内容
Future<void> _repoTouchTemplate(int id) async {
  final db = await Db.open();
  await db.rawUpdate(
    'UPDATE txn_template SET use_count = use_count + 1, last_used_at = ? '
    'WHERE id = ?',
    [DateTime.now().toIso8601String(), id],
  );
}

  /// 拖动排序：把当前顺序整体写回 sort_order
Future<void> _repoReorderTemplates(List<int> orderedIds) async {
  final db = await Db.open();
  await db.transaction((txn) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await txn.update(
        'txn_template',
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [orderedIds[i]],
      );
    }
  });
}
