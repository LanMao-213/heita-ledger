// foundation 里也有一个 Category 注解类，会和数据模型重名，这里隐藏掉
import 'package:flutter/foundation.dart' hide Category;

import 'data/db.dart';
import 'data/cycle.dart' as cyc;
import 'data/models.dart';
import 'data/repo.dart';
import 'data/repo_stats.dart';
import 'data/ui_flags.dart';
import 'design/haptics.dart';
import 'design/palette.dart';
import 'design/theme_ctrl.dart';

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

  /// 触感反馈开关（我的 → 偏好）。真正的执行点在 `Haptics.enabled`，
  /// 这里只是给界面读的那份副本 + 落库。
  bool hapticsEnabled = true;

  static const _kHaptics = 'ui.haptics';

  /// 改开关：立即生效（内存）+ 落库（下次启动还记得）。
  Future<void> setHapticsEnabled(bool on) async {
    hapticsEnabled = on;
    Haptics.enabled = on;
    notifyListeners();
    await Repo.setSetting(_kHaptics, on ? '1' : '0');
  }

  /// 当前主题（我的 → 偏好 → 主题）。
  ///
  /// 真正的执行点是 `ThemeCtrl`（设计层读的是它），这里同样是「界面读的副本 +
  /// 落库」。出厂默认 [kDefaultTheme]（黑塔·永夜），老库没有这个键就用它。
  HeitaThemeId themeId = kDefaultTheme;

  static const _kTheme = 'ui.theme';

  /// 换肤：先让 ThemeCtrl 通知整树重建，再落库。
  ///
  /// 顺序不能反 —— `apply()` 会触发 `app.dart` 的 AnimatedBuilder，
  /// 此时 [themeId] 必须是新值，否则「我的」页那一行会先跳回旧值再跳回来。
  Future<void> setTheme(HeitaThemeId id) async {
    themeId = id;
    ThemeCtrl.i.apply(id);
    notifyListeners();
    await Repo.setSetting(_kTheme, id.name);
  }

  /// 底部导航当前页：0 明细 / 1 图表 / 2 计划 / 3 我的。
  /// 放在 Store 里是为了让统计页「点某天看明细」能跨页切 Tab，
  /// 而不用给 HomeShell 开一个谁都能调的全局 key。
  int tabIndex = 0;

  // ------------------------------------------------------- 通知合并（1.4.5）
  //
  // `loadCycle()` 和 `loadStats()` 各自 `notifyListeners()`，所以「记一笔」
  // 会连着触发两次全树重建 —— 而用户真正需要的只是「最后那一次新状态」。
  // 中间那次重建的内容永远会被立刻覆盖，纯属白干。
  //
  // 这里用一个深度计数把一次操作里的多次通知压成一次：[batchNotify] 结束前
  // 不往外发，结束后只发一次。注意是**合并**不是节流 —— 不会延后到下一帧，
  // 所以界面手感不变。

  int _notifyDepth = 0;
  bool _notifyPending = false;

  @override
  void notifyListeners() {
    if (_notifyDepth > 0) {
      _notifyPending = true;
      return;
    }
    super.notifyListeners();
  }

  /// 把 [body] 里的多次通知合并成一次（在 body 结束后立即发出）。
  Future<T> batchNotify<T>(Future<T> Function() body) async {
    _notifyDepth++;
    try {
      return await body();
    } finally {
      _notifyDepth--;
      if (_notifyDepth == 0 && _notifyPending) {
        _notifyPending = false;
        super.notifyListeners();
      }
    }
  }

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
  // 两级分类（v6 起）：[allExpenseCats] 含「使用中」的全部节点（一级 + 子级），
  // 用于按 id 反查；[expenseCats] 只留一级 —— 筛选面板、预算、分类管理、录入左轮
  // 要的都是一级，混着子分类列出来会出现「餐饮」和「正餐」并排的怪状。
  List<Category> allExpenseCats = [];
  List<Category> allIncomeCats = [];
  List<Category> expenseCats = [];
  List<Category> incomeCats = [];

  // 已停用的分类单独放：选择器、预算、统计一律不碰它们，
  // 只有分类管理页要在「已停用」那一段里列出来好让用户恢复。
  List<Category> archivedExpenseCats = [];
  List<Category> archivedIncomeCats = [];

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

  /// 明细一次最多取多少条（安全上限，不是产品上限）。
  ///
  /// 1.4.5 之前这里是 500，而且**必须**卡住：明细页当时是
  /// `ListView(children: [...])` 的非懒加载列表，一期几千笔会一次性构建所有行。
  /// 现在明细页改成 `SliverList.builder`，只建可视区域内的那几张日卡，
  /// 分摊成本与总条数无关，所以上限提到 2000 只当「防止一次查询把内存打爆」的
  /// 兜底 —— 一个月的个人记账几乎不可能碰到。
  ///
  /// 真碰到也不会静默丢：列表末尾仍是「仅显示最近 N 条 · 本期共 M 笔」+
  /// 「查看本期全部」（`pages/period_all_page.dart`）。
  static const txnPageLimit = 2000;

  /// 本期明细是否被 [txnPageLimit] 截断了 —— 截断了列表末尾要说明白
  bool txnTruncated = false;
  List<Txn> txns = [];

  /// 借贷往来（带派生的已还金额）。
  ///
  /// 明细行据此把流水显示成「借出 · 张三」而不是红色支出，往来卡片也读它 ——
  /// 共用一个缓存，避免两处各查一次、口径还不一致。
  List<Debt> debts = [];
  Map<int, Debt> _debtById = {};

  /// 按 id 取往来；普通流水返回 null（明细行据此决定用哪种渲染）
  Debt? debtOf(int? id) => id == null ? null : _debtById[id];

  /// 未结清的应收合计（别人欠我）
  int get receivableCents => debts
      .where((d) => !d.isClosed && d.direction.isReceivable)
      .fold(0, (a, d) => a + d.remainingCents);

  /// 未结清的应付合计（我欠别人）
  int get payableCents => debts
      .where((d) => !d.isClosed && !d.direction.isReceivable)
      .fold(0, (a, d) => a + d.remainingCents);

  /// 含往来的净资产：账户余额 + 应收 − 应付。
  ///
  /// 借出会让账户余额变少，但不该让「我有多少钱」跟着变少 —— 钱只是从
  /// 现金换成了「别人欠我」。只减余额不加应收，用户会以为钱丢了。
  int get netWorthWithDebtCents =>
      netWorthCents + receivableCents - payableCents;

  /// 抬期池分类 id（工资/奖金/提成）：记一笔面板用它给开关一个默认值
  Set<int> liftableCatIds = {};

  /// 当前期的预算（预算也按周期，D13 已改）
  int? totalBudgetCents;

  /// 上一期的支出合计、笔数、天数 —— **只在当前期没设预算时**才有值。
  ///
  /// 明细页底栏在没预算的期换成「日均 / 环比上一期」的小总结，环比要用它。
  /// 有预算的期这个字段恒为 null，`loadCycle` 也不会为它多查一次库 ——
  /// 一次记账要跑 loadCycle，不能为了一个不显示的文案给它加查询。
  ({int expense, int count, int days})? prevPeriod;

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

  /// 补记的第一道闸：**每个账本**最近一次扫到哪一天。
  ///
  /// 按账本分开记，不是全局一个时间戳。全局的话，今天在「日常账本」补过，
  /// 24 小时内切到「家庭账本」就会被误挡，那本账的房租永远等不到补记 ——
  /// 这也顺带修掉了「切换账本从来不补」这个从 1.1.0 就在的老问题。
  final Map<int, String> _recurringDoneOn = {};

  /// 补记的第二道闸：同一时刻只允许一次在跑。
  ///
  /// 冷启动与「从后台回来」可能几乎同时触发，而 [Repo.runDueRecurring]
  /// 不是原子的。重入时复用同一个 Future，不新开一条。
  Future<int>? _recurringInFlight;

  /// 上一次见到的「今天」和账本 —— 回到前台时拿它判断要不要重算
  String _seenDay = '';
  int _seenLedgerId = 0;

  /// 测试用：假装上一次是另一天（真实值只由 boot / onAppResumed / switchLedger 维护）。
  /// 没有时钟注入点，跨天场景只能靠这个缝来模拟。
  @visibleForTesting
  void debugSetSeenDay(String day) {
    _seenDay = day;
  }

  /// 测试用：清空「今天这个账本已经扫过」的标记，等价于时间过去了。
  @visibleForTesting
  void debugResetRecurringGates() {
    _recurringDoneOn.clear();
    _recurringInFlight = null;
  }

  /// 是否要提示「分类升级成两级了」。只在真的从老库升上来、且没提示过时为真。
  bool catsUpgradeJustDone = false;

  static const _kCatsNotice = 'ui.cats_two_level_notice';

  Ledger? get currentLedger {
    for (final l in ledgers) {
      if (l.id == ledgerId) return l;
    }
    return ledgers.isEmpty ? null : ledgers.first;
  }

  /// 本期「计入预算」的借入本金合计。
  ///
  /// 借贷流水一律不进收支统计，但用户勾了「计入预算」的那笔借入是**真能花**的钱。
  /// 不把它加进可用额度，就会出现「账户里明明多了 3000，预算卡却说你快超支了」。
  /// 借出恒不计入 —— 钱出去了，不是可花的钱。
  int get borrowedInBudgetCents {
    var sum = 0;
    for (final d in debts) {
      if (d.direction.isReceivable) continue;
      if (!d.countInBudget) continue;
      if (cycleFrom.isEmpty || cycleTo.isEmpty) continue;
      // 只算本期借入的；上期借的钱不该抬这一期的额度
      if (d.date.compareTo(cycleFrom) < 0 || d.date.compareTo(cycleTo) > 0) {
        continue;
      }
      sum += d.amountCents;
    }
    return sum;
  }

  /// 本期可用额度 = 预算额度 + 计入预算的借入本金。
  ///
  /// **预算额度本身不动**（那是用户自己设的数，不该被借款改写），
  /// 借入只是把「能花多少」抬上去，并在卡片上单列一行说明。
  int get budgetAvailableCents =>
      (totalBudgetCents ?? 0) + borrowedInBudgetCents;

  int get budgetLeftCents =>
      totalBudgetCents == null ? 0 : budgetAvailableCents - expenseCents;

  bool get overBudget =>
      totalBudgetCents != null && expenseCents > budgetAvailableCents;

  int get overBudgetCents =>
      overBudget ? expenseCents - budgetAvailableCents : 0;

  /// 正在进行的 boot（并发去重用，结束即清空）
  Future<void>? _booting;

  /// 首屏启动：建表/开库 → 补归属期 → 补记周期账单 → 载入全部数据
  ///
  /// **并发调用复用同一个 Future**（1.4.22）。原因：boot 中途要切皮肤，
  /// 切皮肤会通知 `ThemeCtrl`，`app.dart` 里 `_BootGate` 的 key 绑着主题 id，
  /// 一变整棵子树重建 —— 新 State 的 initState 会再调一次 `boot()`。
  /// 重复 boot 会把补记账单再跑一遍、再全量查一遍，测试里甚至直接卡在启动页。
  /// 所以这里做单飞去重；`ready` 之后再次调用仍然照常重跑（测试要靠这个
  /// 换库），只挡住「同时进行中的第二次」。
  Future<void> boot() {
    final inflight = _booting;
    if (inflight != null) return inflight;
    final f = _doBoot().whenComplete(() => _booting = null);
    _booting = f;
    return f;
  }

  Future<void> _doBoot() async {
    await Db.open();
    // v3 → v4 升级后 `period_start` 是空的，先补齐。账单日默认 1 时回填结果
    // 等于月初，与升级前完全一致 —— 这一步不改任何查询口径。
    await Repo.backfillMissingPeriods();
    // 界面实验开关（空态第二行）从 setting 表读覆盖值
    await UiFlags.load();
    // 触感开关：只有存过 '0' 才算关。老库没有这个键 → 保持默认开
    hapticsEnabled = (await Repo.getSetting(_kHaptics)) != '0';
    Haptics.enabled = hapticsEnabled;
    // 主题：读不到（老库）或读到无效值都回落到出厂默认。
    //
    // 读到就立刻切（会通知全树重建），必须在这里切而不是等 boot 结束：
    // `MaterialApp` 早在 `_BootGate` 之前就建好了，用的还是出厂色板。不发通知
    // 的话，页面（读 `C.xxx` getter）是用户选的皮肤，而 ThemeData（弹层底、
    // 对话框、AppBar）永远停在出厂那套 —— 亮色皮肤点「账户管理」会看到
    // 永夜的深紫黑底配本皮肤的深绯紫字，深底叠深字几乎读不出来。
    //
    // 此刻还在启动页，通知引起的整树重建看不出来（`boot()` 单飞，新 State
    // 复用同一个 Future，不会再跑一遍补记与查询）。
    themeId = themeIdFromString(await Repo.getSetting(_kTheme));
    ThemeCtrl.i.apply(themeId);
    ledgerId = await Repo.currentLedgerId();
    cycleStartDay = await Repo.cycleStartDay();
    resetCycleToToday();
    _seenDay = Fmt.date(DateTime.now());
    _seenLedgerId = ledgerId;
    recurringJustAdded = await catchUpRecurring();

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

  /// 从后台回到前台：日期或账本变了，就重算游标并补记周期账单。
  ///
  /// 为什么必须有：这个应用没有后台服务（见 `Repo.runDueRecurring` 的注释），
  /// 所有「到点该做的事」都挂在「打开应用」这一刻。而 Android 上应用常驻后台
  /// 过夜是常态 —— 少了这个钩子，周期条会停在昨天、到期的房租要等下次冷启动
  /// 才补记，中间那几天余额和预算全是错的。
  ///
  /// 返回补记的条数（0 = 没有新东西），交给界面决定要不要提示。
  Future<int> onAppResumed() async {
    if (!ready) return 0;
    final today = Fmt.date(DateTime.now());
    final ledgerChanged = ledgerId != _seenLedgerId;
    // 同一天 + 同一个账本：什么都不用做。这就是「按账本各自核对一次」
    if (today == _seenDay && !ledgerChanged) return 0;

    // 先记下「我当时停在哪一期」，再决定要不要拨 ——
    // 拨完之后 isCurrentPeriod 就变了，判断会失真
    final wasCurrent = isCurrentPeriod;
    _seenDay = today;
    _seenLedgerId = ledgerId;

    // 只在用户本来就停在「当前期」时才把游标拨到今天。
    // 他若正翻 9 月的旧账，切出去回条微信再回来被拽回本月，等于抢方向盘。
    if (wasCurrent) resetCycleToToday();

    final added = await catchUpRecurring();
    if (added > 0) recurringJustAdded = added;
    await loadCycle(); // 内部会 notify 一次，这里不再重复
    return added;
  }

  /// 补记到期周期账单，带两道防重复闸（见 [_recurringDoneOn] / [_recurringInFlight]）。
  ///
  /// 「多久查一次」「会不会同时跑两次」是应用层的事，不该塞进
  /// [Repo.runDueRecurring] —— 那个方法只负责「该记什么」。
  Future<int> catchUpRecurring() {
    final today = Fmt.date(DateTime.now());

    // 闸一：这个账本今天已经扫过
    if (_recurringDoneOn[ledgerId] == today) {
      return _recurringInFlight ?? Future<int>.value(0);
    }
    // 闸二：已有一次在跑就复用它，不新开
    final running = _recurringInFlight;
    if (running != null) return running;

    final f = _runCatchUp(today);
    _recurringInFlight = f;
    return f.whenComplete(() {
      if (identical(_recurringInFlight, f)) _recurringInFlight = null;
    });
  }

  Future<int> _runCatchUp(String today) async {
    final id = ledgerId;
    final added = await Repo.runDueRecurring(id);
    _recurringDoneOn[id] = today;

    // 补记会动账户余额：界面上的净值必须跟着重算，
    // 否则用户看到的是「明细里多了一笔房租，余额却没动」
    if (id == ledgerId) {
      accounts = await Repo.listAccounts();
      netWorthCents = await Repo.totalBalanceCents();
    }
    return added;
  }

  /// 把当前期拨回「今天所在的那一期」
  void resetCycleToToday() {
    final (from, to) = cyc.cycleRange(DateTime.now(), cycleStartDay);
    cycleFrom = from;
    cycleTo = to;
  }

  /// 回到「今天所在的期」。翻了好几期之后一键回来（双击周期条触发）。
  Future<void> backToCurrentCycle() async {
    resetCycleToToday();
    await loadCycle();
  }

  /// 统计页回到当前：按本期 → 今天所在的期；按月 → 本月。
  ///
  /// 两种口径各回各的「当前」，不互相干扰 —— 按月看的时候双击不该把
  /// 周期口径的游标也一起挪了。
  Future<void> backToCurrentStat() async {
    if (statBasis == StatBasis.period) {
      resetCycleToToday();
    } else {
      month = Fmt.month(DateTime.now());
    }
    await loadStats();
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

  /// 取上一期的支出合计（只给「没设预算的期」的小总结用）。
  ///
  /// **有预算的期直接清空、一次都不查** —— `loadCycle` 每次记账都要跑，
  /// 不能为了一条不显示的文案给它加一次查询。
  Future<void> _loadPrevPeriod() async {
    if (totalBudgetCents != null || cycleFrom.isEmpty) {
      prevPeriod = null;
      return;
    }
    final prevFrom = cyc.shiftCycleDate(cycleFrom, cycleStartDay, -1);
    final prevTo = Fmt.date(
      cyc
          .shiftCycle(DateTime.parse(prevFrom), cycleStartDay, 1)
          .subtract(const Duration(days: 1)),
    );
    final t = await RepoStats.rangeTotals(ledgerId, prevFrom, prevTo);
    prevPeriod = (
      expense: t.$1,
      count: t.$3,
      // 期长现算：环比比的是日均，分母不能借用这一期的天数
      days:
          DateTime.parse(prevTo).difference(DateTime.parse(prevFrom)).inDays + 1,
    );
  }

  /// 载入当前期：明细页、计划页、预算都看这一份
  Future<void> loadCycle() async {
    final totals = await RepoStats.rangeTotals(ledgerId, cycleFrom, cycleTo);
    expenseCents = totals.$1;
    incomeCents = totals.$2;
    txnCount = totals.$3;
    totalBudgetCents = await Repo.totalBudgetCents(ledgerId, cycleFrom);
    await _loadPrevPeriod();
    budgetStats = await RepoStats.budgetStats(
      ledgerId: ledgerId,
      periodStart: cycleFrom,
      from: cycleFrom,
      to: cycleTo,
    );
    // 多取一条只为判断有没有被截断：只比较条数的话，
    // 「正好 500 条」和「500 条之外还有」在调用方无法区分
    txns = await Repo.rangeListTxns(
      ledgerId: ledgerId,
      from: cycleFrom,
      to: cycleTo,
      limit: txnPageLimit + 1,
    );
    txnTruncated = txns.length > txnPageLimit;
    if (txnTruncated) txns = txns.sublist(0, txnPageLimit);
    isCurrentPeriod = cyc.isCurrentCycle(cycleFrom, cycleTo);
    notifyListeners();
  }

  /// 载入统计页数据。口径由 [statBasis] 决定，字段也单独存（`stat*`），
  /// 所以切换口径不会动到明细页的数字。
  Future<void> loadStats() async {
    final byPeriod = statBasis == StatBasis.period;
    statFrom = byPeriod ? cycleFrom : Fmt.monthStart(month);
    statTo = byPeriod ? cycleTo : Fmt.monthEnd(month);
    final basis = byPeriod ? DateBasis.period : DateBasis.date;

    final totals = await RepoStats.rangeTotals(
      ledgerId,
      statFrom,
      statTo,
      basis: basis,
    );
    statExpenseCents = totals.$1;
    statIncomeCents = totals.$2;
    statExpenseStats = await RepoStats.rangeCategoryStats(
      ledgerId: ledgerId,
      from: statFrom,
      to: statTo,
      type: TxnType.expense,
      basis: basis,
    );
    statIncomeStats = await RepoStats.rangeCategoryStats(
      ledgerId: ledgerId,
      from: statFrom,
      to: statTo,
      type: TxnType.income,
      basis: basis,
    );
    statDailyTotals = await RepoStats.rangeDailyTotals(
      ledgerId,
      statFrom,
      statTo,
      basis: basis,
    );
    statTrend = byPeriod
        ? await RepoStats.recentPeriods(
            ledgerId: ledgerId,
            endFrom: cycleFrom,
            startDay: cycleStartDay,
            count: 6,
          )
        : await RepoStats.recentMonths(
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

  /// 切账本。返回补记的周期账单条数（0 = 这本账没有欠账）。
  Future<int> switchLedger(int id) async {
    ledgerId = id;
    // 分类 ID 属于账本：带着旧条件切过去只会筛出空结果或错数据
    _resetFilter();
    await Repo.setSetting('current_ledger_id', '$id');
    await loadAll();

    // 切过来的这本账可能已经欠着好几期的周期账单。
    // 1.4.3 之前这里什么都不做 —— 只有冷启动才补，等于「一个账本永远不补」。
    _seenDay = Fmt.date(DateTime.now());
    _seenLedgerId = id;
    final added = await catchUpRecurring();
    if (added > 0) {
      recurringJustAdded = added;
      await loadCycle(); // 补进来的记录要立刻出现在列表和概览里
    }
    return added;
  }

  /// 记一笔 / 改一笔 / 删一笔之后统一调这个刷新
  Future<void> afterTxnChange() async {
    // 一次记账要动账户、往来、本期明细、统计四块，逐个刷新会各发一次通知
    // （`loadCycle` / `loadStats` 内部都会 notify）。合并成一次重建，
    // 界面看到的最终结果完全一样，中间那几次是白建的。
    await batchNotify(() async {
      accounts = await Repo.listAccounts();
      netWorthCents = await Repo.totalBalanceCents();
      // 借贷的「已还多少」是按流水算的，动过流水就得重算
      await _loadDebts();
      await loadCycle();
      await loadStats();
      // 筛选态下必须重跑，否则删掉的记录还会挂在结果里
      if (filtering) await applyFilter(filter);
    });
  }

  /// 新记一笔之后的收口：**保证这笔一定出现在明细里**。
  ///
  /// 1.4.1 的问题：明细列表读的是「当前这一期的 txn」（`rangeListTxns` 按
  /// `period_start` 过滤），而保存成功只刷新数据、不动游标。于是有三种情况
  /// 会「记完看不见」：
  /// 1. 之前左右划过周期条，游标停在别的期；
  /// 2. 这笔收入被「工资抬期」（D22-R1）自动算进了下一期；
  /// 3. 明细上还挂着筛选条件（筛「餐饮」时记了一笔交通）。
  ///
  /// 三种都表现为「输入金额、点确认、什么都没发生」。用户的下一步动作是
  /// 再记一遍 —— 所以这里不再让界面自己猜，而是把视角直接搬到这笔身上：
  /// 清筛选 → 游标对齐到这笔所在的期 → 切回明细页。
  ///
  /// [periodStart] 由调用方按 [periodStartOf] 算好传进来（和 `Repo.periodFor`
  /// 同一口径，含抬期），不在这里重新推断，免得两处口径漂移。
  Future<void> afterTxnInserted({
    required String date,
    required String periodStart,
  }) async {
    _resetFilter();
    if (periodStart != cycleFrom) {
      final (from, to) = cyc.cycleRange(
        DateTime.parse(periodStart),
        cycleStartDay,
      );
      cycleFrom = from;
      cycleTo = to;
    }
    // 从图表/计划页的 FAB 记的账也一样：跳回明细，否则「记完看不见」只是换个形式
    tabIndex = 0;
    await afterTxnChange();
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
    final expAll = await Repo.listCategories(
      ledgerId,
      type: TxnType.expense,
      includeArchived: true,
    );
    final incAll = await Repo.listCategories(
      ledgerId,
      type: TxnType.income,
      includeArchived: true,
    );
    // 停用的不进 [allExpenseCats]：那些列表喂的是选择器、预算和统计，
    // 停用的分类出现在那里就等于没停用。
    archivedExpenseCats = [
      for (final c in expAll)
        if (c.archived) c,
    ];
    archivedIncomeCats = [
      for (final c in incAll)
        if (c.archived) c,
    ];
    allExpenseCats = [
      for (final c in expAll)
        if (!c.archived) c,
    ];
    allIncomeCats = [
      for (final c in incAll)
        if (!c.archived) c,
    ];
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
    // 预算被删掉时这个期会切到「小总结」底栏，环比数据要跟着补上
    await _loadPrevPeriod();
    budgetStats = await RepoStats.budgetStats(
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
    // 停用的也要能反查到：历史流水、模板、周期账单都还指着它，
    // 查不到就会被渲染成「已删除分类」。
    for (final c in archivedExpenseCats) {
      if (c.id == id) return c;
    }
    for (final c in archivedIncomeCats) {
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

  /// 某一类型下已停用的一级分类 —— 只有分类管理页用得上
  List<Category> archivedTopCats(TxnType type) =>
      _topOnly(type.isExpense ? archivedExpenseCats : archivedIncomeCats);

  /// 某个一级分类下已停用的子分类
  List<Category> archivedChildrenOf(int parentId) => [
    for (final c in archivedExpenseCats)
      if (c.parentId == parentId) c,
    for (final c in archivedIncomeCats)
      if (c.parentId == parentId) c,
  ];

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
    // 库都换了：账本 id 和「今天补到哪」都作废，留着会让新库被旧时间戳挡住
    _recurringDoneOn.clear();
    _recurringInFlight = null;
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
