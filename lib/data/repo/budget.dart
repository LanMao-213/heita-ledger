part of '../repo.dart';

// ---------------------------------------------------------------------------
// 预算：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  // ------------------------------------------------------------------- 预算

  /// 某一期的预算明细（`category_id IS NULL` 那条是总预算）
Future<List<Budget>> _repoListBudgets(
  int ledgerId,
  String periodStart,
) async {
  final db = await Db.open();
  final rows = await db.query(
    'budget',
    where: 'ledger_id = ? AND period_start = ?',
    whereArgs: [ledgerId, periodStart],
  );
  return rows.map(Budget.fromMap).toList();
}

  /// 总预算（category_id 为 NULL 的那条）
Future<int?> _repoTotalBudgetCents(int ledgerId, String periodStart) async {
  final db = await Db.open();
  final rows = await db.query(
    'budget',
    columns: ['amount_cents'],
    where: 'ledger_id = ? AND period_start = ? AND category_id IS NULL',
    whereArgs: [ledgerId, periodStart],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return (rows.first['amount_cents'] as int?) ?? 0;
}

Future<void> _repoSetBudget({
  required int ledgerId,
  required String periodStart,
  int? categoryId,
  required int amountCents,
}) async {
  final db = await Db.open();
  if (amountCents <= 0) {
    await db.delete(
      'budget',
      where:
          'ledger_id = ? AND period_start = ? AND '
          '${categoryId == null ? 'category_id IS NULL' : 'category_id = ?'}',
      whereArgs: [ledgerId, periodStart, ?categoryId],
    );
    return;
  }
  await db.insert('budget', {
    'ledger_id': ledgerId,
    'period_start': periodStart,
    'category_id': categoryId,
    'amount_cents': amountCents,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

  /// 改账单日后，把预算挪到新的归属期上。
  ///
  /// 预算的 key 是 `period_start`，账单日一变，原来那些 key 就落在期中间了
  /// （10-15 起的一期，在账单日改回 1 号后已经不存在）。规则是：
  /// **按「旧期第一天」找到它现在落进哪一期**，挪过去。
  ///
  /// 两条旧预算可能挤进同一期（期变长时），此时**金额相加**而不是让后一条
  /// 覆盖前一条 —— 覆盖等于凭空吃掉一笔预算，用户只会觉得「我的预算少了」。
Future<int> _repoRemapBudgetPeriods(int startDay) async {
  final db = await Db.open();
  final rows = await db.query(
    'budget',
    columns: ['ledger_id', 'period_start', 'category_id', 'amount_cents'],
  );
  if (rows.isEmpty) return 0;

  final merged = <(int, String, int?), int>{};
  for (final r in rows) {
    final newStart = periodStartOf(r['period_start'] as String, startDay);
    final key = (r['ledger_id'] as int, newStart, r['category_id'] as int?);
    merged[key] = (merged[key] ?? 0) + ((r['amount_cents'] as int?) ?? 0);
  }

  await db.transaction((txn) async {
    await txn.delete('budget');
    final batch = txn.batch();
    merged.forEach((key, amount) {
      batch.insert('budget', {
        'ledger_id': key.$1,
        'period_start': key.$2,
        'category_id': key.$3,
        'amount_cents': amount,
      });
    });
    await batch.commit(noResult: true);
  });
  return merged.length;
}
