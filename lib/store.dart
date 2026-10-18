// foundation 里也有一个 Category 注解类，会和数据模型重名，这里隐藏掉
import 'package:flutter/foundation.dart' hide Category;

import 'data/db.dart';
import 'data/models.dart';
import 'data/repo.dart';
import 'data/ui_flags.dart';

/// 全局状态。用最朴素的 ChangeNotifier —— 这个应用的数据量很小，
/// 引入状态管理框架反而增加理解成本。
class Store extends ChangeNotifier {
  Store._();

  static final Store i = Store._();

  bool ready = false;

  /// 底部导航当前页：0 明细 / 1 图表 / 2 计划 / 3 我的。
  /// 放在 Store 里是为了让统计页「点某天看明细」能跨页切 Tab，
  /// 而不用给 HomeShell 开一个谁都能调的全局 key。
  int tabIndex = 0;

  void switchTab(int i) {
    if (tabIndex == i) return;
    tabIndex = i;
    notifyListeners();
  }

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

  // 筛选合计走独立聚合（D20），不受 filteredTxns 的 500 条上限影响。
  // 存在这里而不是每次现算，是因为合计要在概览卡里同步显示。
  int _filterExpenseCents = 0;
  int _filterIncomeCents = 0;
  int filterCount = 0;

  /// 当前月每日汇总（日期升序），供趋势图使用
  List<(String date, int expense, int income)> dailyTotals = [];

  /// 近 6 个月收支（含当前月，按月升序），统计页的「近 6 个月」用。
  ///
  /// 放在 Store 而不是页面里，是因为它跟 month 绑死：换月要重查，
  /// 页面组件只该读，不该自己管异步生命周期（否则测试里也等不到回包）。
  List<(String month, int expense, int income)> trendMonths = [];

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
    // 界面实验开关（类型 chips / 空态第二行）从 setting 表读覆盖值
    await UiFlags.load();
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
    trendMonths = await Repo.recentMonths(
      ledgerId: ledgerId,
      endMonth: month,
      count: 6,
    );
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

  /// 筛选结果的支出合计。
  ///
  /// 来自 SQL 聚合（[Repo.sumFiltered]），**不是**把 [filteredTxns] 相加 ——
  /// 列表最多 500 条，相加会把合计算小（D20）。负数按交叉归集：
  /// 支出里的负数算收入，反之亦然；转账两侧都不参与。
  int get filteredExpenseCents => _filterExpenseCents;

  /// 筛选结果的收入合计（同上口径）
  int get filteredIncomeCents => _filterIncomeCents;

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
    // 列表与合计并发查：合计单独聚合（D20），不跟着 500 条上限截断。
    // 用 record 的 .wait 而不是两次 await，是为了「筛选只等一次 I/O」——
    // 时序上也更自然：两者本来就该同时发起。
    final ((items, truncated), (expense, income, count)) = await (
      Repo.searchTxns(ledgerId: ledgerId, filter: f),
      Repo.sumFiltered(ledgerId: ledgerId, filter: f),
    ).wait;
    filter = f;
    filteredTxns = items;
    filterTruncated = truncated;
    _filterExpenseCents = expense;
    _filterIncomeCents = income;
    filterCount = count;
    notifyListeners();
  }

  Future<void> clearFilter() => applyFilter(TxnFilter.none);

  void _resetFilter() {
    filter = TxnFilter.none;
    filteredTxns = [];
    filterTruncated = false;
    _filterExpenseCents = 0;
    _filterIncomeCents = 0;
    filterCount = 0;
  }

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
