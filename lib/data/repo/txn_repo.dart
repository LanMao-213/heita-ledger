import 'package:sqflite/sqflite.dart';

import '../../core/local_date.dart';
import '../../core/period.dart';
import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';
import 'account_repo.dart';
import 'sql_fragments.dart';
import 'txn_query.dart';

export 'txn_query.dart';

/// keyset 分页游标（上一页最后一行的 `date` + `id`）。
class TxnCursor {
  const TxnCursor({required this.date, required this.id});

  final LocalDate date;
  final int id;
}

/// 流水 CRUD + keyset 分页 + 搜索。
class TxnRepo {
  const TxnRepo();

  /// 插入一条流水，并维护账户余额（同一事务）。
  ///
  /// [touchTemplate] 为真时顺手 `use_count + 1`。
  Future<int> insert(
    Txn txn, {
    DatabaseExecutor? ex,
    bool touchTemplate = false,
  }) async {
    Future<int> run(DatabaseExecutor db) async {
      final int id = await db.insert(Tables.txn, txn.toMap());
      await const AccountRepo().applyBalanceDelta(db, txn);
      if (touchTemplate && txn.templateId != null) {
        await db.rawUpdate(
          'UPDATE ${Tables.txnTemplate} SET ${TemplateCols.useCount} = '
          '${TemplateCols.useCount} + 1, ${TemplateCols.lastUsedAt} = ? '
          'WHERE ${TemplateCols.id} = ?',
          <Object?>[DateTime.now().toIso8601String(), txn.templateId],
        );
      }
      return id;
    }

    if (ex != null) return run(ex);
    return Db.transaction(run);
  }

  /// 改一笔：先反向回滚旧值的余额影响，再写新值并应用新影响。
  Future<void> update(
    Txn before,
    Txn after, {
    DatabaseExecutor? ex,
  }) async {
    Future<void> run(DatabaseExecutor db) async {
      await const AccountRepo().applyBalanceDelta(db, before, reverse: true);
      await db.update(
        Tables.txn,
        after.toMap()..remove(TxnCols.id),
        where: '${TxnCols.id} = ?',
        whereArgs: <Object?>[before.id],
      );
      await const AccountRepo().applyBalanceDelta(db, after);
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 删一笔：先回滚余额影响，再删行。
  Future<void> delete(Txn txn, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor db) async {
      await const AccountRepo().applyBalanceDelta(db, txn, reverse: true);
      await db.delete(
        Tables.txn,
        where: '${TxnCols.id} = ?',
        whereArgs: <Object?>[txn.id],
      );
    }

    if (ex != null) return run(ex);
    await Db.transaction(run);
  }

  /// 当期第一页/下一页（keyset，**不用 OFFSET**）。
  Future<List<Txn>> pageByPeriod({
    required int ledgerId,
    required Period period,
    TxnCursor? after,
    int limit = SqlFragments.pageSize,
  }) {
    return _page(
      ledgerId: ledgerId,
      extraWhere: 'AND t.period_start >= ? AND t.period_start <= ?',
      extraArgs: <Object?>[period.fromIso, period.toIso],
      after: after,
      limit: limit,
    );
  }

  Future<List<Txn>> _page({
    required int ledgerId,
    required String extraWhere,
    required List<Object?> extraArgs,
    TxnCursor? after,
    required int limit,
  }) async {
    final Database db = await Db.open();
    final StringBuffer sb = StringBuffer()
      ..write('SELECT t.* FROM ${Tables.txn} t WHERE t.ledger_id = ? ')
      ..write(extraWhere);
    final List<Object?> args = <Object?>[ledgerId, ...extraArgs];
    if (after != null) {
      sb.write(' ${SqlFragments.keysetWhere}');
      args.addAll(<Object?>[after.date.iso, after.date.iso, after.id]);
    }
    sb.write(' ${SqlFragments.keysetOrder} LIMIT ?');
    args.add(limit);
    final List<Map<String, Object?>> rows = await db.rawQuery(sb.toString(), args);
    return rows.map(Txn.fromMap).toList();
  }

  /// 当期合计（交叉归集 + 排除借贷）。
  Future<RangeTotals> totalsInPeriod({
    required int ledgerId,
    required Period period,
  }) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT ${SqlFragments.expSum} AS exp, ${SqlFragments.incSum} AS inc, '
      '${SqlFragments.countAll} AS n FROM ${Tables.txn} t '
      'WHERE t.ledger_id = ? AND t.period_start >= ? AND t.period_start <= ?',
      <Object?>[ledgerId, period.fromIso, period.toIso],
    );
    return _totalsOf(rows);
  }

  /// 筛选/搜索：**跨全部历史**（不带期），列表 500 上限，合计不限。
  Future<TxnSearchResult> search({
    required int ledgerId,
    required TxnQuery query,
    int limit = SqlFragments.searchLimit,
  }) async {
    final Database db = await Db.open();
    final ({String sql, List<Object?> args}) where = query.toWhere(ledgerId);

    final String orderAndLimit =
        ' ${SqlFragments.keysetOrder} LIMIT ${limit + 1}';

    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT t.* FROM ${Tables.txn} t ${where.sql}$orderAndLimit',
      where.args,
    );
    final bool truncated = rows.length > limit;
    final List<Txn> items = <Txn>[
      for (final Map<String, Object?> r in rows.take(limit)) Txn.fromMap(r),
    ];

    final List<Map<String, Object?>> agg = await db.rawQuery(
      'SELECT ${SqlFragments.expSum} AS exp, ${SqlFragments.incSum} AS inc, '
      '${SqlFragments.countAll} AS n FROM ${Tables.txn} t ${where.sql}',
      where.args,
    );

    return TxnSearchResult(
      items: items,
      truncated: truncated,
      totals: _totalsOf(agg),
    );
  }

  static RangeTotals _totalsOf(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return RangeTotals.zero;
    final Map<String, Object?> r = rows.first;
    return RangeTotals(
      expenseCents: asInt(r['exp']),
      incomeCents: asInt(r['inc']),
      count: asInt(r['n']),
    );
  }

  /// 某笔借贷挂着的全部流水（本金 + 还款），算 `RepaidIndex` 用。
  Future<List<Txn>> byDebt(int debtId) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.txn,
      where: '${TxnCols.debtId} = ?',
      whereArgs: <Object?>[debtId],
      orderBy: '${TxnCols.date} ASC, ${TxnCols.id} ASC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// 当前账本全部流水（体检/导出用，非分页路径）。
  Future<List<Txn>> allOfLedger(int ledgerId) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.query(
      Tables.txn,
      where: '${TxnCols.ledgerId} = ?',
      whereArgs: <Object?>[ledgerId],
      orderBy: '${TxnCols.date} ASC, ${TxnCols.id} ASC',
    );
    return rows.map(Txn.fromMap).toList();
  }
}
