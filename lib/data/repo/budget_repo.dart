import 'package:sqflite/sqflite.dart';

import '../../core/local_date.dart';
import '../../core/period.dart';
import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';
import 'stats_repo.dart';

/// 预算读写（总预算 + 分类预算）。
///
/// `amount_cents <= 0` 一律视为**删行**：界面上「清空额度」就是输入 0，
/// 留一行 0 会让「有没有设预算」变成三种状态（无行 / 0 / 正数）。
class BudgetRepo {
  const BudgetRepo();

  /// 该期总预算额度；没有记录 → `null`（**不是 0**）。
  Future<int?> totalBudget(int ledgerId, LocalDate periodStart) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.budget,
      columns: <String>[BudgetCols.amountCents],
      where: '${BudgetCols.ledgerId} = ? AND ${BudgetCols.periodStart} = ? '
          'AND ${BudgetCols.categoryId} IS NULL',
      whereArgs: <Object?>[ledgerId, periodStart.iso],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return asInt(rows.first[BudgetCols.amountCents]);
  }

  /// 写总预算。
  Future<void> setTotalBudget({
    required int ledgerId,
    required LocalDate periodStart,
    required int amountCents,
    DatabaseExecutor? ex,
  }) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.delete(
        Tables.budget,
        where: '${BudgetCols.ledgerId} = ? AND ${BudgetCols.periodStart} = ? '
            'AND ${BudgetCols.categoryId} IS NULL',
        whereArgs: <Object?>[ledgerId, periodStart.iso],
      );
      if (amountCents <= 0) return;
      await db.insert(Tables.budget, <String, Object?>{
        BudgetCols.ledgerId: ledgerId,
        BudgetCols.periodStart: periodStart.iso,
        BudgetCols.categoryId: null,
        BudgetCols.amountCents: amountCents,
      });
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 该期的分类预算。
  Future<List<Budget>> categoryBudgets(
    int ledgerId,
    LocalDate periodStart, {
    DatabaseExecutor? ex,
  }) async {
    final DatabaseExecutor db = ex ?? await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.budget,
      where: '${BudgetCols.ledgerId} = ? AND ${BudgetCols.periodStart} = ? '
          'AND ${BudgetCols.categoryId} IS NOT NULL',
      whereArgs: <Object?>[ledgerId, periodStart.iso],
      orderBy: '${BudgetCols.categoryId} ASC',
    );
    return rows.map(Budget.fromMap).toList();
  }

  /// 写分类预算（`<= 0` 即删行）。
  Future<void> setCategoryBudget({
    required int ledgerId,
    required LocalDate periodStart,
    required int categoryId,
    required int amountCents,
    DatabaseExecutor? ex,
  }) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.delete(
        Tables.budget,
        where: '${BudgetCols.ledgerId} = ? AND ${BudgetCols.periodStart} = ? '
            'AND ${BudgetCols.categoryId} = ?',
        whereArgs: <Object?>[ledgerId, periodStart.iso, categoryId],
      );
      if (amountCents <= 0) return;
      await db.insert(Tables.budget, <String, Object?>{
        BudgetCols.ledgerId: ledgerId,
        BudgetCols.periodStart: periodStart.iso,
        BudgetCols.categoryId: categoryId,
        BudgetCols.amountCents: amountCents,
      });
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 一期的预算派生值（总额度 + 借入 + 已用）。
  Future<BudgetStats> stats({
    required int ledgerId,
    required Period period,
  }) async {
    final int? total = await totalBudget(ledgerId, period.from);
    final RangeTotals used = await const StatsRepo().periodTotals(
      ledgerId: ledgerId,
      period: period,
    );
    final int borrowed = await const StatsRepo().borrowedInBudget(
      ledgerId: ledgerId,
      period: period,
    );
    return BudgetStats(
      totalBudgetCents: total,
      usedCents: used.expenseCents,
      borrowedInBudgetCents: borrowed,
    );
  }

  /// 每个分类预算的「已花」（含子分类、排除借贷）。
  ///
  /// 返回 `categoryId → 已花`。只返回传进来的那几个一级分类。
  Future<Map<int, int>> spentByCategory({
    required int ledgerId,
    required Period period,
    required List<int> topCategoryIds,
  }) async {
    if (topCategoryIds.isEmpty) return <int, int>{};
    final Database db = await Db.open();
    final String placeholders =
        List<String>.filled(topCategoryIds.length, '?').join(',');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(c.${CategoryCols.parentId}, c.${CategoryCols.id}) AS root, '
      'COALESCE(SUM(ABS(t.amount_cents)), 0) AS total '
      'FROM ${Tables.txn} t '
      'JOIN ${Tables.category} c ON c.${CategoryCols.id} = t.category_id '
      'WHERE t.ledger_id = ? AND t.type = ? '
      '  AND t.period_start >= ? AND t.period_start <= ? '
      "  AND t.debt_id IS NULL AND t.amount_cents >= 0 "
      '  AND COALESCE(c.${CategoryCols.parentId}, c.${CategoryCols.id}) '
      '      IN ($placeholders) '
      'GROUP BY root',
      <Object?>[
        ledgerId,
        TxnType.expense.code,
        period.fromIso,
        period.toIso,
        ...topCategoryIds,
      ],
    );
    return <int, int>{
      for (final Map<String, Object?> r in rows) asInt(r['root']): asInt(r['total']),
    };
  }

  /// 改账单日后重算预算归属期：**两条挤进同一期时金额相加**（不是覆盖，I15）。
  ///
  /// 返回被挪动的行数。
  Future<int> remapBudgetPeriods({
    required int ledgerId,
    required int newCycleStartDay,
  }) async {
    final Database db = await Db.open();
    return db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        Tables.budget,
        where: '${BudgetCols.ledgerId} = ?',
        whereArgs: <Object?>[ledgerId],
        orderBy: '${BudgetCols.periodStart} ASC, ${BudgetCols.id} ASC',
      );

      int moved = 0;
      for (final Map<String, Object?> row in rows) {
        final Budget b = Budget.fromMap(row);
        final LocalDate target = Period.cycleStartOf(
          b.periodStart,
          newCycleStartDay,
        );
        if (target == b.periodStart) continue;

        final List<Map<String, Object?>> existing = await txn.query(
          Tables.budget,
          columns: <String>[BudgetCols.id, BudgetCols.amountCents],
          where: '${BudgetCols.ledgerId} = ? AND ${BudgetCols.periodStart} = ? '
              'AND ${BudgetCols.id} != ? '
              'AND ${b.isTotal ? '${BudgetCols.categoryId} IS NULL' : '${BudgetCols.categoryId} = ?'}',
          whereArgs: <Object?>[
            ledgerId,
            target.iso,
            b.id,
            if (!b.isTotal) b.categoryId,
          ],
          limit: 1,
        );

        if (existing.isEmpty) {
          await txn.update(
            Tables.budget,
            <String, Object?>{BudgetCols.periodStart: target.iso},
            where: '${BudgetCols.id} = ?',
            whereArgs: <Object?>[b.id],
          );
        } else {
          // 挤进同一期 → 相加
          final int keepId = asInt(existing.first[BudgetCols.id]);
          final int keepAmount = asInt(existing.first[BudgetCols.amountCents]);
          await txn.update(
            Tables.budget,
            <String, Object?>{BudgetCols.amountCents: keepAmount + b.amountCents},
            where: '${BudgetCols.id} = ?',
            whereArgs: <Object?>[keepId],
          );
          await txn.delete(
            Tables.budget,
            where: '${BudgetCols.id} = ?',
            whereArgs: <Object?>[b.id],
          );
        }
        moved++;
      }
      return moved;
    });
  }
}
