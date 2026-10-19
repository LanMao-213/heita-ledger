// foundation 里也有一个 Category 注解类，会和数据模型重名，这里隐藏掉
import 'package:flutter/foundation.dart' hide Category;

import 'data/db.dart';
import 'data/cycle.dart' as cyc;
import 'data/models.dart';
import 'data/repo.dart';
import 'data/ui_flags.dart';

/// 统计页的归集口径。
///
/// 「本期」按归属期（`period_start`），「本月」按真实日期（`date`）。
/// 账单日不是 1 时两者数字会不同 —— 这不是 bug，是切换按钮要表达的东西。
enum StatBasis { period, month }

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
  //
  // 两级分类（v6 起）：[allExpenseCats] 含全部节点，用于按 id 反查；
  // [expenseCats] 只留一级 —— 筛选面板、预算、分类管理、录入左轮要的都是
  // 一级，混着子分类列出来会出现「餐饮」和「正餐」并排的怪状。
  List<Category> allExpenseCats = [];
  List<Category> allIncomeCats = [];
  List<Category> expenseCats = [];
  List<Category> incomeCats = [];

  // 记账模板（templates 按管理页顺序，recentTemplates 按使用频率取前 3）
  List<TxnTemplate> templates = [];
  List<TxnTemplate> recentTemplates = [];

  // 储蓄目标
  List<SavingGoal> goals = [];

  // ---------------------------------------------------------------- 周期 / 月
  //
  // 明细页与计划页（预算）看的是**当前期**：`cycleFrom`–`cycleTo`。
  // 统计页可以在「本期 / 本月」之间切换，所以它另有一套 `stat*` 字段 ——
  // 两套分开存，切换统计数据时不会把明细页的数字带歪。

  /// 账单日（周期起始日），1–31，默认 1（= 自然月）
  int cycleStartDay = 1;

  /// 当前期首尾日期（`YYYY-MM-DD`，含两端）
  String cycleFrom = '';
  String cycleTo = '';

  /// 当前期是否包含今天
  bool isCurrentPeriod = true;

  /// 当前期的收支与明细
  int expenseCents = 0;
  int incomeCents = 0;
  int txnCount = 0;
  List<Txn> txns = [];

  /// 借贷往来（带派生的已还金额）。
  ///
  /// 明细行据此把流水显示成「借出 · 张三」而不是红色支出，往来卡片也读它 ——
  /// 共用一个缓存，避免两处各查一次、口径还不一致。
  List<Debt> debts = [];
  Map<int, Debt> _debtById = {};

  /// 按 id 取往来；普通流水返回 null（明细行据此决定用哪种渲染）
  Debt? debtOf(int? id) => id == null ? null : _debtById[id];

  /// 抬期池分类 id（工资/奖金/提成）：记一笔面板用它给开关一个默认值
  Set<int> liftableCatIds = {};

  /// 当前期的预算（预算也按周期，D13 已改）
  int? totalBudgetCents;
  List<BudgetStat> budgetStats = [];

  /// 统计页的归集口径
  StatBasis statBasis = StatBasis.period;

  /// 统计页当前看的区间（周期视图 = 当前期；月份视图 = 自然月）
  String statFrom = '';
  String statTo = '';

  String month = Fmt.month(DateTime.now());
  int statExpenseCents = 0;
  int statIncomeCents = 0;
  List<CatStat> statExpenseStats = [];
  List<CatStat> statIncomeStats = [];
  List<(String date, int expense, int income)> statDailyTotals = [];

  /// 近 6 段的收支（周期视图是「期」，月份视图是「月」），按时间升序。
  ///
  /// 放在 Store 而不是页面里，是因为它跟当前区间绑死：换期要重查，
  /// 页面组件只该读，不该自己管异步生命周期（否则测试里也等不到回包）。
  List<(String label, int expense, int income)> statTrend = [];

  // 明细筛选。筛选生效时明细页看 filteredTxns，否则看 monthTxns
  TxnFilter filter = TxnFilter.none;
  List<Txn> filteredTxns = [];
  bool filterTruncated = false;

  // 筛选合计走独立聚合（D20），不受 filteredTxns 的 500 条上限影响。
  // 存在这里而不是每次现算，是因为合计要在概览卡里同步显示。
  int _filterExpenseCents = 0;
  int _filterIncomeCents = 0;
  int filterCount = 0;

  /// 启动时补记的周期账单条数（>0 时界面给一次提示）
  int recurringJustAdded = 0;

  /// 是否要提示「分类升级成两级了」。只在真的从老库升上来、且没提示过时为真。
  bool catsUpgradeJustDone = false;

  static const _kCatsNotice = 'ui.cats_two_level_notice';

  Ledger? get currentLedger {
    for (final l in ledgers) {
      if (l.id == ledgerId) return l;
    }
    return ledgers.isEmpty ? null : ledgers.first;
  }

  int get budgetLeftCents =>
      totalBudgetCents == null ? 0 : totalBudgetCents! - expenseCents;

  bool get overBudget =>
      totalBudgetCents != null && expenseCents > totalBudgetCents!;

  int get overBudgetCents => overBudget ? expenseCents - totalBudgetCents! : 0;

  /// 首屏启动：建表/开库 → 补归属期 → 补记周期账单 → 载入全部数据
  Future<void> boot() async {
    await Db.open();
    // v3 → v4 升级后 `period_start` 是空的，先补齐。账单日默认 1 时回填结果
    // 等于月初，与升级前完全一致 —— 这一步不改任何查询口径。
    await Repo.backfillMissingPeriods();
    // 界面实验开关（类型 chips / 空态第二行）从 setting 表读覆盖值
    await UiFlags.load();
    ledgerId = await Repo.currentLedgerId();
    cycleStartDay = await Repo.cycleStartDay();
    resetCycleToToday();
    recurringJustAdded = await Repo.runDueRecurring(ledgerId);

    // 分类从「一级 + 名目」改成「分类 + 子分类」之后，老用户打开会看到一堆
    // 眼熟的分类换了名字（交通→出行、学习→成长），还多出一层子分类。
    // 不说一句，他会以为数据被改乱了。提示只出一次，落一个 setting 作标记。
    if (Db.upgradedToTwoLevel && await Repo.getSetting(_kCatsNotice) == null) {
      catsUpgradeJustDone = true;
      await Repo.setSetting(_kCatsNotice, '1');
    }

    await loadAll();
    ready = true;
    notifyListeners();
  }

  /// 把当前期拨回「今天所在的那一期」
  void resetCycleToToday() {
    final (from, to) = cyc.cycleRange(DateTime.now(), cycleStartDay);
    cycleFrom = from;
    cycleTo = to;
  }

  Future<void> loadAll() async {
    ledgers = await Repo.listLedgers();
    accounts = await Repo.listAccounts();
    netWorthCents = await Repo.totalBalanceCents();
    await _loadCategories();
    await _loadDebts();
    goals = await Repo.listGoals();
    liftableCatIds = await Repo.liftableCategoryIds(ledgerId);
    await loadTemplates();
    await loadCycle();
    await loadStats();
  }

  /// 整库被替换（从备份恢复）之后重读一遍。
  ///
  /// 比 loadAll 多做两件事：`current_ledger_id` 可能也变了要重取；
  /// 筛选条件里引用的分类/账户可能已经不存在，直接清掉。
  Future<void> reloadAfterRestore() async {
    ledgerId = await Repo.currentLedgerId();
    _resetFilter();
    await loadAll();
    notifyListeners();
  }

  Future<void> loadTemplates() async {
    templates = await Repo.listTemplates(ledgerId);
    recentTemplates = await Repo.recentTemplates(ledgerId);
  }

  /// 载入当前期：明细页、计划页、预算都看这一份
  Future<void> loadCycle() async {
    final totals = await Repo.rangeTotals(ledgerId, cycleFrom, cycleTo);
    expenseCents = totals.$1;
    incomeCents = totals.$2;
    txnCount = totals.$3;
    totalBudgetCents = await Repo.totalBudgetCents(ledgerId, cycleFrom);
    budgetStats = await Repo.budgetStats(
      ledgerId: ledgerId,
      periodStart: cycleFrom,
      from: cycleFrom,
      to: cycleTo,
    );
    txns = await Repo.rangeListTxns(
      ledgerId: ledgerId,
      from: cycleFrom,
      to: cycleTo,
    );
    isCurrentPeriod = cyc.isCurrentCycle(cycleFrom, cycleTo);
    notifyListeners();
  }

  /// 载入统计页数据。口径由 [statBasis] 决定，字段也单独存（`stat*`），
  /// 所以切换口径不会动到明细页的数字。
  Future<void> loadStats() async {
    final byPeriod = statBasis == StatBasis.period;
    statFrom = byPeriod ? cycleFrom : Repo.monthStart(month);
    statTo = byPeriod ? cycleTo : Repo.monthEnd(month);
    final basis = byPeriod ? DateBasis.period : DateBasis.date;

    final totals = await Repo.rangeTotals(
      ledgerId,
      statFrom,
      statTo,
      basis: basis,
    );
    statExpenseCents = totals.$1;
    statIncomeCents = totals.$2;
    statExpenseStats = await Repo.rangeCategoryStats(
      ledgerId: ledgerId,
      from: statFrom,
      to: statTo,
      type: TxnType.expense,
      basis: basis,
    );
    statIncomeStats = await Repo.rangeCategoryStats(
      ledgerId: ledgerId,
      from: statFrom,
      to: statTo,
      type: TxnType.income,
      basis: basis,
    );
    statDailyTotals = await Repo.rangeDailyTotals(
      ledgerId,
      statFrom,
      statTo,
      basis: basis,
    );
    statTrend = byPeriod
        ? await Repo.recentPeriods(
            ledgerId: ledgerId,
            endFrom: cycleFrom,
            startDay: cycleStartDay,
            count: 6,
          )
        : await Repo.recentMonths(
            ledgerId: ledgerId,
            endMonth: month,
            count: 6,
          );
    notifyListeners();
  }

  /// 切换统计口径（统计页的「本期 / 本月」）
  Future<void> setStatBasis(StatBasis b) async {
    if (statBasis == b) return;
    statBasis = b;
    await loadStats();
  }

  /// 统计页翻一段：周期视图翻一期，月份视图翻一个月
  Future<void> shiftStat(int delta) async {
    if (statBasis == StatBasis.period) {
      await shiftCycle(delta);
      return;
    }
    month = Fmt.shiftMonth(month, delta);
    await loadStats();
  }

  /// 明细页 / 计划页翻一期
  Future<void> shiftCycle(int delta) async {
    cycleFrom = cyc.shiftCycleDate(cycleFrom, cycleStartDay, delta);
    cycleTo = Fmt.date(
      cyc
          .shiftCycle(DateTime.parse(cycleFrom), cycleStartDay, 1)
          .subtract(const Duration(days: 1)),
    );
    await loadCycle();
    // 统计页停在周期视图时要跟着翻，否则切回图表页数字还停在上一期
    if (statBasis == StatBasis.period) await loadStats();
  }

  /// 跳到某个日期所在的那一期（日历里点某天用）
  Future<void> goToCycleOf(String date) async {
    final (from, to) = cyc.cycleRange(DateTime.parse(date), cycleStartDay);
    if (from == cycleFrom && to == cycleTo) return;
    cycleFrom = from;
    cycleTo = to;
    await loadCycle();
    if (statBasis == StatBasis.period) await loadStats();
  }

  /// 跳到某个月（统计页的月份视图里点日历用）。
  ///
  /// 只动 `month` 与统计数据：明细页/预算走的是「期」，不该被月份跳转带偏。
  Future<void> goToMonth(String ym) async {
    if (month == ym) return;
    month = ym;
    await loadStats();
  }

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
    // 借贷的「已还多少」是按流水算的，动过流水就得重算
    await _loadDebts();
    await loadCycle();
    await loadStats();
    // 筛选态下必须重跑，否则删掉的记录还会挂在结果里
    if (filtering) await applyFilter(filter);
  }

  /// 删除一笔（会同时回滚账户余额，由 Repo 负责）
  Future<void> deleteTxn(Txn t) async {
    await Repo.deleteTxn(t);
    await afterTxnChange();
  }

  Future<void> afterCategoryChange() async {
    await _loadCategories();
    await loadCycle();
    await loadStats();
  }

  /// 分类是两级结构，但只有一个数据源：一次查全，再切出一级。
  /// 分开查两次（`WHERE parent_id IS NULL` + 全量）会让两个列表的
  /// 加载时机不一致，改分类时界面会闪一下。
  Future<void> _loadCategories() async {
    allExpenseCats = await Repo.listCategories(ledgerId, type: TxnType.expense);
    allIncomeCats = await Repo.listCategories(ledgerId, type: TxnType.income);
    expenseCats = _topOnly(allExpenseCats);
    incomeCats = _topOnly(allIncomeCats);
  }

  /// 借贷列表与索引一起重建，保证 `debts` 与 `debtOf` 永远一致
  Future<void> _loadDebts() async {
    debts = await Repo.listDebts(ledgerId: ledgerId);
    _debtById = {for (final d in debts) d.id: d};
  }

  static List<Category> _topOnly(List<Category> all) => [
    for (final c in all)
      if (c.parentId == null) c,
  ];

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
    totalBudgetCents = await Repo.totalBudgetCents(ledgerId, cycleFrom);
    budgetStats = await Repo.budgetStats(
      ledgerId: ledgerId,
      periodStart: cycleFrom,
      from: cycleFrom,
      to: cycleTo,
    );
    notifyListeners();
  }

  Category? categoryOf(int? id) {
    if (id == null) return null;
    for (final c in allExpenseCats) {
      if (c.id == id) return c;
    }
    for (final c in allIncomeCats) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 某个一级分类的全部子分类，已按 `sort_order` 排好（查询时就是这个顺序）。
  List<Category> childrenOf(int? parentId) {
    if (parentId == null) return const [];
    return [
      for (final c in allExpenseCats)
        if (c.parentId == parentId) c,
      for (final c in allIncomeCats)
        if (c.parentId == parentId) c,
    ];
  }

  /// 子分类的父级；一级分类本身返回 null。
  /// 明细行要显示「正餐 · 餐饮」这种层级说明时用得上。
  Category? parentOf(Category? c) =>
      c?.parentId == null ? null : categoryOf(c!.parentId);

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
  List<Txn> get visibleTxns => filtering ? filteredTxns : txns;

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

  /// 把当前期明细按日期分组（日期倒序，组内 id 倒序）
  List<(String date, List<Txn> items)> get groupedByDay => _group(txns);

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

  /// 账单日改动后：重算归属期 + 挪预算 + 拨回今天所在的那一期 + 全量重载
  Future<void> applyCycleStartDay(int day) async {
    cycleStartDay = day.clamp(1, 31);
    await Repo.setSetting(Repo.cycleStartDayKey, '$cycleStartDay');
    await Repo.rebuildPeriods(ledgerId);
    // 预算的 key 是期首日，账单日变了必须跟着挪，否则历史预算全部「悬空」
    await Repo.remapBudgetPeriods(cycleStartDay);
    resetCycleToToday();
    await loadCycle();
    await loadStats();
  }
}
