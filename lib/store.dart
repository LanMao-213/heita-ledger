// foundation 里也有一个 Category 注解类，会和数据模型重名，这里隐藏掉
import 'package:flutter/foundation.dart' hide Category;

import 'data/db.dart';
import 'data/models.dart';
import 'data/repo.dart';

/// 全局状态。用最朴素的 ChangeNotifier —— 这个应用的数据量很小，
/// 引入状态管理框架反而增加理解成本。
class Store extends ChangeNotifier {
  Store._();

  static final Store i = Store._();

  bool ready = false;

  // 账本
  List<Ledger> ledgers = [];
  int ledgerId = 0;

  // 账户
  List<Account> accounts = [];
  int netWorthCents = 0;

  // 分类
  List<Category> expenseCats = [];
  List<Category> incomeCats = [];

  // 记账模板（templates 按管理页顺序，recentTemplates 按使用频率取前 3）
  List<TxnTemplate> templates = [];
  List<TxnTemplate> recentTemplates = [];

  // 储蓄目标
  List<SavingGoal> goals = [];

  // 当前月份
  String month = Fmt.month(DateTime.now());
  bool monthIsCurrent = true;

  // 月统计
  int monthExpenseCents = 0;
  int monthIncomeCents = 0;
  int monthTxnCount = 0;
  int? totalBudgetCents;
  List<CatStat> expenseStats = [];
  List<CatStat> incomeStats = [];
  List<BudgetStat> budgetStats = [];

  // 当前月明细
  List<Txn> monthTxns = [];

  // 明细筛选。筛选生效时明细页看 filteredTxns，否则看 monthTxns
  TxnFilter filter = TxnFilter.none;
  List<Txn> filteredTxns = [];
  bool filterTruncated = false;

  /// 当前月每日汇总（日期升序），供趋势图使用
  List<(String date, int expense, int income)> dailyTotals = [];

  /// 启动时补记的周期账单条数（>0 时界面给一次提示）
  int recurringJustAdded = 0;

  Ledger? get currentLedger {
    for (final l in ledgers) {
      if (l.id == ledgerId) return l;
    }
    return ledgers.isEmpty ? null : ledgers.first;
  }

  int get budgetLeftCents =>
      totalBudgetCents == null ? 0 : totalBudgetCents! - monthExpenseCents;

  bool get overBudget =>
      totalBudgetCents != null && monthExpenseCents > totalBudgetCents!;

  int get overBudgetCents =>
      overBudget ? monthExpenseCents - totalBudgetCents! : 0;

  /// 首屏启动：建表/开库 → 补记周期账单 → 载入全部数据
  Future<void> boot() async {
    await Db.open();
    ledgerId = await Repo.currentLedgerId();
    recurringJustAdded = await Repo.runDueRecurring(ledgerId);
    await loadAll();
    ready = true;
    notifyListeners();
  }

  Future<void> loadAll() async {
    ledgers = await Repo.listLedgers();
    accounts = await Repo.listAccounts();
    netWorthCents = await Repo.totalBalanceCents();
    expenseCats = await Repo.listCategories(ledgerId, type: TxnType.expense);
    incomeCats = await Repo.listCategories(ledgerId, type: TxnType.income);
    goals = await Repo.listGoals();
    await loadTemplates();
    await loadMonth();
  }

  Future<void> loadTemplates() async {
    templates = await Repo.listTemplates(ledgerId);
    recentTemplates = await Repo.recentTemplates(ledgerId);
  }

  Future<void> loadMonth() async {
    final totals = await Repo.monthTotals(ledgerId, month);
    monthExpenseCents = totals.$1;
    monthIncomeCents = totals.$2;
    monthTxnCount = totals.$3;
    totalBudgetCents = await Repo.totalBudgetCents(ledgerId, month);
    expenseStats =
        await Repo.categoryStats(ledgerId: ledgerId, month: month, type: TxnType.expense);
    incomeStats =
        await Repo.categoryStats(ledgerId: ledgerId, month: month, type: TxnType.income);
    budgetStats = await Repo.budgetStats(ledgerId, month);
    monthTxns = await Repo.listTxns(ledgerId: ledgerId, month: month);
    dailyTotals = await Repo.dailyTotals(ledgerId, month);
    monthIsCurrent = month == Fmt.month(DateTime.now());
    notifyListeners();
  }

  Future<void> setMonth(String ym) async {
    month = ym;
    await loadMonth();
  }

  Future<void> shiftMonth(int delta) =>
      setMonth(Fmt.shiftMonth(month, delta));

  Future<void> switchLedger(int id) async {
    ledgerId = id;
    // 分类 ID 属于账本：带着旧条件切过去只会筛出空结果或错数据
    _resetFilter();
    await Repo.setSetting('current_ledger_id', '$id');
    await loadAll();
  }

  /// 记一笔 / 改一笔 / 删一笔之后统一调这个刷新
  Future<void> afterTxnChange() async {
    accounts = await Repo.listAccounts();
    netWorthCents = await Repo.totalBalanceCents();
    await loadMonth();
    // 筛选态下必须重跑，否则删掉的记录还会挂在结果里
    if (filtering) await applyFilter(filter);
  }

  /// 删除一笔（会同时回滚账户余额，由 Repo 负责）
  Future<void> deleteTxn(Txn t) async {
    await Repo.deleteTxn(t);
    await afterTxnChange();
  }

  Future<void> afterCategoryChange() async {
    expenseCats = await Repo.listCategories(ledgerId, type: TxnType.expense);
    incomeCats = await Repo.listCategories(ledgerId, type: TxnType.income);
    await loadMonth();
  }

  Future<void> afterAccountChange() async {
    accounts = await Repo.listAccounts();
    netWorthCents = await Repo.totalBalanceCents();
    notifyListeners();
  }

  Future<void> afterGoalChange() async {
    goals = await Repo.listGoals();
    notifyListeners();
  }

  Future<void> afterTemplateChange() async {
    await loadTemplates();
    notifyListeners();
  }

  Future<void> afterBudgetChange() async {
    totalBudgetCents = await Repo.totalBudgetCents(ledgerId, month);
    budgetStats = await Repo.budgetStats(ledgerId, month);
    notifyListeners();
  }

  Category? categoryOf(int? id) {
    if (id == null) return null;
    for (final c in expenseCats) {
      if (c.id == id) return c;
    }
    for (final c in incomeCats) {
      if (c.id == id) return c;
    }
    return null;
  }

  Account? accountOf(int? id) {
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ------------------------------------------------------------------ 筛选

  bool get filtering => filter.isNotEmpty;

  /// 明细页的展示源：筛选生效时看筛选结果，否则看当月全部
  List<Txn> get visibleTxns => filtering ? filteredTxns : monthTxns;

  /// 筛选结果的支出合计（不含转账，与 monthTotals 同口径）
  int get filteredExpenseCents => _sum(filteredTxns, TxnType.expense);

  /// 筛选结果的收入合计（不含转账）
  int get filteredIncomeCents => _sum(filteredTxns, TxnType.income);

  /// 应用筛选。空条件等价于「清空筛选」。
  ///
  /// 先查库再改状态：查询抛错时 Store 保持原样，不会留下「条件条说已经
  /// 筛选、列表却是空的」这种假态。
  Future<void> applyFilter(TxnFilter f) async {
    if (f.isEmpty) {
      _resetFilter();
      notifyListeners();
      return;
    }
    final (items, truncated) =
        await Repo.searchTxns(ledgerId: ledgerId, filter: f);
    filter = f;
    filteredTxns = items;
    filterTruncated = truncated;
    notifyListeners();
  }

  Future<void> clearFilter() => applyFilter(TxnFilter.none);

  void _resetFilter() {
    filter = TxnFilter.none;
    filteredTxns = [];
    filterTruncated = false;
  }

  int _sum(List<Txn> txns, TxnType type) => txns
      .where((t) => t.type == type)
      .fold<int>(0, (a, t) => a + t.amountCents);

  /// 把当前月明细按日期分组（日期倒序，组内 id 倒序）
  List<(String date, List<Txn> items)> get groupedByDay => _group(monthTxns);

  /// 筛选态下的按日分组，与 groupedByDay 同构
  List<(String date, List<Txn> items)> get groupedVisibleByDay =>
      _group(visibleTxns);

  List<(String date, List<Txn> items)> _group(List<Txn> txns) {
    final map = <String, List<Txn>>{};
    for (final t in txns) {
      map.putIfAbsent(t.date, () => []).add(t);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) => (k, map[k]!)).toList();
  }

  /// 重新开库（清空数据之后用）
  Future<void> reboot() async {
    await Db.close();
    _resetFilter();
    await boot();
  }
}
