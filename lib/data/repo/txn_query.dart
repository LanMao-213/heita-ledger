import '../../core/local_date.dart';
import '../models/models.dart';
import 'sql_fragments.dart';

/// 明细筛选条件。**字段为 null = 这一项没设**。
///
/// 刻意不提供 `copyWith + clearXxx` 那套：「清空筛选」是整体动作，逐项清空
/// 只会让状态多出十几种组合。
///
/// 为什么单独一个文件：`txn_repo.dart` 有 250 行硬上限（架构设计 §2.1），
/// 把「条件对象 + 结果对象」拆出来是唯一不删注释的办法。
class TxnQuery {
  const TxnQuery({
    this.keyword,
    this.type,
    this.categoryId,
    this.accountId,
    this.from,
    this.to,
    this.minCents,
    this.maxCents,
  });

  /// 关键词（备注/详情字段/分类名/账户名/金额）。
  final String? keyword;

  /// 类型；`null` = 不限。
  final TxnType? type;

  /// 一级分类 id（**连带子分类**）；`null` = 不限。
  final int? categoryId;

  /// 账户 id（转账两端都算）。
  final int? accountId;

  /// 真实日期区间（不是 `period_start`）。
  final LocalDate? from;
  final LocalDate? to;

  final int? minCents;
  final int? maxCents;

  /// 空条件 == 未筛选（明细页据此切「本期 / 全部历史」两种口径）。
  bool get isEmpty =>
      (keyword ?? '').trim().isEmpty &&
      type == null &&
      categoryId == null &&
      accountId == null &&
      from == null &&
      to == null &&
      minCents == null &&
      maxCents == null;

  /// 条件 → WHERE 子句 + 绑定参数（**唯一**拼装处，合计与列表共用）。
  ({String sql, List<Object?> args}) toWhere(int ledgerId) {
    final StringBuffer sql = StringBuffer('WHERE t.ledger_id = ?');
    final List<Object?> args = <Object?>[ledgerId];

    if (type != null) {
      sql.write(' AND t.type = ?');
      args.add(type!.code);
    }
    if (categoryId != null) {
      sql.write(' AND ${SqlFragments.catScopeWithChildren('t.category_id')}');
      args..add(categoryId)..add(categoryId);
    }
    if (accountId != null) {
      sql.write(' AND (t.account_id = ? OR t.to_account_id = ?)');
      args..add(accountId)..add(accountId);
    }
    if (from != null) {
      sql.write(' AND t.date >= ?');
      args.add(from!.iso);
    }
    if (to != null) {
      sql.write(' AND t.date <= ?');
      args.add(to!.iso);
    }
    if (minCents != null) {
      sql.write(' AND t.amount_cents >= ?');
      args.add(minCents);
    }
    if (maxCents != null) {
      sql.write(' AND t.amount_cents <= ?');
      args.add(maxCents);
    }

    final String keyword = (this.keyword ?? '').trim();
    if (keyword.isNotEmpty) {
      final String param = SqlFragments.likeParam(keyword);
      final bool amount = SqlFragments.isAmountKeyword(keyword);
      // 文本 / 分类名 / 账户名 **OR** 金额：关键词命中任意一处都算（口径 3.9）
      sql.write(' AND (');
      sql.write(SqlFragments.keywordWhere());
      // 顺序与 keywordWhere 的占位一致：5 个文本列 + 分类名 + 父分类名 + 两个账户名
      for (int i = 0; i < 9; i++) {
        args.add(param);
      }
      if (amount) {
        sql.write(' OR ${SqlFragments.amountWhere}');
        args.add(SqlFragments.likeParam(SqlFragments.amountDigits(keyword)));
      }
      sql.write(')');
    }

    return (sql: sql.toString(), args: args);
  }
}

/// 搜索/筛选结果。**列表有上限，合计没有**（口径 3.7 / D20）。
class TxnSearchResult {
  const TxnSearchResult({
    required this.items,
    required this.truncated,
    required this.totals,
  });

  final List<Txn> items;

  /// 是否被 [SqlFragments.searchLimit] 截断（多查一条判定）。
  final bool truncated;

  /// 全量合计（不受列表上限影响）。
  final RangeTotals totals;
}
