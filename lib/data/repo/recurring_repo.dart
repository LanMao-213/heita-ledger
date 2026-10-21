import 'package:sqflite/sqflite.dart';

import '../../core/local_date.dart';
import '../../core/period.dart';
import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';
import 'account_repo.dart';
import 'setting_repo.dart';

/// 周期账单规则 CRUD + 补记。
///
/// 补记的三道闸（口径 3.10）：
/// ① 上游（`PlanStore`）按**账本**记「今天扫过没有」；
/// ② 上游复用同一个在飞 Future；
/// ③ **物理唯一**：`ux_txn_recurring_date` + `INSERT OR IGNORE`，插不进去就
///    只记日志、**继续推进日期**（不 break）。
class RecurringRepo {
  const RecurringRepo();

  Future<List<Recurring>> all(int ledgerId) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.recurring,
      where: '${RecurringCols.ledgerId} = ?',
      whereArgs: <Object?>[ledgerId],
      orderBy: '${RecurringCols.enabled} DESC, ${RecurringCols.nextRunDate} ASC, '
          '${RecurringCols.id} ASC',
    );
    return rows.map(Recurring.fromMap).toList();
  }

  Future<int> insert(Recurring rule, {DatabaseExecutor? ex}) async {
    Future<int> run(DatabaseExecutor db) =>
        db.insert(Tables.recurring, rule.toMap());

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  Future<void> update(Recurring rule, {DatabaseExecutor? ex}) async {
    final int? id = rule.id;
    if (id == null) throw ArgumentError('update 需要 id');
    Future<void> run(DatabaseExecutor db) async {
      await db.update(
        Tables.recurring,
        rule.toMap()..remove(RecurringCols.id),
        where: '${RecurringCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<void> delete(int id, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.delete(
        Tables.recurring,
        where: '${RecurringCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  Future<void> setEnabled(int id, bool enabled) async {
    final Database db = await Db.open();
    await db.update(
      Tables.recurring,
      <String, Object?>{RecurringCols.enabled: boolToInt(enabled)},
      where: '${RecurringCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 补记到期的规则，返回新增笔数。
  ///
  /// 交易日期用**规则本应触发的日期**（`next_run_date`），不是补记当天 ——
  /// 否则房租全记在补记那天，历史月份全是窟窿。
  /// 连续欠多期逐期补，单条规则最多 60 期（防御脏数据写出十万行）。
  Future<int> runDueRecurring({
    required int ledgerId,
    required int cycleStartDay,
    LocalDate? today,
  }) async {
    final LocalDate now = today ?? LocalDate.today();
    final Database db = await Db.open();

    final List<Map<String, Object?>> due = await db.query(
      Tables.recurring,
      where: '${RecurringCols.ledgerId} = ? AND ${RecurringCols.enabled} = 1 '
          'AND ${RecurringCols.nextRunDate} <= ?',
      whereArgs: <Object?>[ledgerId, now.iso],
      orderBy: '${RecurringCols.nextRunDate} ASC',
    );
    if (due.isEmpty) return 0;

    int added = 0;
    for (final Map<String, Object?> row in due) {
      final Recurring rule = Recurring.fromMap(row);
      added += await Db.transaction((Transaction txn) async {
        int count = 0;
        LocalDate runDate = rule.nextRunDate;
        int guard = 0;
        while (runDate <= now && guard++ < 60) {
          final LocalDate? end = rule.endDate;
          if (end != null && runDate > end) break;

          final Txn principal = Txn(
            ledgerId: ledgerId,
            type: rule.type,
            amountCents: rule.amountCents,
            categoryId: rule.categoryId,
            accountId: rule.accountId,
            date: runDate,
            periodStart: Period.periodStartOf(runDate, cycleStartDay),
            note: rule.note.trim().isEmpty ? '周期账单' : rule.note,
            recurringId: rule.id,
            createdAt: DateTime.now(),
          );

          // ③ 物理唯一：重复时 rowid 为 0，**仍然推进日期**
          final int id = await txn.rawInsert(
            'INSERT OR IGNORE INTO ${Tables.txn} '
            '(${TxnCols.ledgerId}, ${TxnCols.type}, ${TxnCols.amountCents}, '
            ' ${TxnCols.categoryId}, ${TxnCols.accountId}, ${TxnCols.date}, '
            ' ${TxnCols.periodStart}, ${TxnCols.note}, ${TxnCols.recurringId}, '
            ' ${TxnCols.createdAt}) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            <Object?>[
              principal.ledgerId,
              principal.type.code,
              principal.amountCents,
              principal.categoryId,
              principal.accountId,
              principal.date.iso,
              principal.periodStart?.iso,
              principal.note,
              principal.recurringId,
              principal.createdAt.toIso8601String(),
            ],
          );
          if (id != 0) {
            await const AccountRepo().applyBalanceDelta(txn, principal);
            count++;
          }

          runDate = Recurring.advanceDate(runDate, rule.freq, rule.interval);
        }

        await txn.update(
          Tables.recurring,
          <String, Object?>{RecurringCols.nextRunDate: runDate.iso},
          where: '${RecurringCols.id} = ?',
          whereArgs: <Object?>[rule.id],
        );
        return count;
      });
    }
    return added;
  }

  /// 兜底：把规则的 `next_run_date` 一次性推到今天之后（跳过欠期）。
  Future<void> skipToToday(int id, LocalDate today, {int cycleStartDay = 1}) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.recurring,
      where: '${RecurringCols.id} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final Recurring rule = Recurring.fromMap(rows.first);
    LocalDate runDate = rule.nextRunDate;
    int guard = 0;
    while (runDate <= today && guard++ < 600) {
      runDate = Recurring.advanceDate(runDate, rule.freq, rule.interval);
    }
    await update(rule.copyWith(nextRunDate: runDate));
  }

  /// 当前账单日（补记要它算归属期）。
  Future<int> cycleStartDay() => const SettingRepo().cycleStartDay();
}
