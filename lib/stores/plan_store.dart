import '../core/local_date.dart';
import '../core/period.dart';
import '../data/models/models.dart';
import '../data/repo/budget_repo.dart';
import '../data/repo/category_repo.dart';
import '../data/repo/debt_repo.dart';
import '../data/repo/recurring_repo.dart';
import '../data/repo/setting_repo.dart';
import '../data/repo/stats_repo.dart';
import '../data/services/summary_service.dart';
import 'shell_store.dart';

/// 图表页的两把尺子。
///
/// - [cycle]：按**归属期**（账单日 ≠ 1 时与自然月不重合）；
/// - [month]：按**自然月**（用户嘴里说的「这个月」）。
///
/// 两个口径**不共用游标、不共用快照**（判据 3.5）——共用一个字段的话，
/// 切一下口径明细页的期就被顺手改了，用户翻回来会以为记错账。
enum StatsScope {
  cycle('本期'),
  month('本月');

  const StatsScope(this.label);

  final String label;
}

/// 统计快照：**统计不在启动路径算**（§5.2）。
///
/// 页面先渲染上一次快照，后台重算完再替换；失败保留旧值不清空 ——
/// 原版「统计页首帧显示本期还没有数据」就是因为在首帧路径里同步算。
class StatSnapshot {
  const StatSnapshot({
    required this.scope,
    required this.period,
    required this.loaded,
    required this.expenseCents,
    required this.incomeCents,
    required this.expenseCats,
    required this.incomeCats,
    required this.daily,
    required this.trend,
    required this.accountAssetsCents,
    required this.computedAt,
  });

  /// 还没算过的空壳（只有区间是对的，用来让骨架显示「哪一段」）。
  factory StatSnapshot.unloaded(StatsScope scope, Period period) => StatSnapshot(
    scope: scope,
    period: period,
    loaded: false,
    expenseCents: 0,
    incomeCents: 0,
    expenseCats: const <CategoryStat>[],
    incomeCats: const <CategoryStat>[],
    daily: const <DailyTotal>[],
    trend: const <TrendSegment>[],
    accountAssetsCents: 0,
    computedAt: null,
  );

  final StatsScope scope;

  /// 这个快照覆盖的**真实日期区间**（已按口径换算过）。
  final Period period;

  /// 是否算过一次。为 false 时页面画骨架，**不许**画「还没有数据」。
  final bool loaded;

  final int expenseCents;
  final int incomeCents;

  /// 一级分类聚合（已按金额降序、已剔除合计 ≤0 的）。
  final List<CategoryStat> expenseCats;
  final List<CategoryStat> incomeCats;

  /// 区间内**每一天**一格（无数据的那天是 0）。
  final List<DailyTotal> daily;

  /// 近 6 段双柱（含当前段）。
  final List<TrendSegment> trend;

  /// Σ 账户余额（只算计入净资产的）。
  final int accountAssetsCents;

  final DateTime? computedAt;

  /// 这一口径下真的没有数据（空态文案只在 `loaded == true` 之后才允许出现）。
  bool get isEmpty => expenseCats.isEmpty && incomeCats.isEmpty;
}

/// 分类预算的一行：一级分类 + 本期限额 + 本期已花（含所有子分类）。
class CategoryBudgetRow {
  const CategoryBudgetRow({
    required this.category,
    required this.budgetCents,
    required this.spentCents,
  });

  final Category category;

  /// 0 = 没设预算（只因为本期有支出才被列出来）。
  final int budgetCents;

  /// 支出**含该一级下所有子分类**（记到「正餐」要能推动「餐饮」的进度条）。
  final int spentCents;

  bool get hasBudget => budgetCents > 0;

  /// 花掉的比例（不截断，超了 > 1，界面自己 clamp）。
  double get ratio => budgetCents <= 0 ? 0 : spentCents / budgetCents;

  int get leftCents => budgetCents - spentCents;

  int get overCents => leftCents < 0 ? -leftCents : 0;
}

/// 分类预算列表 = 「设了预算的 ∪ 本期有支出的一级」（口径 3.1）。
///
/// 排序：**有预算的按额度降序在前，没预算的按已花降序在后** ——
/// 前者是用户主动管的，后者是「花了但没设限」的提醒，混在一起排会两头不讨好。
List<CategoryBudgetRow> buildCategoryBudgetRows({
  required CategoryTree tree,
  required List<Budget> budgets,
  required Map<int, int> spentByCategory,
}) {
  final Map<int, int> budgetByCategory = <int, int>{};
  for (final Budget b in budgets) {
    final int? id = b.categoryId;
    if (id == null) continue;
    budgetByCategory[id] = (budgetByCategory[id] ?? 0) + b.amountCents;
  }

  final Set<int> ids = <int>{
    ...budgetByCategory.keys,
    for (final MapEntry<int, int> e in spentByCategory.entries)
      if (e.value > 0) e.key,
  };

  final List<CategoryBudgetRow> rows = <CategoryBudgetRow>[];
  for (final int id in ids) {
    final Category? c = tree.byId(id);
    // 已停用的分类不出现：它的历史支出还在，但「再给它设预算」没有意义
    if (c == null || c.archived || !c.isTop) continue;
    rows.add(
      CategoryBudgetRow(
        category: c,
        budgetCents: budgetByCategory[id] ?? 0,
        spentCents: spentByCategory[id] ?? 0,
      ),
    );
  }

  rows.sort((CategoryBudgetRow a, CategoryBudgetRow b) {
    if (a.hasBudget != b.hasBudget) return a.hasBudget ? -1 : 1;
    if (a.hasBudget) return b.budgetCents.compareTo(a.budgetCents);
    return b.spentCents.compareTo(a.spentCents);
  });
  return rows;
}

/// 预算 / 借贷 / 周期账单 / 统计快照。
///
/// ★ 补记的三道闸都在这里（与 `RecurringRepo` 的物理唯一索引配合）：
/// 闸一按**账本**记「今天扫过没有」，闸二是**在飞 Future 复用**。
class PlanStore extends StoreBase {
  PlanStore();

  final BudgetRepo _budgets = const BudgetRepo();
  final DebtRepo _debts = const DebtRepo();
  final RecurringRepo _recurring = const RecurringRepo();
  final StatsRepo _stats = const StatsRepo();
  final CategoryRepo _categories = const CategoryRepo();
  final SettingRepo _settings = const SettingRepo();

  int _ledgerId = 0;
  int _cycleStartDay = 1;
  Period _period = Period(
    from: LocalDate.today().firstOfMonth,
    to: LocalDate.today().lastOfMonth,
  );

  BudgetStats _budget = BudgetStats.empty;
  List<Budget> _categoryBudgets = <Budget>[];
  List<CategoryBudgetRow> _categoryRows = <CategoryBudgetRow>[];
  Map<int, int> _spentByCategory = <int, int>{};
  List<Debt> _debtList = <Debt>[];
  List<Debt> _closedDebts = <Debt>[];
  RepaidIndex _repaidIndex = RepaidIndex.empty;
  List<Recurring> _recurringList = <Recurring>[];

  // ── 统计：两个口径各一份游标、各一份快照 ──
  StatsScope _statsScope = StatsScope.cycle;
  Period? _statsCycle;
  Period? _statsMonth;
  final Map<StatsScope, StatSnapshot> _snapshots = <StatsScope, StatSnapshot>{};
  final Map<StatsScope, bool> _statsStale = <StatsScope, bool>{};

  /// 闸一：按**账本**记「今天扫过没有」。键不是全局时间戳 ——
  /// 全局时间戳会让 24h 内切到另一本账被误挡，那本账永远不补（原版踩过）。
  final Map<int, LocalDate> _scannedOn = <int, LocalDate>{};

  /// 闸二：在飞 Future 复用（冷启动与回前台撞车时不新开一条）。
  Future<int>? _inFlight;

  BudgetStats get budget => _budget;

  /// 当前账本 id（写预算时要用）。
  int get ledgerId => _ledgerId;

  List<Budget> get categoryBudgets => _categoryBudgets;

  /// 分类预算列表（已在重查时算好，UI 直接读，不再异步查库）。
  List<CategoryBudgetRow> get categoryBudgetRows => _categoryRows;

  Map<int, int> get spentByCategory => _spentByCategory;
  /// **未结清**的往来（计划页摘要、往来页「未结清」段用）。
  List<Debt> get debts => _debtList;

  /// 已结清的往来（往来页末尾那段；单独一份，免得每个调用方自己过滤）。
  List<Debt> get closedDebts => _closedDebts;
  RepaidIndex get repaidIndex => _repaidIndex;
  List<Recurring> get recurring => _recurringList;

  /// 计划页正在看的那一期。
  Period get period => _period;
  int get cycleStartDay => _cycleStartDay;

  // ── 统计 ──

  StatsScope get statsScope => _statsScope;

  /// 当前口径的区间（翻期只动这里，绝不动 `BookStore.cycle`）。
  Period get statsPeriod => _rangeOf(_statsScope);

  /// 某个口径当前的区间；游标还没动过就落到「今天所在的那一段」。
  Period _rangeOf(StatsScope scope) {
    final Period? cursor = _rangeOfScope(scope);
    if (cursor != null) return cursor;
    return Period.cycleRange(
      LocalDate.today(),
      scope == StatsScope.cycle ? _cycleStartDay : 1,
    );
  }

  /// 当前口径的快照。**区间对不上就当作没算过**（翻期后先给骨架，别给旧数字）。
  StatSnapshot get stats => statsOf(_statsScope);

  StatSnapshot statsOf(StatsScope scope) {
    final Period want = _rangeOf(scope);
    final StatSnapshot? cached = _snapshots[scope];
    if (cached != null &&
        cached.period.from == want.from &&
        cached.period.to == want.to) {
      return cached;
    }
    return StatSnapshot.unloaded(scope, want);
  }

  Period? _rangeOfScope(StatsScope scope) =>
      scope == StatsScope.cycle ? _statsCycle : _statsMonth;

  /// 当前口径是否要重算（没算过，或被记账打了脏标记）。
  bool get statsStale =>
      !stats.loaded || (_statsStale[_statsScope] ?? false);

  /// 换口径：**只改统计自己的游标**，明细页的期一动不动。
  void switchStatsScope(StatsScope scope) {
    if (scope == _statsScope) return;
    _statsScope = scope;
    notifyListeners();
  }

  /// 区间条横滑翻页（[delta] 正数往后）。两个口径的步长不同：
  /// 期按账单日滚，月按自然月滚。
  void flipStats(int delta) {
    if (delta == 0) return;
    final Period current = statsPeriod;
    final Period next = _statsScope == StatsScope.cycle
        ? Period.shiftCycle(current, delta, _cycleStartDay)
        : _shiftMonth(current, delta);
    if (_statsScope == StatsScope.cycle) {
      _statsCycle = next;
    } else {
      _statsMonth = next;
    }
    notifyListeners();
  }

  /// 双击区间条：回到今天所在的期 / 月。
  void resetStatsToToday() {
    if (_statsScope == StatsScope.cycle) {
      _statsCycle = Period.cycleRange(LocalDate.today(), _cycleStartDay);
    } else {
      _statsMonth = Period.cycleRange(LocalDate.today(), 1);
    }
    notifyListeners();
  }

  /// 日历选了某天：跳到那天所在的期 / 月。
  void jumpStatsTo(LocalDate day) {
    if (_statsScope == StatsScope.cycle) {
      _statsCycle = Period.cycleRange(day, _cycleStartDay);
    } else {
      _statsMonth = Period.cycleRange(day, 1);
    }
    notifyListeners();
  }

  static Period _shiftMonth(Period naturalMonth, int delta) {
    int year = naturalMonth.from.year;
    int month = naturalMonth.from.month + delta;
    while (month > 12) {
      month -= 12;
      year++;
    }
    while (month < 1) {
      month += 12;
      year--;
    }
    return Period.cycleRange(LocalDate(year, month, 1), 1);
  }

  // ── 计划页周期条 ──

  /// 翻期（[delta] 正数往后）。计划页**允许翻到未来**（提前排下一期的预算），
  /// 与明细页（不许翻未来）不同。
  Future<void> movePeriod(int delta) async {
    if (delta == 0) return;
    _period = Period.shiftCycle(_period, delta, _cycleStartDay);
    await reload();
  }

  Future<void> resetPeriodToToday() async {
    final Period today = Period.cycleRange(LocalDate.today(), _cycleStartDay);
    if (today.from == _period.from && today.to == _period.to) return;
    _period = today;
    await reload();
  }

  Future<void> jumpToPeriod(Period period) async {
    if (period.from == _period.from && period.to == _period.to) return;
    _period = period;
    await reload();
  }

  /// 绑定账本与当期。
  Future<void> bind({
    required int ledgerId,
    required Period period,
    int cycleStartDay = 1,
  }) async {
    _ledgerId = ledgerId;
    _cycleStartDay = cycleStartDay;
    _period = period;
    _statsCycle = null;
    _statsMonth = null;
    _snapshots.clear();
    _statsStale
      ..clear()
      ..[StatsScope.cycle] = true
      ..[StatsScope.month] = true;
  }

  /// 全量重查（预算 / 分类预算 / 往来 / 周期账单）。
  Future<void> reload() async {
    await batchNotifyAsync<void>(() async {
      await _loadWithoutNotify();
      notifyListeners();
    });
  }

  Future<void> _loadWithoutNotify() async {
    _budget = await _budgets.stats(ledgerId: _ledgerId, period: _period);
    _categoryBudgets = await _budgets.categoryBudgets(_ledgerId, _period.from);
    // 一条查询拿全，再在内存里分两桶（避免两次 IO）
    final List<Debt> allDebts = await _debts.all(_ledgerId);
    _debtList = <Debt>[
      for (final Debt d in allDebts)
        if (!d.isClosed) d,
    ];
    _closedDebts = <Debt>[
      for (final Debt d in allDebts)
        if (d.isClosed) d,
    ];
    _repaidIndex = await _debts.repaidIndex(_ledgerId);
    _recurringList = await _recurring.all(_ledgerId);

    // 分类预算的「已花」要覆盖**所有**一级分类：只查「设了预算的」那些，
    // 「花了但没设限」的分类就永远进不了列表（判据 3.4 要的正是它）。
    final CategoryTree tree = CategoryTree(await _categories.all(_ledgerId));
    final List<int> expenseTopIds = <int>[
      for (final Category c in tree.tops)
        if (c.type == TxnType.expense && c.id != null) c.id!,
    ];
    _spentByCategory = await _budgets.spentByCategory(
      ledgerId: _ledgerId,
      period: _period,
      topCategoryIds: expenseTopIds,
    );
    _categoryRows = buildCategoryBudgetRows(
      tree: tree,
      budgets: _categoryBudgets,
      spentByCategory: _spentByCategory,
    );
  }

  /// 分类预算列表（口径 3.1 的实现见 [buildCategoryBudgetRows]）。
  Future<List<CategoryBudgetRow>> reloadCategoryBudgetRows() async {
    await reload();
    return _categoryRows;
  }

  /// 预算派生值（可用额度 / 剩余 / 超支）。
  ///
  /// 大数字与进度条一律走 `budgetAvailable`：借入只抬可用额度，不改额度本身。
  BudgetStats budgetStats({int usedCents = 0, int borrowedInBudgetCents = 0}) =>
      SummaryService.budgetStats(
        totalCents: _budget.totalBudgetCents,
        usedCents: usedCents,
        borrowedInBudgetCents: borrowedInBudgetCents,
      );

  /// 借贷行的「应还 11-30」文案（没约定应还日返回 null）。
  String? dueLabelOf(int? debtId) {
    if (debtId == null) return null;
    for (final Debt d in <Debt>[..._debtList, ..._closedDebts]) {
      if (d.id != debtId) continue;
      final LocalDate? due = d.dueDate;
      if (due == null) return null;
      return '应还 ${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
    }
    return null;
  }

  /// 标记统计过期（记账后调用：**只打标记，不查统计**）。
  ///
  /// 两个口径一起打：同一笔记账会同时改变「本期」和「本月」。
  ///
  /// 打标记要**发一次通知**：图表页正是靠这次重建才挂上「帧后补算」的回调。
  /// 不发通知的话，用户切回图表页看到的永远是上一次的图（原版那个
  /// 「记完账图表不更新、杀掉重进才对」就是少了这一下）。
  void markStatsStale() {
    _statsStale[StatsScope.cycle] = true;
    _statsStale[StatsScope.month] = true;
    notifyListeners();
  }

  /// 重算当前口径的统计快照。失败保留旧值（不清空）。
  ///
  /// [force] 为 false 时只在「没算过 / 有脏标记」时动手 —— 页面每次 build 都调
  /// 也不会打库。
  Future<void> refreshStats({bool force = false}) async {
    final StatsScope scope = _statsScope;
    final Period range = statsPeriod;
    if (!force && !statsStale) return;

    try {
      final List<CategoryStat> expenseCats = await _stats.categoryStats(
        ledgerId: _ledgerId,
        from: range.fromIso,
        to: range.toIso,
      );
      final List<CategoryStat> incomeCats = await _stats.categoryStats(
        ledgerId: _ledgerId,
        from: range.fromIso,
        to: range.toIso,
        type: TxnType.income,
      );
      final RangeTotals totals = await _stats.rangeTotals(
        ledgerId: _ledgerId,
        from: range.fromIso,
        to: range.toIso,
      );
      // 近 6 段以**当前段末**为终点往前数，**1 条合并查询**
      final List<Period> segments = <Period>[
        for (int i = 5; i >= 0; i--)
          Period.shiftCycle(range, -i, statsScope == StatsScope.cycle ? _cycleStartDay : 1),
      ];
      final List<TrendSegment> trend = await _stats.trendTotals(
        ledgerId: _ledgerId,
        periods: segments,
      );
      final List<DailyTotal> daily = fillDailyRange(
        period: range,
        rows: await _stats.dailyTotals(
          ledgerId: _ledgerId,
          from: range.fromIso,
          to: range.toIso,
        ),
      );
      final int assets = await _stats.accountAssets();

      _snapshots[scope] = StatSnapshot(
        scope: scope,
        period: range,
        loaded: true,
        expenseCents: totals.expenseCents,
        incomeCents: totals.incomeCents,
        expenseCats: expenseCats,
        incomeCats: incomeCats,
        daily: daily,
        trend: trend,
        accountAssetsCents: assets,
        computedAt: DateTime.now(),
      );
      _statsStale[scope] = false;
      notifyListeners();
    } catch (_) {
      // 失败保留上一次快照（界面上「旧数据」而不是空白）。
      // 脏标记**不清**：下次进页面还会再试一次。
    }
  }

  /// 旧名兼容：等价于 [refreshStats]。
  Future<void> recomputeStats() => refreshStats(force: true);

  /// 补记到期账单（三道闸）。
  ///
  /// 返回新增笔数。同一天同一本账只扫一次；并发调用复用同一个 Future。
  Future<int> catchUp({LocalDate? today}) async {
    final LocalDate now = today ?? LocalDate.today();
    if (_scannedOn[_ledgerId] == now) return 0;
    final Future<int>? running = _inFlight;
    if (running != null) return running;

    final Future<int> future = _runCatchUp(now);
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
    }
  }

  /// **手动补记**：绕过闸一、只走闸二。
  ///
  /// 为什么必须绕闸一：闸一是「这本账今天扫过了」的内存标记，自动补记用它挡重复；
  /// 但用户点「立刻补记」是**明确的指令**，被这个标记静默挡掉的表现就是
  /// 「按了没反应」—— 用户会以为功能坏了，然后再点三次。
  /// 闸二（在飞 Future 复用）和闸三（物理唯一索引）仍然在，不会重复记。
  Future<int> manualCatchUp({LocalDate? today}) async {
    final Future<int>? running = _inFlight;
    if (running != null) return running;
    final Future<int> future = _runCatchUp(
      today ?? LocalDate.today(),
      markScanned: false,
    );
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
    }
  }

  /// 回前台补记：与自动补记同一条路（走闸一，日期没变就是 0 次查询）。
  Future<int> catchUpOnResume({LocalDate? today}) => catchUp(today: today);

  Future<int> _runCatchUp(LocalDate now, {bool markScanned = true}) async {
    final int cycleStartDay = await _settings.cycleStartDay();
    final int added = await _recurring.runDueRecurring(
      ledgerId: _ledgerId,
      cycleStartDay: cycleStartDay,
      today: now,
    );
    if (markScanned) _scannedOn[_ledgerId] = now;
    if (added > 0) {
      await batchNotifyAsync<void>(() async {
        await _loadWithoutNotify();
        notifyListeners();
      });
    }
    return added;
  }

  /// 清空「今天扫过」游标（`wipeAllData` / 恢复之后必须调）。
  void resetScanCursor() {
    _scannedOn.clear();
    _inFlight = null;
  }
}
