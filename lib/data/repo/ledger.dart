part of '../repo.dart';

// ---------------------------------------------------------------------------
// 账本：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  /// 当前账本 id。
  ///
  /// ★ 存下来的 id **必须校验还活着**：1.4.1 的清空 bug 会在库里留下
  /// 「`current_ledger_id` 指着已删除的账本」这种状态，直接沿用的话，
  /// 明细、分类、预算全部按一个不存在的 ledger_id 去查 —— 界面上一片空白，
  /// 记一笔也看不见（新记录挂在另一个账本上）。这里发现对不上就改成真实存在的
  /// 那一本，让已经中招的库在下次启动时自愈，不用重装。
Future<int> _repoCurrentLedgerId() async {
  final v = await _repoGetSetting('current_ledger_id');
  final saved = int.tryParse(v ?? '');
  if (saved != null) {
    final db = await Db.open();
    final hit = await db.query(
      'ledger',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [saved],
      limit: 1,
    );
    if (hit.isNotEmpty) return saved;
  }
  final ledgers = await _repoListLedgers();
  if (ledgers.isEmpty) {
    final db = await Db.open();
    final id = await db.insert('ledger', {
      'name': '日常账本',
      'icon': 'book',
      'sort_order': 0,
      'archived': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _repoSetSetting('current_ledger_id', '$id');
    return id;
  }
  await _repoSetSetting('current_ledger_id', '${ledgers.first.id}');
  return ledgers.first.id;
}

  // ------------------------------------------------------------------- 账本
Future<List<Ledger>> _repoListLedgers({
  bool includeArchived = false,
}) async {
  final db = await Db.open();
  final rows = await db.query(
    'ledger',
    where: includeArchived ? null : 'archived = 0',
    orderBy: 'sort_order, id',
  );
  return rows.map(Ledger.fromMap).toList();
}

Future<int> _repoInsertLedger(Ledger l) async {
  final db = await Db.open();
  final id = await db.insert('ledger', l.toMap());
  // 新账本要带上默认分类，否则记一笔时没分类可选。
  // 走 `Db.seedCategories` 而不是在这儿再列一份分类表 —— 两处各写一份，
  // 迟早出现「首启账本有正餐、新建账本只有餐饮」这种只在新建账本上复现的怪事。
  await Db.seedCategories(db, id);
  return id;
}

Future<void> _repoUpdateLedger(Ledger l) async {
  final db = await Db.open();
  await db.update('ledger', l.toMap(), where: 'id = ?', whereArgs: [l.id]);
}

  /// 删除账本会级联删掉它的分类与交易（外键 ON DELETE CASCADE）
Future<void> _repoDeleteLedger(int id) async {
  final db = await Db.open();
  await db.delete('ledger', where: 'id = ?', whereArgs: [id]);
}
