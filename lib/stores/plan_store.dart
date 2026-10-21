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

/// 统计快照：**统计不在启动路径算**（§5.2）。
///
/// 页面先渲染上一次快照（骨架），后台重算完再替换；失败保留旧值不清空 ——
/// 原版「统计页首帧显示本期还没有数据」就是因为在首帧路径里同步算。
class StatSnapshot {
  const StatSnapshot({
    required this.period,
    required this.categories,
    required this.daily,
    required this.computedAt,
  });

  static const StatSnapshot empty = StatSnapshot(
    period: null,
    categories: <CategoryStat>[],
    daily: <DailyTotal>[],
    computedAt: null,
  );

  final Period? period;
  final List<CategoryStat> categories;
  final List<DailyTotal> daily;
  final DateTime? computedAt;

  bool get isEmpty => period == null;
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
  Period _period = Period(
    from: LocalDate.today().firstOfMonth,
    to: LocalDate.today().lastOfMonth,
  );

  BudgetStats _budget = BudgetStats.empty;
  List<Budget> _categoryBudgets = <Budget>[];
  Map<int, int> _spentByCategory = <int, int>{};
  List<Debt> _debtList = <Debt>[];
  RepaidIndex _repaidIndex = RepaidIndex.empty;
  List<Recurring> _recurringList = <Recurring>[];
  StatSnapshot _statsSnapshot = StatSnapshot.empty;
  bool _statsStale = true;

  /// 闸一：按**账本**记「今天扫过没有」。键不是全局时间戳 ——
  /// 全局时间戳会让 24h 内切到另一本账被误挡，那本账永远不补（原版踩过）。
  final Map<int, LocalDate> _scannedOn = <int, LocalDate>{};

  /// 闸二：在飞 Future 复用（冷启动与回前台撞车时不新开一条）。
  Future<int>? _inFlight;

  BudgetStats get budget => _budget;
  List<Budget> get categoryBudgets => _categoryBudgets;
  Map<int, int> get spentByCategory => _spentByCategory;
  List<Debt> get debts => _debtList;
  RepaidIndex get repaidIndex => _repaidIndex;
  List<Recurring> get recurring => _recurringList;
  StatSnapshot get stats => _statsSnapshot;
  bool get statsStale => _statsStale;

  /// 绑定账本与当期。
  Future<void> bind({
    required int ledgerId,
    required Period period,
  }) async {
    _ledgerId = ledgerId;
    _period = period;
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
    _debtList = await _debts.all(_ledgerId, includeClosed: false);
    _repaidIndex = await _debts.repaidIndex(_ledgerId);
    _recurringList = await _recurring.all(_ledgerId);

    // 分类预算的「已花」：只查设了预算的一级分类（含子分类）
    final List<int> topIds = <int>[
      for (final Budget b in _categoryBudgets)
        if (b.categoryId != null) b.categoryId!,
    ];
    _spentByCategory = await _budgets.spentByCategory(
      ledgerId: _ledgerId,
      period: _period,
      topCategoryIds: topIds,
    );
  }

  /// 分类预算列表 = **设了预算的 ∪ 本期有支出的一级分类**（口径 3.1）。
  Future<List<({Category category, int budgetCents, int spentCents})>>
  categoryBudgetRows() async {
    final CategoryTree tree = CategoryTree(await _categories.all(_ledgerId));
    final Set<int> ids = <int>{};
    for (final Budget b in _categoryBudgets) {
      if (b.categoryId != null) ids.add(b.categoryId!);
    }
    for (final Category c in tree.topsOf(TxnType.expense)) {
      if (c.id != null && (_spentByCategory[c.id] ?? 0) > 0) ids.add(c.id!);
    }

    final List<({Category category, int budgetCents, int spentCents})> rows =
        <({Category category, int budgetCents, int spentCents})>[];
    for (final int id in ids) {
      final Category? c = tree.byId(id);
      if (c == null || c.archived) continue;
      final int budgetCents = _categoryBudgets
          .where((Budget b) => b.categoryId == id)
          .fold<int>(0, (int a, Budget b) => a + b.amountCents);
      rows.add((
        category: c,
        budgetCents: budgetCents,
        spentCents: _spentByCategory[id] ?? 0,
      ));
    }
    rows.sort((a, b) => a.category.sortOrder.compareTo(b.category.sortOrder));
    return rows;
  }

  /// 预算派生值（可用额度 / 剩余 / 超支）。
  BudgetStats budgetStats({int usedCents = 0, int borrowedInBudgetCents = 0}) =>
      SummaryService.budgetStats(
        totalCents: _budget.totalBudgetCents,
        usedCents: usedCents,
        borrowedInBudgetCents: borrowedInBudgetCents,
      );

  /// 借贷行的「应还 11-30」文案（没约定应还日返回 null）。
  String? dueLabelOf(int? debtId) {
    if (debtId == null) return null;
    for (final Debt d in _debtList) {
      if (d.id != debtId) continue;
      final LocalDate? due = d.dueDate;
      if (due == null) return null;
      return '应还 ${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
    }
    return null;
  }

  /// 标记统计过期（记账后调用：**只打标记，不查统计**）。
  void markStatsStale() {
    _statsStale = true;
  }

  /// 重算统计快照。失败保留旧值（不清空）。
  Future<void> recomputeStats() async {
    try {
      final List<CategoryStat> categories = await _stats.categoryStats(
        ledgerId: _ledgerId,
        from: _period.fromIso,
        to: _period.toIso,
      );
      final List<DailyTotal> daily = await _stats.dailyTotals(
        ledgerId: _ledgerId,
        from: _period.fromIso,
        to: _period.toIso,
      );
      _statsSnapshot = StatSnapshot(
        period: _period,
        categories: categories,
        daily: daily,
        computedAt: DateTime.now(),
      );
      _statsStale = false;
      notifyListeners();
    } catch (_) {
      // 失败保留上一次快照（界面上「旧数据 + 一个重试」，而不是空白）
    }
  }

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

  Future<int> _runCatchUp(LocalDate now) async {
    final int cycleStartDay = await _settings.cycleStartDay();
    final int added = await _recurring.runDueRecurring(
      ledgerId: _ledgerId,
      cycleStartDay: cycleStartDay,
      today: now,
    );
    _scannedOn[_ledgerId] = now;
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
