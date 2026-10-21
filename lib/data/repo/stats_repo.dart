import 'package:sqflite/sqflite.dart';

import '../../core/period.dart';
import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';
import 'sql_fragments.dart';

/// 一级分类的金额汇总（饼图 / 排行）。
class CategoryStat {
  const CategoryStat({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.cents,
  });

  final int categoryId;
  final String name;
  final String icon;

  /// **绝对值**（口径 3.15：有退款/净额负数的分类不该变成负扇区）。
  final int cents;
}

/// 某一天的合计（每日柱 / 趋势）。
class DailyTotal {
  const DailyTotal({required this.date, required this.expenseCents, required this.incomeCents});

  final String date;
  final int expenseCents;
  final int incomeCents;
}

/// 近 6 段双柱里的一段（一段 = 一个归属期）。
class TrendSegment {
  const TrendSegment({
    required this.period,
    required this.expenseCents,
    required this.incomeCents,
  });

  final Period period;
  final int expenseCents;
  final int incomeCents;

  /// 轴上那一格的字：`9月`（期首月，账单日 15 时 10-15 期写「10月」）。
  String get label => '${period.from.month}月';
}

/// 把「有数据的那几天」补成「区间内每一天一格」。
///
/// 每日柱的判据是「无数据的那天也占一格」——直接拿 SQL 结果画图会让
/// 1 号下一个柱子跳到 8 号，看着像那几天被吞了。补齐是纯函数，不碰数据库。
List<DailyTotal> fillDailyRange({
  required Period period,
  required List<DailyTotal> rows,
}) {
  final Map<String, DailyTotal> byDate = <String, DailyTotal>{
    for (final DailyTotal r in rows) r.date: r,
  };
  final List<DailyTotal> out = <DailyTotal>[];
  for (int i = 0; i < period.dayCount; i++) {
    final String iso = period.from.addDays(i).iso;
    out.add(
      byDate[iso] ??
          DailyTotal(date: iso, expenseCents: 0, incomeCents: 0),
    );
  }
  return out;
}

/// 只读聚合。**交叉归集 / 借贷排除全部复用 [SqlFragments]**，不另写一套。
class StatsRepo {
  const StatsRepo();

  /// 任意日期区间的两侧合计（按 `t.date`，不是归属期）。
  Future<RangeTotals> rangeTotals({
    required int ledgerId,
    required String from,
    required String to,
  }) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT ${SqlFragments.expSum} AS exp, ${SqlFragments.incSum} AS inc, '
      '${SqlFragments.countAll} AS n FROM ${Tables.txn} t '
      'WHERE t.ledger_id = ? AND t.date >= ? AND t.date <= ?',
      <Object?>[ledgerId, from, to],
    );
    return _totals(rows);
  }

  /// 按归属期的合计（明细概览卡 / 预算已用）。
  Future<RangeTotals> periodTotals({
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
    return _totals(rows);
  }

  static RangeTotals _totals(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return RangeTotals.zero;
    final Map<String, Object?> r = rows.first;
    return RangeTotals(
      expenseCents: asInt(r['exp']),
      incomeCents: asInt(r['inc']),
      count: asInt(r['n']),
    );
  }

  /// 分类聚合：**归到一级**、支出取绝对值、只算该类型、排除借贷、排除停用分类。
  Future<List<CategoryStat>> categoryStats({
    required int ledgerId,
    required String from,
    required String to,
    TxnType type = TxnType.expense,
  }) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT root.${CategoryCols.id} AS cid, '
      'root.${CategoryCols.name} AS cname, '
      'root.${CategoryCols.icon} AS cicon, '
      'COALESCE(SUM(ABS(t.amount_cents)), 0) AS total '
      'FROM ${Tables.txn} t '
      'JOIN ${Tables.category} c ON c.${CategoryCols.id} = t.category_id '
      'JOIN ${Tables.category} root '
      '  ON root.${CategoryCols.id} = COALESCE(c.${CategoryCols.parentId}, c.${CategoryCols.id}) '
      'WHERE t.ledger_id = ? AND t.type = ? '
      '  AND t.date >= ? AND t.date <= ? '
      '  AND ${SqlFragments.excludeDebt} '
      '  AND root.${CategoryCols.archived} = 0 '
      'GROUP BY root.${CategoryCols.id} '
      'ORDER BY total DESC, root.${CategoryCols.sortOrder} ASC',
      <Object?>[ledgerId, type.code, from, to],
    );
    return <CategoryStat>[
      for (final Map<String, Object?> r in rows)
        CategoryStat(
          categoryId: asInt(r['cid']),
          name: asString(r['cname']),
          icon: asString(r['cicon'], 'more'),
          cents: asInt(r['total']),
        ),
    ];
  }

  /// 每日合计：**按 `date` 分组**（筛选仍按归属期，只有分组用真实日期）。
  Future<List<DailyTotal>> dailyTotals({
    required int ledgerId,
    required String from,
    required String to,
  }) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT t.date AS d, ${SqlFragments.expSum} AS exp, '
      '${SqlFragments.incSum} AS inc FROM ${Tables.txn} t '
      'WHERE t.ledger_id = ? AND t.date >= ? AND t.date <= ? '
      'GROUP BY t.date ORDER BY t.date ASC',
      <Object?>[ledgerId, from, to],
    );
    return <DailyTotal>[
      for (final Map<String, Object?> r in rows)
        DailyTotal(
          date: asString(r['d']),
          expenseCents: asInt(r['exp']),
          incomeCents: asInt(r['inc']),
        ),
    ];
  }

  /// 近 6 段双柱：**1 条合并查询**（按 `period_start` 分组，回来再分桶）。
  ///
  /// 为什么强调一条：一天一段地查就是 6 次 IO，6 张图叠在首屏就是肉眼可见的
  /// 卡顿；而且 6 次查询之间数据可能已经变了，同屏两个数字对不上。
  ///
  /// [periods] 必须**按时间升序**且连续。没数据的段补 0（零值不画柱）。
  /// 「查了几条 SQL」由 [lastTrendQueryCount] 自报，测试拿它做上限断言。
  Future<List<TrendSegment>> trendTotals({
    required int ledgerId,
    required List<Period> periods,
  }) async {
    lastTrendQueryCount = 0;
    if (periods.isEmpty) return <TrendSegment>[];
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT t.period_start AS ps, ${SqlFragments.expSum} AS exp, '
      '${SqlFragments.incSum} AS inc FROM ${Tables.txn} t '
      'WHERE t.ledger_id = ? AND t.period_start >= ? AND t.period_start <= ? '
      'GROUP BY t.period_start ORDER BY ps ASC',
      <Object?>[ledgerId, periods.first.fromIso, periods.last.toIso],
    );
    lastTrendQueryCount = 1;

    final Map<String, ({int exp, int inc})> byPeriod =
        <String, ({int exp, int inc})>{};
    for (final Map<String, Object?> r in rows) {
      byPeriod[asString(r['ps'])] = (
        exp: asInt(r['exp']),
        inc: asInt(r['inc']),
      );
    }

    return <TrendSegment>[
      for (final Period p in periods)
        TrendSegment(
          period: p,
          expenseCents: byPeriod[p.fromIso]?.exp ?? 0,
          incomeCents: byPeriod[p.fromIso]?.inc ?? 0,
        ),
    ];
  }

  /// 上一次 [trendTotals] 发了几条 SQL（判据「逐段数据由 1 条合并查询取得」）。
  ///
  /// 说明：这是**自报**的计数（sqflite 没有全局钩子可以拦截），只挡得住
  /// 「有人把合并查询改回 per-period 循环并且顺手加了自己的计数」以外的场景；
  /// 真正的护栏是 [trendTotals] 只有一条 `rawQuery`，改回循环时这个数字会变。
  static int lastTrendQueryCount = 0;

  /// 账户资产合计（只算 `include_in_total = 1`）。
  Future<int> accountAssets() async {    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(SUM(${AccountCols.balanceCents}), 0) AS s '
      'FROM ${Tables.account} WHERE ${AccountCols.includeInTotal} = 1',
    );
    if (rows.isEmpty) return 0;
    return asInt(rows.first['s']);
  }

  /// 本期计入预算的借入合计（只抬可用额度，不改额度本身）。
  Future<int> borrowedInBudget({
    required int ledgerId,
    required Period period,
  }) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(SUM(${DebtCols.amountCents}), 0) AS s '
      'FROM ${Tables.debt} WHERE ${DebtCols.ledgerId} = ? '
      "  AND ${DebtCols.direction} = '${DebtDirection.in_.code}' "
      '  AND ${DebtCols.countInBudget} = 1 '
      '  AND ${DebtCols.closedAt} IS NULL '
      '  AND ${DebtCols.date} >= ? AND ${DebtCols.date} <= ?',
      <Object?>[ledgerId, period.fromIso, period.toIso],
    );
    if (rows.isEmpty) return 0;
    return asInt(rows.first['s']);
  }

  /// 某账户的余额与恒等式是否一致（体检 / 测试用）。
  Future<bool> balanceMatches(int accountId) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT ${AccountCols.balanceCents} AS b, ${AccountCols.openingCents} AS o '
      'FROM ${Tables.account} WHERE ${AccountCols.id} = ?',
      <Object?>[accountId],
    );
    if (rows.isEmpty) return false;
    final int balance = asInt(rows.first['b']);
    final int opening = asInt(rows.first['o']);
    final List<Map<String, Object?>> flow = await db.rawQuery(
      'SELECT COALESCE(SUM(CASE '
      "  WHEN t.type = 'transfer' AND t.account_id = ? THEN -t.amount_cents "
      "  WHEN t.type = 'transfer' AND t.to_account_id = ? THEN t.amount_cents "
      "  WHEN t.type = 'income' AND t.account_id = ? THEN t.amount_cents "
      "  WHEN t.type = 'expense' AND t.account_id = ? THEN -t.amount_cents "
      '  ELSE 0 END), 0) AS delta FROM ${Tables.txn} t '
      'WHERE t.account_id = ? OR t.to_account_id = ?',
      <Object?>[accountId, accountId, accountId, accountId, accountId, accountId],
    );
    final int delta = flow.isEmpty ? 0 : asInt(flow.first['delta']);
    return balance == opening + delta;
  }

  /// 高频 SQL 的执行计划（测试用它断言「没有 SCAN TABLE txn」）。
  Future<List<String>> explain(String sql, [List<Object?> args = const <Object?>[]]) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
    return <String>[
      for (final Map<String, Object?> r in rows) asString(r['detail']),
    ];
  }

  /// 一段时间内有数据的月份（月份选择器的提示点）。
  Future<List<String>> monthsWithData(int ledgerId) async {
    final Database db = await Db.open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT DISTINCT substr(t.date, 1, 7) AS ym FROM ${Tables.txn} t '
      'WHERE t.ledger_id = ? ORDER BY ym ASC',
      <Object?>[ledgerId],
    );
    return <String>[for (final Map<String, Object?> r in rows) asString(r['ym'])];
  }
}
