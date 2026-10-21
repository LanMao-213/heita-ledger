import 'package:sqflite/sqflite.dart';

import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';

/// 账户 CRUD + 余额维护。
///
/// ★ 余额恒等式（口径 3.4 / 不变量 I1）：
///   `balance_cents == opening_cents + Σ(该账户流水影响)`
///   `opening` 只在「用户手填当前余额」时改，**任何自动流程都不许动它**。
class AccountRepo {
  const AccountRepo();

  /// 每个账户的流水影响合计（转账两端分别算）。
  ///
  /// 方向：收入 `+amt`、支出 `−amt`、转账转出 `−amt`、转入 `+amt`；
  /// **不做 ABS** —— `amount_cents` 允许为负（净额记账）。
  static const String _flowDeltaSql =
      'SELECT COALESCE(SUM(CASE '
      "  WHEN t.type = 'transfer' AND t.account_id = ? THEN -t.amount_cents "
      "  WHEN t.type = 'transfer' AND t.to_account_id = ? THEN t.amount_cents "
      "  WHEN t.type = 'income' AND t.account_id = ? THEN t.amount_cents "
      "  WHEN t.type = 'expense' AND t.account_id = ? THEN -t.amount_cents "
      '  ELSE 0 END), 0) AS delta '
      'FROM ${Tables.txn} t '
      'WHERE t.account_id = ? OR t.to_account_id = ?';

  Future<List<Account>> list() async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.account,
      orderBy: '${AccountCols.sortOrder} ASC, ${AccountCols.id} ASC',
    );
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> byId(int id) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.account,
      where: '${AccountCols.id} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Account.fromMap(rows.first);
  }

  /// 新建账户。
  ///
  /// 没有流水 → 恒等式只能是 `balance == opening`，这里**强制对齐**
  /// （用户填了「当前余额 5000」，就把它当成期初 5000）。
  Future<int> insert(Account account, {DatabaseExecutor? ex}) async {
    Future<int> run(DatabaseExecutor db) async {
      final Account aligned = account.copyWith(
        balanceCents: account.openingCents,
      );
      return db.insert(Tables.account, aligned.toMap());
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  /// 改账户属性（名称 / 类型 / 是否计入净资产）。
  ///
  /// **绝不写两列余额**：`attributesOnly()` 里没有 `opening_cents` /
  /// `balance_cents`，所以 SQL 层面就不可能误改 —— 原版 1.4.5 真机上
  /// 就是栽在「改个名字顺手把余额写回旧快照」。
  Future<void> updateAttributes(Account account, {DatabaseExecutor? ex}) async {
    final int? id = account.id;
    if (id == null) throw ArgumentError('updateAttributes 需要 id');
    final Map<String, Object?> values = account.attributesOnly()
      ..remove(AccountCols.id);
    Future<void> run(DatabaseExecutor db) async {
      await db.update(
        Tables.account,
        values,
        where: '${AccountCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 删账户：**只删这一行**，流水里的 `account_id` 变成悬空引用（有意的软关联）。
  ///
  /// 为什么不把 `account_id` 也置 NULL：置空之后余额对账就再也查不出问题
  /// （体检的「孤儿引用」正是干这个的）。
  Future<void> delete(int id, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.delete(
        Tables.account,
        where: '${AccountCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 用户手填「当前余额」：反算 `opening = 手填 − 流水合计`，并把 balance 对齐。
  ///
  /// 这是**唯一**允许改写 `opening_cents` 的入口。
  Future<void> setActualBalance(int id, int actualCents) async {
    await Db.transaction((Transaction txn) async {
      final int delta = await flowDelta(txn, id);
      await txn.update(
        Tables.account,
        <String, Object?>{
          AccountCols.openingCents: actualCents - delta,
          AccountCols.balanceCents: actualCents,
        },
        where: '${AccountCols.id} = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  /// 某账户的流水影响合计。
  Future<int> flowDelta(DatabaseExecutor db, int accountId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      _flowDeltaSql,
      <Object?>[accountId, accountId, accountId, accountId, accountId, accountId],
    );
    if (rows.isEmpty) return 0;
    return asInt(rows.first['delta']);
  }

  /// 一条流水对余额的增量（写入/回滚都用它，保证正反一致）。
  ///
  /// 转账：转出端 `−amount`、转入端 `+amount`；其他：收入 `+amount`、支出 `−amount`。
  /// 返回 `(accountId → delta)` 的成对增量（可能 0/1/2 项）。
  static List<({int accountId, int delta})> deltasOf(
    Txn txn, {
    bool reverse = false,
  }) {
    final int sign = reverse ? -1 : 1;
    if (txn.type.isTransfer) {
      return <({int accountId, int delta})>[
        if (txn.accountId != null)
          (accountId: txn.accountId!, delta: -txn.amountCents * sign),
        if (txn.toAccountId != null)
          (accountId: txn.toAccountId!, delta: txn.amountCents * sign),
      ];
    }
    final int? id = txn.accountId;
    if (id == null) return const <({int accountId, int delta})>[];
    return <({int accountId, int delta})>[
      (accountId: id, delta: txn.amountCents * Account.flowSign(txn.type) * sign),
    ];
  }

  /// 按流水增量更新 `balance_cents`（**只动 balance，不动 opening**）。
  Future<void> applyBalanceDelta(
    DatabaseExecutor db,
    Txn txn, {
    bool reverse = false,
  }) async {
    for (final ({int accountId, int delta}) d in deltasOf(txn, reverse: reverse)) {
      if (d.delta == 0) continue;
      await db.rawUpdate(
        'UPDATE ${Tables.account} SET ${AccountCols.balanceCents} = '
        '${AccountCols.balanceCents} + ? WHERE ${AccountCols.id} = ?',
        <Object?>[d.delta, d.accountId],
      );
    }
  }

  /// 重算余额（体检的「重算余额」）：`balance = opening + Σ流水`。
  ///
  /// **只改 balance，不改 opening。**
  Future<int> recalcBalances({DatabaseExecutor? ex}) async {
    Future<int> run(DatabaseExecutor db) async {
      final List<Map<String, Object?>> accounts = await db.query(
        Tables.account,
        columns: <String>[AccountCols.id, AccountCols.openingCents],
      );
      int changed = 0;
      for (final Map<String, Object?> row in accounts) {
        final int id = asInt(row[AccountCols.id]);
        final int opening = asInt(row[AccountCols.openingCents]);
        final int expected = opening + await flowDelta(db, id);
        changed += await db.rawUpdate(
          'UPDATE ${Tables.account} SET ${AccountCols.balanceCents} = ? '
          'WHERE ${AccountCols.id} = ?',
          <Object?>[expected, id],
        );
      }
      return changed;
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  /// 找出余额与恒等式不一致的账户（体检用）。
  Future<List<({Account account, int expected})>> mismatched() async {
    final Database db = await Db.open();
    final List<({Account account, int expected})> out =
        <({Account account, int expected})>[];
    for (final Account a in await list()) {
      final int delta = await flowDelta(db, a.id!);
      final int expected = a.openingCents + delta;
      if (expected != a.balanceCents) {
        out.add((account: a, expected: expected));
      }
    }
    return out;
  }
}
