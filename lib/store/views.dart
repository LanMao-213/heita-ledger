part of '../store.dart';

/// 统计页的只读视图。
///
/// ## 为什么单独一层
///
/// 统计屏有**自己的一套游标**（口径 / 起止 / 月份）和一套结果（合计、分类聚合、
/// 每日、近 6 段）。它们和明细页的 `cycleFrom` 是两套口径 —— 账单日 15 时，
/// 10-10 的工资算「本期」还是「10 月」，答案不一样。
///
/// 以前这两套字段平铺在 `Store` 的同一个字段表里，读代码的人得靠前缀
/// （`stat*`）猜归属，写代码的人也能随手 `store.statExpenseCents = 0`。
/// 收进视图之后：
/// - **读**统一走 `store.stats.xxx`，一眼看出是统计口径；
/// - **写**只有 `Store` 自己的 `loadStats` / `setStatBasis` / `shiftStat` 能做，
///   外部没有 setter —— 「页面误写状态」在编译期就不成立。
///
/// 视图本身不缓存任何东西（每次 getter 都读 Store 的当前值），所以不存在
/// 「视图和 Store 不同步」这种新问题。
class StatsView {
  StatsView._(this._s);

  final Store _s;

  /// 归集口径：按归属期（本期）还是按自然月
  StatBasis get basis => _s._statBasis;

  /// 当前统计区间的首尾（`YYYY-MM-DD`，含两端）
  String get from => _s._statFrom;
  String get to => _s._statTo;

  /// 月份视图游标（`YYYY-MM`）
  String get month => _s._month;

  int get expenseCents => _s._statExpenseCents;
  int get incomeCents => _s._statIncomeCents;

  /// 分类聚合（饼图 / 排行），已按金额降序
  List<CatStat> get expenseStats => _s._statExpenseStats;
  List<CatStat> get incomeStats => _s._statIncomeStats;

  /// 每日收支（趋势图），按真实发生日分组
  List<(String date, int expense, int income)> get daily => _s._statDailyTotals;

  /// 近 6 段（期或月）的收支，按时间升序
  List<(String label, int expense, int income)> get trend => _s._statTrend;

  /// 是否按「期」归集 —— 统计页要按它切换文案（「本期」/「本月」）
  bool get byPeriod => _s._statBasis == StatBasis.period;
}

/// 明细筛选的只读视图。
///
/// 筛选态是「和期平行的另一个维度」：生效时明细列表看 `txns`，
/// 概览卡看 `expenseCents` / `incomeCents` / `count`（走独立 SQL 聚合，
/// 不受 500 条上限影响），而不是把列表里的金额加一遍。
///
/// 把这些收在一起，是为了让「筛选态」在调用点读起来是一个整体：
/// `store.filter.active` / `store.filter.current` / `store.filter.txns`，
/// 而不是散落的 `filtering` `filter` `filteredTxns` `filterTruncated`
/// `filterCount` 五个名字。
class FilterView {
  FilterView._(this._s);

  final Store _s;

  /// 当前条件（未筛选时是 [TxnFilter.none]）
  TxnFilter get current => _s._filter;

  /// 是否在筛选态
  bool get active => _s._filter.isNotEmpty;

  /// 命中的记录（最多 [Repo.searchLimit] 条）
  List<Txn> get txns => _s._filteredTxns;

  /// 记录是否被条数上限截断
  bool get truncated => _s._filterTruncated;

  int get expenseCents => _s._filterExpenseCents;
  int get incomeCents => _s._filterIncomeCents;
  int get count => _s._filterCount;
}
