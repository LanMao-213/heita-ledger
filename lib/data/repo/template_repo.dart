import 'package:sqflite/sqflite.dart';

import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';

/// 记账模板 CRUD + 排序 + 使用计数。
class TemplateRepo {
  const TemplateRepo();

  Future<List<TxnTemplate>> all(int ledgerId) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.txnTemplate,
      where: '${TemplateCols.ledgerId} = ?',
      whereArgs: <Object?>[ledgerId],
      orderBy: '${TemplateCols.sortOrder} ASC, ${TemplateCols.id} ASC',
    );
    return rows.map(TxnTemplate.fromMap).toList();
  }

  /// 「最近 3 个」：用过次数优先 → 最后使用时间 → sort_order。
  Future<List<TxnTemplate>> recent(int ledgerId, {int limit = 3}) async {
    final List<TxnTemplate> all = await this.all(ledgerId);
    all.sort(TxnTemplate.recentSort);
    return all.take(limit).toList();
  }

  Future<int> insert(TxnTemplate tpl, {DatabaseExecutor? ex}) async {
    Future<int> run(DatabaseExecutor db) async {
      final int order = tpl.sortOrder > 0 ? tpl.sortOrder : await _nextOrder(db, tpl.ledgerId);
      return db.insert(
        Tables.txnTemplate,
        tpl.copyWith(sortOrder: order).toMap(),
      );
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  Future<void> update(TxnTemplate tpl, {DatabaseExecutor? ex}) async {
    final int? id = tpl.id;
    if (id == null) throw ArgumentError('update 需要 id');
    Future<void> run(DatabaseExecutor db) async {
      await db.update(
        Tables.txnTemplate,
        tpl.toMap()..remove(TemplateCols.id),
        where: '${TemplateCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<void> delete(int id, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.delete(
        Tables.txnTemplate,
        where: '${TemplateCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 用过一次：`use_count + 1`、`last_used_at = now`。
  Future<void> touch(int id, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.rawUpdate(
        'UPDATE ${Tables.txnTemplate} SET ${TemplateCols.useCount} = '
        '${TemplateCols.useCount} + 1, ${TemplateCols.lastUsedAt} = ? '
        'WHERE ${TemplateCols.id} = ?',
        <Object?>[DateTime.now().toIso8601String(), id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<void> reorder(List<int> ids, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      for (int i = 0; i < ids.length; i++) {
        await db.update(
          Tables.txnTemplate,
          <String, Object?>{TemplateCols.sortOrder: i},
          where: '${TemplateCols.id} = ?',
          whereArgs: <Object?>[ids[i]],
        );
      }
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<int> _nextOrder(DatabaseExecutor db, int ledgerId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(MAX(${TemplateCols.sortOrder}), -1) AS m '
      'FROM ${Tables.txnTemplate} WHERE ${TemplateCols.ledgerId} = ?',
      <Object?>[ledgerId],
    );
    if (rows.isEmpty) return 0;
    return asInt(rows.first['m']) + 1;
  }
}
