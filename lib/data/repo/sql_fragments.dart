import '../models/models.dart';

/// SQL 片段：**交叉归集 / 借贷排除 / 分类连带 / keyset 分页 / 搜索转义**。
///
/// 全项目只有这一份。原版把排除条件写在「各查询的 WHERE」里，后来新加的一个
/// 只用 SUM 表达式、不复用 WHERE 的查询就漏掉了，某个月的支出因此虚高。
///
/// ★ 约定：所有用到本文件聚合片段的查询，必须把 `txn` 别名成 **`t`**
///   （片段里写的是 `t.xxx`），否则 `no such column`。
abstract final class SqlFragments {
  /// 借贷流水不是收支：借出去的钱不是消费，收回来的也不是收入。
  static const String excludeDebt = 't.debt_id IS NULL';

  /// 支出侧合计（交叉归集：支出里的负数算收入侧）。
  ///
  /// **排除借贷写进表达式本身**，而不是只写在 WHERE —— 前者保证「谁能用上
  /// 这个合计，就一定带着排除」。
  static final String expSum =
      'COALESCE(SUM(CASE '
      '  WHEN t.debt_id IS NOT NULL THEN 0 '
      "  WHEN t.type = '${TxnType.expense.code}' AND t.amount_cents >= 0 "
      '    THEN t.amount_cents '
      "  WHEN t.type = '${TxnType.income.code}' AND t.amount_cents < 0 "
      '    THEN -t.amount_cents '
      '  ELSE 0 END), 0)';

  /// 收入侧合计（同上，方向相反）。
  static final String incSum =
      'COALESCE(SUM(CASE '
      '  WHEN t.debt_id IS NOT NULL THEN 0 '
      "  WHEN t.type = '${TxnType.income.code}' AND t.amount_cents >= 0 "
      '    THEN t.amount_cents '
      "  WHEN t.type = '${TxnType.expense.code}' AND t.amount_cents < 0 "
      '    THEN -t.amount_cents '
      '  ELSE 0 END), 0)';

  /// 笔数（借贷**算**笔数：用户要在列表里看到它，只是不算金额）。
  static const String countAll = 'COUNT(*)';

  /// 分类连带子分类：`(t.category_id = ? OR t.category_id IN (子分类))`。
  ///
  /// 绑两个参数（同一个分类 id 两遍）。记到「正餐」必须能算进「餐饮」。
  static String catScopeWithChildren(String column) =>
      '($column = ? OR $column IN (SELECT id FROM category WHERE parent_id = ?))';

  /// 筛选态的时间范围按**真实日期**（`t.date`），不是归属期。
  static const String dateRangeWhere =
      'AND t.date >= ? AND t.date <= ?';

  /// keyset 分页的排序（**永远带上 id**：同一天多笔时靠它保证稳定）。
  static const String keysetOrder = 'ORDER BY t.date DESC, t.id DESC';

  /// keyset 分页的游标条件（绑 3 个参数：date、date、id）。
  ///
  /// 不用 `OFFSET`：翻到第 20 页时 offset 要先扫过前 19 页的行（§8.1）。
  static const String keysetWhere = 'AND (t.date < ? OR (t.date = ? AND t.id < ?))';

  /// 明细列表的上限（搜索也一样）。**合计不受限**（独立聚合 SQL）。
  static const int pageSize = 50;
  static const int searchLimit = 500;

  /// LIKE 的转义子句（所有 `LIKE` 都必须带上它）。
  static const String likeEscapeClause = "ESCAPE '\\'";

  /// 关键词转义：**反斜杠必须先转**，否则 `\%` 会被二次转义成 `\\%`。
  static String escapeLike(String keyword) => keyword
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  /// 关键词 → `LIKE` 的绑定值。
  static String likeParam(String keyword) => '%${escapeLike(keyword)}%';

  /// 关键词要搜的文本列（备注之外还要带详情字段：记了「红包 · 对象=张三」
  /// 却搜不到「张三」，那个字段等于白填）。
  static const List<String> keywordColumns = <String>[
    't.note',
    't.person',
    't.subject',
    't.place_from',
    't.place_to',
  ];

  /// 文本列 OR 分类名（含父分类名）OR 账户名（转出 + 转入）的匹配片段。
  ///
  /// 参数顺序与 [keywordColumns] 一致，末尾再绑 1 个（金额）—— 金额是否参与
  /// 由 [isAmountKeyword] 决定，调用方自己拼。
  static String keywordWhere() {
    final StringBuffer buf = StringBuffer('(');
    for (int i = 0; i < keywordColumns.length; i++) {
      if (i > 0) buf.write(' OR ');
      buf.write('${keywordColumns[i]} LIKE ? $likeEscapeClause');
    }
    buf.write(
      ' OR t.category_id IN ('
      'SELECT c.id FROM category c '
      'LEFT JOIN category p ON p.id = c.parent_id '
      'WHERE c.name LIKE ? $likeEscapeClause '
      '   OR p.name LIKE ? $likeEscapeClause)',
    );
    buf.write(
      ' OR t.account_id IN (SELECT id FROM account WHERE name LIKE ? '
      '$likeEscapeClause)',
    );
    buf.write(
      ' OR t.to_account_id IN (SELECT id FROM account WHERE name LIKE ? '
      '$likeEscapeClause)',
    );
    buf.write(')');
    return buf.toString();
  }

  /// 关键词是否该当金额匹配：`^\d+(\.\d{1,2})?$` 且**数字位 ≥ 2**。
  ///
  /// 「5」几乎能匹配全部记录，噪音会盖掉真正命中的那几条 —— 这是用户提的。
  static final RegExp _amountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

  static bool isAmountKeyword(String keyword) {
    final String k = keyword.trim();
    if (!_amountPattern.hasMatch(k)) return false;
    final String digits = k.replaceAll('.', '');
    return digits.length >= 2;
  }

  /// 金额匹配用的「数字串」（去掉小数点）：`38.5` → `385`。
  ///
  /// 匹配的是 `CAST(amount_cents AS TEXT)`，所以 `385` 会命中 38.50（3850）、
  /// 138.50（13850）与 3.85（385）—— 用户记不清准确金额时要的就是包含关系。
  static String amountDigits(String keyword) =>
      keyword.trim().replaceAll('.', '');

  /// 金额匹配片段（绑定值用 `%${amountDigits}%`）。
  static const String amountWhere =
      'CAST(ABS(t.amount_cents) AS TEXT) LIKE ? $likeEscapeClause';
}
