/// 统计聚合：收支合计、分类聚合、每日趋势、预算执行。
///
/// 从 `repo.dart` 拆出来的原因：这一段是**口径最容易被改动**的地方，
/// 而它原先混在 2000 多行的文件里，改一次得翻很久。拆成独立文件之后，
/// 「改统计口径」只需要打开这一个（外加 `sql_fragments.dart`）——
/// 边界落在文件上，而不是落在记忆里。
///
/// 三条纪律：
/// 1. **只读**：这里不写库，也就不可能破坏「余额 = 期初 + 流水」恒等式。
/// 2. **口径优先复用 [kExpSumSql] / [kIncSumSql]**。自己拼 SUM 的只有两处
///    （分类聚合、每日趋势），因为要按维度分组；改口径时那两处必须一起改。
/// 3. **借贷一律不计入收支**：借出去不是消费，收回来的也不是收入。
library;

import 'cycle.dart';
import 'db.dart';
import 'models.dart';
import 'sql_fragments.dart';

abstract final class RepoStats {
  RepoStats._();

  // -------------------------------------------------------------- 收支合计

  /// 月收支合计。
  ///
  /// 阶段 3 起只是 [rangeTotals] 的薄委托：`month` 折算成月初/月末。账单日
  /// 默认 1 时 `period_start` 就是月初，结果与按 `date` 查完全一致。
  static Future<(int expense, int income, int count)> monthTotals(
    int ledgerId,
    String month,
  ) => rangeTotals(ledgerId, Fmt.monthStart(month), Fmt.monthEnd(month));

  /// 某一期的收支合计。[from] / [to] 是该期的首尾日期（含两端）。
  ///
  /// 条件打在 **`period_start`** 上，不是 `date` —— 这是周期归集的口径：
  /// 10-10 到账的工资被抬进 10-15 那一期后，就该算在那一期里。
  static Future<(int expense, int income, int count)> rangeTotals(
    int ledgerId,
    String from,
    String to, {
    DateBasis basis = DateBasis.period,
  }) async {
    final db = await Db.open();
    final r = await db.rawQuery(
      // 负数交叉归集：支出里的负数算进收入，收入里的负数算进支出
      'SELECT $kExpSumSql AS exp, $kIncSumSql AS inc, COUNT(*) AS cnt '
      'FROM txn WHERE ledger_id = ? AND ${kDateCol(basis)} BETWEEN ? AND ?',
      [ledgerId, from, to],
    );
    final row = r.first;
    return (
      (row['exp'] as int?) ?? 0,
      (row['inc'] as int?) ?? 0,
      (row['cnt'] as int?) ?? 0,
    );
  }

  /// 最近 [count] 个月（含 [endMonth]）的收支合计，按月升序。
  ///
  /// 统计页的「近 6 个月」用。逐月调 [monthTotals] 是有意的：
  /// 一条 GROUP BY 走 substr(date,1,7) 反而用不上索引，而这里最多 6 次、
  /// 每次都是毫秒级（实测 5000 条 1.4ms），没必要为它加复杂度。
  static Future<List<(String month, int expense, int income)>> recentMonths({
    required int ledgerId,
    required String endMonth,
    int count = 6,
  }) async {
    final y = int.parse(endMonth.substring(0, 4));
    final m = int.parse(endMonth.substring(5, 7));
    final out = <(String, int, int)>[];
    for (var i = count - 1; i >= 0; i--) {
      final d = DateTime(y, m - i);
      final ym = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final t = await rangeTotals(
        ledgerId,
        '$ym-01',
        '$ym-${Fmt.daysInMonth(d.year, d.month).toString().padLeft(2, '0')}',
        basis: DateBasis.date,
      );
      out.add((ym, t.$1, t.$2));
    }
    return out;
  }

  /// 最近 [count] 期（含 [endFrom] 那一期）的收支合计，按期升序。
  ///
  /// 统计页的「近 6 期」用。逐期调 [rangeTotals] 与 [recentMonths] 同理由：
  /// 最多 6 次、每次毫秒级，不值得为它写一条按周期分组的复杂 SQL。
  static Future<List<(String from, int expense, int income)>> recentPeriods({
    required int ledgerId,
    required String endFrom,
    required int startDay,
    int count = 6,
  }) async {
    final out = <(String, int, int)>[];
    final base = DateTime.parse(endFrom);
    for (var i = count - 1; i >= 0; i--) {
      final from = Fmt.date(shiftCycle(base, startDay, -i));
      final to = Fmt.date(
        shiftCycle(
          DateTime.parse(from),
          startDay,
          1,
        ).subtract(const Duration(days: 1)),
      );
      final t = await rangeTotals(ledgerId, from, to);
      out.add((from, t.$1, t.$2));
    }
    return out;
  }

  // -------------------------------------------------------------- 分类聚合

  /// 分类聚合（饼图 / 排行）。结果按金额降序，直接对应灰阶由深到浅。
  static Future<List<CatStat>> categoryStats({
    required int ledgerId,
    required String month,
    required TxnType type,
  }) => rangeCategoryStats(
    ledgerId: ledgerId,
    from: Fmt.monthStart(month),
    to: Fmt.monthEnd(month),
    type: type,
  );

  /// 某一期的分类聚合（[categoryStats] 的区间版）
  static Future<List<CatStat>> rangeCategoryStats({
    required int ledgerId,
    required String from,
    required String to,
    required TxnType type,
    DateBasis basis = DateBasis.period,
  }) async {
    final db = await Db.open();
    // 对侧类型：支出饼要吸收「收入里的负数」，反之亦然
    final other = type == TxnType.income ? TxnType.expense : TxnType.income;
    final rows = await db.rawQuery(
      // 本侧的正数 + 对侧的负数（金额取绝对值）—— 与 rangeTotals 的口径保持一致，
      // 否则饼图分项之和会跟合计对不上
      //
      // **按根分类聚合**：两级分类之后，交易可能挂在子分类（正餐）上，
      // 也可能直接挂一级（餐饮）。饼图与排行只按一级呈现，所以用
      // `COALESCE(p.id, c.id)` 把子分类折回它的一级；未分类时三者都空，
      // 落在同一组里显示为「未分类」。
      'SELECT COALESCE(p.id, c.id) AS cid, '
      "  COALESCE(p.name, c.name, '未分类') AS name, "
      "  COALESCE(p.icon, c.icon, 'more')  AS icon, "
      '  SUM(CASE WHEN t.amount_cents < 0 THEN -t.amount_cents'
      '          ELSE t.amount_cents END) AS total, '
      '  COUNT(*) AS cnt '
      'FROM txn t '
      '  LEFT JOIN category c ON c.id = t.category_id '
      '  LEFT JOIN category p ON p.id = c.parent_id '
      'WHERE t.ledger_id = ? AND t.${kDateCol(basis)} BETWEEN ? AND ? '
      '  AND t.debt_id IS NULL '
      '  AND ((t.type = ? AND t.amount_cents >= 0)'
      '    OR (t.type = ? AND t.amount_cents < 0)) '
      'GROUP BY COALESCE(p.id, c.id) '
      'ORDER BY total DESC',
      [ledgerId, from, to, type.code, other.code],
    );
    return rows
        .map(
          (m) => CatStat(
            categoryId: (m['cid'] as int?) ?? -1,
            name: m['name'] as String,
            icon: m['icon'] as String,
            totalCents: (m['total'] as int?) ?? 0,
            count: (m['cnt'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  // -------------------------------------------------------------- 每日趋势

  /// 每日收支（趋势图）—— 月的薄委托，见 [rangeDailyTotals]。
  static Future<List<(String date, int expense, int income)>> dailyTotals(
    int ledgerId,
    String month,
  ) => rangeDailyTotals(ledgerId, Fmt.monthStart(month), Fmt.monthEnd(month));

  /// 某一期的每日收支（趋势图）。
  ///
  /// **筛的是归属期，分组仍按真实 `date`** —— 趋势图的柱子代表「那天花了多少」，
  /// 把它挪到账单日会变成谎报。所以一笔 10-10 的工资在 10-15 那一期里，
  /// 仍然显示在 10-10 这根柱子上。
  static Future<List<(String date, int expense, int income)>> rangeDailyTotals(
    int ledgerId,
    String from,
    String to, {
    DateBasis basis = DateBasis.period,
  }) async {
    final db = await Db.open();
    final rows = await db.rawQuery(
      'SELECT date, '
      '  COALESCE(SUM(CASE '
      "    WHEN type = 'expense' AND amount_cents >= 0 THEN amount_cents "
      "    WHEN type = 'income'  AND amount_cents <  0 THEN -amount_cents "
      '    ELSE 0 END), 0) AS exp, '
      '  COALESCE(SUM(CASE '
      "    WHEN type = 'income'  AND amount_cents >= 0 THEN amount_cents "
      "    WHEN type = 'expense' AND amount_cents <  0 THEN -amount_cents "
      '    ELSE 0 END), 0) AS inc '
      'FROM txn WHERE ledger_id = ? AND ${kDateCol(basis)} BETWEEN ? AND ? '
      '  AND debt_id IS NULL '
      'GROUP BY date ORDER BY date',
      [ledgerId, from, to],
    );
    return rows
        .map(
          (m) => (
            m['date'] as String,
            (m['exp'] as int?) ?? 0,
            (m['inc'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  // -------------------------------------------------------------- 预算执行

  /// 某一期各分类的预算执行情况。
  ///
  /// 返回结果包含**设置了预算的分类**，以及**有支出但没设预算的分类**
  /// （后者 budgetCents 为 0，用于展示「未设预算」）。
  ///
  /// [periodStart] 决定读哪一期的预算；[from] / [to] 是该期的首尾日期，
  /// 支出按 `period_start` 归集 —— 与明细页的「本期支出」同口径。
  static Future<List<BudgetStat>> budgetStats({
    required int ledgerId,
    required String periodStart,
    required String from,
    required String to,
  }) async {
    final db = await Db.open();
    final rows = await db.rawQuery(
      // 只列一级分类（`parent_id IS NULL`）：预算设在「餐饮」上，
      // 不该出现「正餐」。已用金额则要**含该一级下的所有子分类**，
      // 否则把交易记到子分类之后，餐饮的预算进度条永远不动。
      //
      // ⚠️ 这里曾经用「相关子查询」按每个一级分类各算一次 SUM。那个写法有两个
      // 毛病：① `COALESCE(tc.parent_id, tc.id) = c.id` 是表达式，索引根本用不上；
      // ② 子查询里没有 `ledger_id` 条件，等于对全表扫一遍。而 `Store.loadCycle()`
      // **每记一笔都会调这个函数**，于是记一笔的代价随总笔数线性上涨。
      // 改成「先 GROUP BY 一次算完当期各一级分类的合计，再 LEFT JOIN 回分类表」，
      // 单次扫描 + 一次 join，与账本总笔数脱钩。
      'WITH spent AS ('
      '  SELECT COALESCE(tc.parent_id, tc.id) AS pid, '
      '         SUM(t.amount_cents) AS s '
      '  FROM txn t JOIN category tc ON tc.id = t.category_id '
      "  WHERE t.ledger_id = ? AND t.type = 'expense' AND t.debt_id IS NULL "
      '    AND t.period_start BETWEEN ? AND ? '
      '  GROUP BY COALESCE(tc.parent_id, tc.id)'
      ') '
      'SELECT c.id AS cid, c.name AS name, c.icon AS icon, '
      '  b.amount_cents AS budget, '
      '  COALESCE(sp.s, 0) AS spent '
      'FROM category c '
      'LEFT JOIN budget b ON b.category_id = c.id '
      '  AND b.ledger_id = c.ledger_id AND b.period_start = ? '
      'LEFT JOIN spent sp ON sp.pid = c.id '
      "WHERE c.ledger_id = ? AND c.type = 'expense' AND c.archived = 0 "
      '  AND c.parent_id IS NULL '
      '  AND (b.amount_cents IS NOT NULL OR COALESCE(sp.s, 0) > 0) '
      'ORDER BY (b.amount_cents IS NULL), b.amount_cents DESC',
      [ledgerId, from, to, periodStart, ledgerId],
    );
    return rows
        .map(
          (m) => BudgetStat(
            categoryId: (m['cid'] as int?) ?? -1,
            name: m['name'] as String,
            icon: m['icon'] as String,
            spentCents: (m['spent'] as int?) ?? 0,
            budgetCents: (m['budget'] as int?) ?? 0,
          ),
        )
        .toList();
  }
}
