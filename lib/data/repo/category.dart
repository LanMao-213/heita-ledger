part of '../repo.dart';

// ---------------------------------------------------------------------------
// 分类（含抬期白名单）：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  // ------------------------------------------------------------------- 分类
Future<List<Category>> _repoListCategories(
  int ledgerId, {
  TxnType? type,
  bool includeArchived = false,
}) async {
  final db = await Db.open();
  final where = StringBuffer('ledger_id = ?');
  final args = <Object?>[ledgerId];
  if (type != null) {
    where.write(' AND type = ?');
    args.add(type.code);
  }
  if (!includeArchived) where.write(' AND archived = 0');
  final rows = await db.query(
    'category',
    where: where.toString(),
    whereArgs: args,
    orderBy: 'sort_order, id',
  );
  return rows.map(Category.fromMap).toList();
}

Future<int> _repoInsertCategory(Category c) async {
  final db = await Db.open();
  // 两级上限：父级自己必须是一级分类，否则就会长出第三层。
  // 数据层拦一道，比在界面上藏入口可靠 —— 导入 Excel、恢复备份都会走这里。
  if (c.parentId != null) {
    final parent = await db.query(
      'category',
      columns: ['parent_id'],
      where: 'id = ?',
      whereArgs: [c.parentId],
      limit: 1,
    );
    if (parent.isEmpty || parent.first['parent_id'] != null) {
      throw ArgumentError('子分类的父级必须是一级分类');
    }
  }
  return db.insert('category', c.toMap());
}

Future<void> _repoUpdateCategory(Category c) async {
  final db = await Db.open();
  await db.update('category', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
}

  /// 分类被删时，历史交易的 `category_id` 置空（不连带删交易）。
  ///
  /// 删一级分类会**连同它的子分类一起删**：子分类失去父级之后既不会出现在
  /// 轮盘里，也没法在界面上找到，留着只会变成孤儿行。
Future<void> _repoDeleteCategory(int id) async {
  final db = await Db.open();
  await db.transaction((txn) async {
    final subs = await txn.query(
      'category',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    final ids = [id, ...subs.map((r) => r['id'] as int)];
    final marks = List.filled(ids.length, '?').join(',');
    await txn.update(
      'txn',
      {'category_id': null},
      where: 'category_id IN ($marks)',
      whereArgs: ids,
    );
    // 指向这些分类的预算也要一起清掉，否则会留下查不到分类的预算行
    await txn.delete(
      'budget',
      where: 'category_id IN ($marks)',
      whereArgs: ids,
    );
    await txn.delete('category', where: 'id IN ($marks)', whereArgs: ids);
  });
}

  /// 某账本里属于「抬期池」的收入分类 id。
  ///
  /// 白名单只按**分类名**判定，用户改名/删掉分类后自动失效 —— 这正是设计里
  /// 「白名单只决定默认值」的意思：真正落库前每笔仍可手动改（阶段 5 的开关）。
Future<Set<int>> _repoLiftableCategoryIds(int ledgerId) async {
  final db = await Db.open();
  return _liftableCategoryIds(db, ledgerId);
}

Future<Set<int>> _liftableCategoryIds(
  DatabaseExecutor db,
  int ledgerId,
) async {
  final keys = Repo.liftableIncomeNames.toList();
  final rows = await db.query(
    'category',
    columns: ['id'],
    where:
        'ledger_id = ? AND type = ? '
        'AND name IN (${List.filled(keys.length, '?').join(',')})',
    whereArgs: [ledgerId, TxnType.income.code, ...keys],
  );
  return rows.map((r) => r['id'] as int).toSet();
}

  /// 按传入顺序重写分类的 `sort_order`（0..n-1）。
  ///
  /// 只动排序，不碰名称、图标、停用状态。停用的分类不参与排序 ——
  /// 管理页把它们单独排在下面，拖的是「使用中」那一段。
Future<void> _repoReorderCategories(List<int> orderedIds) async {
  final db = await Db.open();
  await db.transaction((txn) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await txn.update(
        'category',
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [orderedIds[i]],
      );
    }
  });
}

  /// 停用 / 恢复一个分类。
  ///
  /// 不级联：停用一级分类时，它的子分类保持原状。理由是一级分类消失后，
  /// 子分类本来就到不了（选择器先选一级再选二级），级联反而会让「恢复一级」
  /// 顺手把用户单独停用过的子分类也放出来。
Future<void> _repoSetCategoryArchived(int id, {required bool archived}) async {
  final db = await Db.open();
  await db.update(
    'category',
    {'archived': archived ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );
}
