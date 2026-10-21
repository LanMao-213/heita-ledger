import 'package:sqflite/sqflite.dart';

import '../../core/local_date.dart';
import '../../core/period.dart';
import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';
import 'account_repo.dart';
import 'txn_repo.dart';

/// 往来 CRUD + 还款 + 已还索引。
///
/// ★ 三个铁律：
/// 1. 本金与还款**都是流水**（挂 `debt_id`），所以「已还」永远能重算；
/// 2. 还款超过剩余 → `ArgumentError`（面板与数据层同一条规则）；
/// 3. 删往来 = 回滚余额 + 删流水 + 删 debt，**一个事务**。
class DebtRepo {
  const DebtRepo();

  Future<List<Debt>> all(int ledgerId, {bool includeClosed = true}) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.debt,
      where: includeClosed
          ? '${DebtCols.ledgerId} = ?'
          : '${DebtCols.ledgerId} = ? AND ${DebtCols.closedAt} IS NULL',
      whereArgs: <Object?>[ledgerId],
      orderBy: '${DebtCols.closedAt} IS NOT NULL, '
          '${DebtCols.dueDate} IS NULL, ${DebtCols.dueDate} ASC, '
          '${DebtCols.id} DESC',
    );
    return rows.map(Debt.fromMap).toList();
  }

  Future<Debt?> byId(int id) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.debt,
      where: '${DebtCols.id} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Debt.fromMap(rows.first);
  }

  /// 已还索引：一条 `GROUP BY debt_id, type` 查回全部，不在内存里遍历整本账。
  Future<RepaidIndex> repaidIndex(int ledgerId) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT t.${TxnCols.debtId} AS did, t.${TxnCols.type} AS ty, '
      'COALESCE(SUM(t.${TxnCols.amountCents}), 0) AS s '
      'FROM ${Tables.txn} t '
      'WHERE t.${TxnCols.ledgerId} = ? AND t.${TxnCols.debtId} IS NOT NULL '
      'GROUP BY t.${TxnCols.debtId}, t.${TxnCols.type}',
      <Object?>[ledgerId],
    );
    final Map<int, int> income = <int, int>{};
    final Map<int, int> expense = <int, int>{};
    for (final Map<String, Object?> r in rows) {
      final int id = asInt(r['did']);
      final int sum = asInt(r['s']);
      if (asString(r['ty']) == TxnType.income.code) {
        income[id] = sum;
      } else if (asString(r['ty']) == TxnType.expense.code) {
        expense[id] = sum;
      }
    }
    return RepaidIndex.fromSums(income: income, expense: expense);
  }

  /// 记一笔借贷：`debt` + 本金流水 + 余额，**同一事务**。
  ///
  /// 本金流水方向：借出 = `expense`、借入 = `income`。
  /// 借出的 `count_in_budget` **强制 0**（借出去的钱不是消费）。
  Future<int> createDebt({
    required Debt draft,
    required int cycleStartDay,
    DatabaseExecutor? ex,
  }) async {
    Future<int> run(DatabaseExecutor db) async {
      final Debt fixed = draft.copyWith(
        countInBudget: draft.isReceivable ? false : draft.countInBudget,
      );
      final int debtId = await db.insert(Tables.debt, fixed.toMap());

      final LocalDate periodStart = Period.periodStartOf(
        fixed.date,
        cycleStartDay,
      );
      final Txn principal = Txn(
        ledgerId: fixed.ledgerId,
        type: fixed.isReceivable ? TxnType.expense : TxnType.income,
        amountCents: fixed.amountCents,
        accountId: fixed.accountId,
        date: fixed.date,
        periodStart: periodStart,
        note: fixed.note,
        person: fixed.counterparty,
        debtId: debtId,
        createdAt: DateTime.now(),
      );
      await db.insert(Tables.txn, principal.toMap());
      await const AccountRepo().applyBalanceDelta(db, principal);
      return debtId;
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  /// 还一笔（或收回一笔）。返回更新后的 debt。
  ///
  /// 还款方向：借出（应收）收回 → `income`；借入（应付）还钱 → `expense`。
  /// 还满 → 同事务写 `closed_at`；**超过剩余 → [ArgumentError]**。
  Future<Debt> repay({
    required Debt debt,
    required int amountCents,
    required int cycleStartDay,
    LocalDate? date,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', '还款金额必须大于 0');
    }
    final int debtId = debt.id!;
    final RepaidIndex index = RepaidIndex.fromTxns(
      await const TxnRepo().byDebt(debtId),
    );
    final int remaining = debt.remainingCents(index);
    if (remaining <= 0) {
      throw ArgumentError('这笔往来已经结清，不用再还');
    }
    if (amountCents > remaining) {
      throw ArgumentError('不能超过剩余 ${remaining ~/ 100} 元');
    }

    final LocalDate when = date ?? LocalDate.today();
    await Db.transaction((Transaction txn) async {
      final Txn flow = Txn(
        ledgerId: debt.ledgerId,
        type: debt.isReceivable ? TxnType.income : TxnType.expense,
        amountCents: amountCents,
        accountId: debt.accountId,
        date: when,
        periodStart: Period.periodStartOf(when, cycleStartDay),
        note: debt.counterparty,
        person: debt.counterparty,
        debtId: debtId,
        createdAt: DateTime.now(),
      );
      await txn.insert(Tables.txn, flow.toMap());
      await const AccountRepo().applyBalanceDelta(txn, flow);

      if (amountCents >= remaining) {
        await txn.update(
          Tables.debt,
          <String, Object?>{DebtCols.closedAt: DateTime.now().toIso8601String()},
          where: '${DebtCols.id} = ?',
          whereArgs: <Object?>[debtId],
        );
      }
    });

    return (await byId(debtId))!;
  }

  /// 手动结清 / 撤销结清：**只动 `closed_at`**，不动流水与余额。
  Future<void> setClosed(int id, bool closed) async {
    final Database db = await Db.open();
    await db.update(
      Tables.debt,
      <String, Object?>{
        DebtCols.closedAt: closed ? DateTime.now().toIso8601String() : null,
      },
      where: '${DebtCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 删往来：回滚每笔流水的余额影响 → 删流水 → 删 debt（同一事务）。
  Future<void> deleteDebt(int id) async {
    await Db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        Tables.txn,
        where: '${TxnCols.debtId} = ?',
        whereArgs: <Object?>[id],
      );
      for (final Map<String, Object?> row in rows) {
        final Txn t = Txn.fromMap(row);
        await const AccountRepo().applyBalanceDelta(txn, t, reverse: true);
        await txn.delete(
          Tables.txn,
          where: '${TxnCols.id} = ?',
          whereArgs: <Object?>[t.id],
        );
      }
      await txn.delete(
        Tables.debt,
        where: '${DebtCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  /// 当前账本的应收 / 应付合计（用已还索引，避免 N+1）。
  Future<({int receivable, int payable})> totals(int ledgerId) async {
    final List<Debt> debts = await all(ledgerId, includeClosed: false);
    final RepaidIndex index = await repaidIndex(ledgerId);
    int receivable = 0;
    int payable = 0;
    for (final Debt d in debts) {
      if (d.isReceivable) {
        receivable += d.remainingCents(index);
      } else {
        payable += d.remainingCents(index);
      }
    }
    return (receivable: receivable, payable: payable);
  }
}
