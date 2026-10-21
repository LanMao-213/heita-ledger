import 'package:sqflite/sqflite.dart';

import '../db/db.dart';
import '../db/schema.dart';
import '../db/seeds.dart';
import '../models/models.dart';

/// 删分类的结果（界面用它说清「N 笔账目转为未分类」）。
class DeleteCategoryResult {
  const DeleteCategoryResult({
    required this.detachedTxns,
    required this.deletedBudgets,
    required this.deletedCategories,
  });

  /// 被置为「未分类」的流水条数（不删流水）。
  final int detachedTxns;

  /// 被连带删掉的预算行数。
  final int deletedBudgets;

  /// 删掉的分类行数（一级连带子分类）。
  final int deletedCategories;
}

/// 分类 CRUD + 两级硬校验 + 删除连带。
class CategoryRepo {
  const CategoryRepo();

  /// 全部分类（含停用的）。
  Future<List<Category>> all(int ledgerId, {bool includeArchived = true}) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.category,
      where: includeArchived
          ? '${CategoryCols.ledgerId} = ?'
          : '${CategoryCols.ledgerId} = ? AND ${CategoryCols.archived} = 0',
      whereArgs: <Object?>[ledgerId],
      orderBy: '${CategoryCols.parentId} IS NOT NULL, '
          '${CategoryCols.sortOrder} ASC, ${CategoryCols.id} ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<CategoryTree> tree(int ledgerId) async =>
      CategoryTree(await all(ledgerId));

  /// 新增分类。`parentId` 必须指向**同账本同类型的一级**分类。
  Future<int> insert(Category category, {DatabaseExecutor? ex}) async {
    Future<int> run(DatabaseExecutor db) async {
      await _validateParent(db, category);
      final int order = category.sortOrder > 0
          ? category.sortOrder
          : await _nextSortOrder(db, category);
      return db.insert(
        Tables.category,
        category.copyWith(sortOrder: order).toMap(),
      );
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  /// 改名 / 换图标 / 停用。**不允许改层级**（`parentId` 只能保持原值或 null→保持）。
  Future<void> update(Category category, {DatabaseExecutor? ex}) async {
    final int? id = category.id;
    if (id == null) throw ArgumentError('update 需要 id');
    Future<void> run(DatabaseExecutor db) async {
      final List<Map<String, Object?>> rows = await db.query(
        Tables.category,
        columns: <String>[CategoryCols.parentId, CategoryCols.ledgerId],
        where: '${CategoryCols.id} = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('分类不存在：$id');
      final int? oldParent = asIntOrNull(rows.first[CategoryCols.parentId]);
      if (oldParent != null && category.parentId != oldParent) {
        throw ArgumentError('不允许改层级：子分类只能留在原父级下');
      }
      await db.update(
        Tables.category,
        <String, Object?>{
          CategoryCols.name: category.name.trim(),
          CategoryCols.icon: category.icon,
          CategoryCols.archived: boolToInt(category.archived),
        },
        where: '${CategoryCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 按给定顺序重排（只动 `sort_order`，按数组下标编号）。
  Future<void> reorder(List<int> ids, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      for (int i = 0; i < ids.length; i++) {
        await db.update(
          Tables.category,
          <String, Object?>{CategoryCols.sortOrder: i},
          where: '${CategoryCols.id} = ?',
          whereArgs: <Object?>[ids[i]],
        );
      }
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<void> setArchived(int id, bool archived, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.update(
        Tables.category,
        <String, Object?>{CategoryCols.archived: boolToInt(archived)},
        where: '${CategoryCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 删分类（I14）：一个事务里 ① 流水 `category_id` 置 NULL（**不删交易**）
  /// ② 删指向它的 `budget` 行 ③ 删分类（一级连带子分类）
  Future<DeleteCategoryResult> delete(int id, {DatabaseExecutor? ex}) async {
    Future<DeleteCategoryResult> run(DatabaseExecutor db) async {
      final List<Map<String, Object?>> rows = await db.query(
        Tables.category,
        columns: <String>[CategoryCols.parentId],
        where: '${CategoryCols.id} = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return const DeleteCategoryResult(
          detachedTxns: 0,
          deletedBudgets: 0,
          deletedCategories: 0,
        );
      }
      final bool isTop = asIntOrNull(rows.first[CategoryCols.parentId]) == null;

      // 涉及的分类 id：一级连带它的子分类
      final List<int> ids = <int>[id];
      if (isTop) {
        final List<Map<String, Object?>> children = await db.query(
          Tables.category,
          columns: <String>[CategoryCols.id],
          where: '${CategoryCols.parentId} = ?',
          whereArgs: <Object?>[id],
        );
        for (final Map<String, Object?> c in children) {
          ids.add(asInt(c[CategoryCols.id]));
        }
      }
      final String placeholders = List<String>.filled(ids.length, '?').join(',');

      final int detached = await db.rawUpdate(
        'UPDATE ${Tables.txn} SET ${TxnCols.categoryId} = NULL '
        'WHERE ${TxnCols.categoryId} IN ($placeholders)',
        ids,
      );
      final int budgets = await db.delete(
        Tables.budget,
        where: '${BudgetCols.categoryId} IN ($placeholders)',
        whereArgs: ids,
      );
      // 子分类先删（parent_id 上没有 ON DELETE CASCADE）
      await db.delete(
        Tables.category,
        where: '${CategoryCols.parentId} = ?',
        whereArgs: <Object?>[id],
      );
      final int deleted = await db.delete(
        Tables.category,
        where: '${CategoryCols.id} = ?',
        whereArgs: <Object?>[id],
      );
      return DeleteCategoryResult(
        detachedTxns: detached,
        deletedBudgets: budgets,
        deletedCategories: deleted + (ids.length - 1),
      );
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  /// 补齐某账本的分类种子（幂等）。
  Future<void> ensureSeedCategories(int ledgerId, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.category} '
        'WHERE ${CategoryCols.ledgerId} = ?',
        <Object?>[ledgerId],
      );
      if ((Sqflite.firstIntValue(rows) ?? 0) > 0) return;
      await seedCategories(db, ledgerId);
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<void> _validateParent(DatabaseExecutor db, Category c) async {
    final int? parentId = c.parentId;
    if (parentId == null) return;
    final List<Map<String, Object?>> rows = await db.query(
      Tables.category,
      columns: <String>[
        CategoryCols.parentId,
        CategoryCols.ledgerId,
        CategoryCols.type,
      ],
      where: '${CategoryCols.id} = ?',
      whereArgs: <Object?>[parentId],
      limit: 1,
    );
    if (rows.isEmpty) throw ArgumentError('父分类不存在：$parentId');
    final Map<String, Object?> row = rows.first;
    if (asIntOrNull(row[CategoryCols.parentId]) != null) {
      throw ArgumentError('不支持三级分类：父分类本身是子分类');
    }
    if (asInt(row[CategoryCols.ledgerId]) != c.ledgerId) {
      throw ArgumentError('父子分类必须属于同一本账本');
    }
    if (asString(row[CategoryCols.type]) != c.type.code) {
      throw ArgumentError('父子分类必须同类型（支出/收入不能混）');
    }
  }

  Future<int> _nextSortOrder(DatabaseExecutor db, Category c) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(MAX(${CategoryCols.sortOrder}), -1) AS m '
      'FROM ${Tables.category} '
      'WHERE ${CategoryCols.ledgerId} = ? AND ${CategoryCols.type} = ? '
      'AND ${CategoryCols.parentId} IS ?',
      <Object?>[c.ledgerId, c.type.code, c.parentId],
    );
    if (rows.isEmpty) return 0;
    return asInt(rows.first['m']) + 1;
  }
}
