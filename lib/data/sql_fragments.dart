/// 跨查询共用的 SQL 片段。
///
/// 单独成文件，是因为它们**被不同职责的查询共用**：收支合计（[kExpSumSql]）
/// 同时被「统计」（`rangeTotals` / `monthTotals`）和「筛选合计」（`sumFiltered`）
/// 使用。放在任一侧都等于让另一侧依赖它，两种归属都不对。
///
/// 更重要的是：**口径要改时只改这里一处**。这两个表达式就是「哪些流水算作
/// 收支」的唯一定义 —— 将来若加「记录级不计入统计」，条件加在这两个表达式里，
/// 五个查询同时生效，不必逐个去翻。
library;

import 'models.dart';

/// 归集口径对应的字段名：周期视图筛 `period_start`，月份视图筛 `date`。
///
/// 明细段（`rangeListTxns`）与统计段共用 —— 两边必须筛同一个字段，
/// 否则会出现「列表里 12 条、合计只有 8 条的金额」这种对不上的怪事。
String kDateCol(DateBasis basis) =>
    basis == DateBasis.period ? 'period_start' : 'date';

/// 交叉归集的求和表达式（支出侧 / 收入侧）。
///
/// 负数按交叉口径：支出里的负数算进收入，收入里的负数算进支出。
///
/// **借贷流水一律算 0**：借出去的钱不是消费，收回来的也不是收入。
/// 排除条件写在这两个表达式里而不是各查询的 WHERE —— 只写 WHERE 的话，
/// 哪天有人新加一个只用表达式、不复用 WHERE 的查询，就会漏掉。
const kExpSumSql =
    'COALESCE(SUM(CASE '
    '  WHEN debt_id IS NOT NULL THEN 0 '
    "  WHEN type = 'expense' AND amount_cents >= 0 THEN amount_cents "
    "  WHEN type = 'income'  AND amount_cents <  0 THEN -amount_cents "
    '  ELSE 0 END), 0)';

const kIncSumSql =
    'COALESCE(SUM(CASE '
    '  WHEN debt_id IS NOT NULL THEN 0 '
    "  WHEN type = 'income'  AND amount_cents >= 0 THEN amount_cents "
    "  WHEN type = 'expense' AND amount_cents <  0 THEN -amount_cents "
    '  ELSE 0 END), 0)';
