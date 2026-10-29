// foundation 里也有一个 Category 注解类，会和数据模型重名，这里隐藏掉
import 'package:flutter/foundation.dart' hide Category;

import 'data/db.dart';
import 'data/cycle.dart' as cyc;
import 'data/excel_service.dart';
import 'data/goal_projection.dart';
import 'data/integrity.dart';
import 'data/models.dart';
import 'data/repo.dart';
import 'data/repo_stats.dart';
import 'data/ui_flags.dart';
import 'design/haptics.dart';
import 'design/palette.dart';
import 'design/theme_ctrl.dart';
part 'store/state.dart';
part 'store/actions.dart';

part 'store/views.dart';

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

  bool _ready = false;

  /// 触感反馈开关（我的 → 偏好）。真正的执行点在 `Haptics.enabled`，
  /// 这里只是给界面读的那份副本 + 落库。
  bool _hapticsEnabled = true;

  static const _kHaptics = 'ui.haptics';

  /// 改开关：立即生效（内存）+ 落库（下次启动还记得）。
  Future<void> setHapticsEnabled(bool on) async {
    _hapticsEnabled = on;
    Haptics.enabled = on;
    notifyListeners();
    await Repo.setSetting(_kHaptics, on ? '1' : '0');
  }

  /// 当前主题（我的 → 偏好 → 主题）。
  ///
  /// 真正的执行点是 `ThemeCtrl`（设计层读的是它），这里同样是「界面读的副本 +
  /// 落库」。出厂默认 [kDefaultTheme]（圣地 · 审判白），老库没有这个键就用它。
  HeitaThemeId _themeId = kDefaultTheme;

  // ------------------------------------------------------------- 默认支出账户
  //
  // 记账面板新建一笔时用哪个账户做初值（「我的 → 账户管理 → 设为默认支出」）。
  //
  // 为什么不存账户名：账户可以改名，存名字会在改名那一刻变成死引用。存 id 之后
  // 「账户被删」是唯一一种会让它失效的情况，而那一档在读取处回落即可
  // （见 `record_sheet.dart` 的 `_initialAccountId`）—— 比在删除流程里加一条
  // 「顺手清理设置」的联动少一处会漏的地方。

  /// 默认支出账户 id；null = 没设过（或存的不是数字）。
  int? _defaultExpenseAccountId;

  static const _kDefaultExpenseAccount = 'default_expense_account';

  static const _kTheme = 'ui.theme';

  /// 「界面默认皮肤是『圣地 · 审判白』，可在『我的 → 主题』换回」这条一次性提示的落库标记。
  ///
  /// 与 [_kTheme] 分开一个键，是因为两者语义不同：`ui.theme` 记的是「用户选了哪套」，
  /// 这里记的是「用户见过这条说明没有」。共用一个键会导致「用户手动选了默认那套」
  /// 被误判成「已经被告知过」。
  static const _kThemeNotice = 'ui.theme_notice';

  /// 皮肤默认值的变更日（1.5.1 发布日）。
  ///
  /// 只服务 [_kThemeNotice] 这一条判据：这一版把出厂默认从「黑塔 · 永夜」改成
  /// 「圣地 · 审判白」，需要被提醒的只有**升级上来的老用户**，而"谁升级过"
  /// 无从查询 —— 能用的只有时间线，判据见 `_doBoot` 里那段注释。
  ///
  /// 将来默认值再变一次，除了改这个日期，还得把 `ui.theme_notice` 换个新键：
  /// 旧标记已经躺在老用户的库里，沿用同一个键会让新提示永远不触发。
  static const _defaultSkinChangedAt = '2026-10-28';

  /// 换肤：先让 ThemeCtrl 通知整树重建，再落库。
  ///
  /// 顺序不能反 —— `apply()` 会触发 `app.dart` 的 AnimatedBuilder，
  /// 此时 [_themeId] 必须是新值，否则「我的」页那一行会先跳回旧值再跳回来。
  Future<void> setTheme(HeitaThemeId id) async {
    _themeId = id;
    ThemeCtrl.i.apply(id);
    notifyListeners();
    await Repo.setSetting(_kTheme, id.name);
  }

  /// 底部导航当前页：0 明细 / 1 图表 / 2 计划 / 3 我的。
  /// 放在 Store 里是为了让统计页「点某天看明细」能跨页切 Tab，
  /// 而不用给 HomeShell 开一个谁都能调的全局 key。
  int _tabIndex = 0;

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
    if (_tabIndex == i) return;
    _tabIndex = i;
    notifyListeners();
  }

  // 账本
  List<Ledger> _ledgers = [];
  int _ledgerId = 0;

  // 账户
  List<Account> _accounts = [];
  int _netWorthCents = 0;

  // 分类
  //
  // 两级分类（v6 起）：[_allExpenseCats] 含「使用中」的全部节点（一级 + 子级），
  // 用于按 id 反查；[_expenseCats] 只留一级 —— 筛选面板、预算、分类管理、录入左轮
  // 要的都是一级，混着子分类列出来会出现「餐饮」和「正餐」并排的怪状。
  List<Category> _allExpenseCats = [];
  List<Category> _allIncomeCats = [];
  List<Category> _expenseCats = [];
  List<Category> _incomeCats = [];

  // 已停用的分类单独放：选择器、预算、统计一律不碰它们，
  // 只有分类管理页要在「已停用」那一段里列出来好让用户恢复。
  List<Category> _archivedExpenseCats = [];
  List<Category> _archivedIncomeCats = [];

  // 记账模板（_templates 按管理页顺序，_recentTemplates 按使用频率取前 3）
  List<TxnTemplate> _templates = [];
  List<TxnTemplate> _recentTemplates = [];

  // 储蓄目标
  List<SavingGoal> _goals = [];

  /// 储蓄目标的存/取流水，按 `goal_id` 分好组。
  ///
  /// 分组放在加载时做一次，而不是每张卡片自己去查：计划页一屏可能有 5 个目标，
  /// 每次 rebuild 都查一遍库会让滚动明显发涩。目标数量本来就是个位数，
  /// 全量取回的内存代价可以忽略。
  Map<int, List<GoalFlow>> _goalFlows = const {};

  // ---------------------------------------------------------------- 周期 / 月
  //
  // 明细页与计划页（预算）看的是**当前期**：`_cycleFrom`–`_cycleTo`。
  // 统计页可以在「本期 / 本月」之间切换，所以它另有一套 `stat*` 字段 ——
  // 两套分开存，切换统计数据时不会把明细页的数字带歪。

  /// 账单日（周期起始日），1–31，默认 1（= 自然月）
  int _cycleStartDay = 1;

  /// 当前期首尾日期（`YYYY-MM-DD`，含两端）
  String _cycleFrom = '';
  String _cycleTo = '';

  /// 当前期是否包含今天
  bool _isCurrentPeriod = true;

  /// 当前期的收支与明细
  int _expenseCents = 0;
  int _incomeCents = 0;
  int _txnCount = 0;

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
  bool _txnTruncated = false;
  List<Txn> _txns = [];

  /// 借贷往来（带派生的已还金额）。
  ///
  /// 明细行据此把流水显示成「借出 · 张三」而不是红色支出，往来卡片也读它 ——
  /// 共用一个缓存，避免两处各查一次、口径还不一致。
  List<Debt> _debts = [];
  Map<int, Debt> _debtById = {};

  /// 按 id 取往来；普通流水返回 null（明细行据此决定用哪种渲染）
  Debt? debtOf(int? id) => id == null ? null : _debtById[id];

  /// 未结清的应收合计（别人欠我）
  int get receivableCents => _debts
      .where((d) => !d.isClosed && d.direction.isReceivable)
      .fold(0, (a, d) => a + d.remainingCents);

  /// 未结清的应付合计（我欠别人）
  int get payableCents => _debts
      .where((d) => !d.isClosed && !d.direction.isReceivable)
      .fold(0, (a, d) => a + d.remainingCents);

  /// 含往来的净资产：账户余额 + 应收 − 应付。
  ///
  /// 借出会让账户余额变少，但不该让「我有多少钱」跟着变少 —— 钱只是从
  /// 现金换成了「别人欠我」。只减余额不加应收，用户会以为钱丢了。
  int get netWorthWithDebtCents =>
      _netWorthCents + receivableCents - payableCents;

  /// 抬期池分类 id（工资/奖金/提成）：记一笔面板用它给开关一个默认值
  Set<int> _liftableCatIds = {};

  /// 当前期的预算（预算也按周期，D13 已改）
  int? totalBudgetCents;

  /// 上一期的支出合计、笔数、天数 —— **只在当前期没设预算时**才有值。
  ///
  /// 明细页底栏在没预算的期换成「日均 / 环比上一期」的小总结，环比要用它。
  /// 有预算的期这个字段恒为 null，`loadCycle` 也不会为它多查一次库 ——
  /// 一次记账要跑 loadCycle，不能为了一个不显示的文案给它加查询。
  ({int expense, int count, int days})? prevPeriod;

  List<BudgetStat> _budgetStats = [];

  // ---- 统计与筛选：状态私有，外部只能通过 views.dart 里的只读视图访问 ----
  //
  // 这一组字段原先平铺在这里（`_statBasis` / `_statFrom` / `filter` / `_filterCount`
  // …），页面既能读也能写。改私有之后，写入只剩本文件里的
  // `loadStats` / `setStatBasis` / `shiftStat` / `applyFilter`，
  // 「页面误改统计口径」在编译期就通不过。

  /// 统计页的归集口径
  StatBasis _statBasis = StatBasis.period;

  /// 统计页当前看的区间（周期视图 = 当前期；月份视图 = 自然月）
  String _statFrom = '';
  String _statTo = '';
  String _month = Fmt.month(DateTime.now());
  int _statExpenseCents = 0;
  int _statIncomeCents = 0;
  List<CatStat> _statExpenseStats = [];
  List<CatStat> _statIncomeStats = [];
  List<(String date, int expense, int income)> _statDailyTotals = [];

  /// 近 6 段的收支（周期视图是「期」，月份视图是「月」），按时间升序。
  ///
  /// 放在 Store 而不是页面里，是因为它跟当前区间绑死：换期要重查，
  /// 页面组件只该读，不该自己管异步生命周期（否则测试里也等不到回包）。
  List<(String label, int expense, int income)> _statTrend = [];

  /// 统计屏的只读视图：口径、区间、合计、分类聚合、每日、近 6 段
  late final StatsView stats = StatsView._(this);

  // 明细筛选。筛选生效时明细页看 `_filteredTxns`，否则看本期 `_txns`
  TxnFilter _filter = TxnFilter.none;
  List<Txn> _filteredTxns = [];
  bool _filterTruncated = false;

  // 筛选合计走独立聚合（D20），不受 500 条上限影响。
  // 存在这里而不是每次现算，是因为合计要在概览卡里同步显示。
  int _filterExpenseCents = 0;
  int _filterIncomeCents = 0;
  int _filterCount = 0;

  /// 筛选态的只读视图：条件、命中列表、合计、是否截断
  late final FilterView filter = FilterView._(this);

  /// 启动时补记的周期账单条数（>0 时界面给一次提示）
  int _recurringJustAdded = 0;

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
  bool _catsUpgradeJustDone = false;

  static const _kCatsNotice = 'ui.cats_two_level_notice';

  /// 是否要提示「界面默认皮肤是『圣地 · 审判白』，可在「我的 → 主题」换回」。
  ///
  /// 只在三条同时成立时为真：从没手动选过皮肤（`ui.theme` 空）、从没提示过
  /// （`ui.theme_notice` 空）、**发布日之前就记过账**（= 升级上来的老用户）。
  /// 第三条为什么不是「库里有账目」：装完就记账的新用户也有账目，会误伤。
  bool _themeDefaultNotice = false;

  Ledger? get currentLedger {
    for (final l in _ledgers) {
      if (l.id == _ledgerId) return l;
    }
    return _ledgers.isEmpty ? null : _ledgers.first;
  }

  /// 本期「计入预算」的借入本金合计。
  ///
  /// 借贷流水一律不进收支统计，但用户勾了「计入预算」的那笔借入是**真能花**的钱。
  /// 不把它加进可用额度，就会出现「账户里明明多了 3000，预算卡却说你快超支了」。
  /// 借出恒不计入 —— 钱出去了，不是可花的钱。
  int get borrowedInBudgetCents {
    var sum = 0;
    for (final d in _debts) {
      if (d.direction.isReceivable) continue;
      if (!d.countInBudget) continue;
      if (_cycleFrom.isEmpty || _cycleTo.isEmpty) continue;
      // 只算本期借入的；上期借的钱不该抬这一期的额度
      if (d.date.compareTo(_cycleFrom) < 0 || d.date.compareTo(_cycleTo) > 0) {
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
      totalBudgetCents == null ? 0 : budgetAvailableCents - _expenseCents;

  bool get overBudget =>
      totalBudgetCents != null && _expenseCents > budgetAvailableCents;

  int get overBudgetCents =>
      overBudget ? _expenseCents - budgetAvailableCents : 0;

  /// 正在进行的 boot（并发去重用，结束即清空）
  Future<void>? _booting;

  /// 首屏启动：建表/开库 → 补归属期 → 补记周期账单 → 载入全部数据
  ///
  /// **并发调用复用同一个 Future**（1.4.22）。原因：boot 中途要切皮肤，
  /// 切皮肤会通知 `ThemeCtrl`，`app.dart` 里 `_BootGate` 的 key 绑着主题 id，
  /// 一变整棵子树重建 —— 新 State 的 initState 会再调一次 `boot()`。
  /// 重复 boot 会把补记账单再跑一遍、再全量查一遍，测试里甚至直接卡在启动页。
  /// 所以这里做单飞去重；`_ready` 之后再次调用仍然照常重跑（测试要靠这个
  /// 换库），只挡住「同时进行中的第二次」。
  Future<void> boot() {
    final inflight = _booting;
    if (inflight != null) return inflight;
    final f = _doBoot().whenComplete(() => _booting = null);
    _booting = f;
    return f;
  }

  Future<void> _doBoot() async {
    // 一次性提示标记的语义是「**本次启动**刚发生」，所以每次 boot 先清零。
    // 不重置的话它只在「真从老库升上来」那一刻被置 true，之后永远为真 ——
    // 进程内重复 boot（测试、以及热重启后的首次导航）就会重复弹。
    _catsUpgradeJustDone = false;
    _themeDefaultNotice = false;
    await Db.open();
    // v3 → v4 升级后 `period_start` 是空的，先补齐。账单日默认 1 时回填结果
    // 等于月初，与升级前完全一致 —— 这一步不改任何查询口径。
    await Repo.backfillMissingPeriods();
    // 界面实验开关（空态第二行）从 setting 表读覆盖值
    await UiFlags.load();
    // 触感开关：只有存过 '0' 才算关。老库没有这个键 → 保持默认开
    _hapticsEnabled = (await Repo.getSetting(_kHaptics)) != '0';
    Haptics.enabled = _hapticsEnabled;
    // 默认支出账户：没这个键（老库）或存了非法值都回落 null = 「没设过」，
    // 此时记账面板按原行为落到第一个账户。
    _defaultExpenseAccountId = int.tryParse(
      await Repo.getSetting(_kDefaultExpenseAccount) ?? '',
    );
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
    _themeId = themeIdFromString(await Repo.getSetting(_kTheme));
    ThemeCtrl.i.apply(_themeId);
    _ledgerId = await Repo.currentLedgerId();
    _cycleStartDay = await Repo.cycleStartDay();
    resetCycleToToday();
    _seenDay = Fmt.date(DateTime.now());
    _seenLedgerId = _ledgerId;
    _recurringJustAdded = await catchUpRecurring();

    // 分类从「一级 + 名目」改成「分类 + 子分类」之后，老用户打开会看到一堆
    // 眼熟的分类换了名字（交通→出行、学习→成长），还多出一层子分类。
    // 不说一句，他会以为数据被改乱了。提示只出一次，落一个 setting 作标记。
    if (Db.upgradedToTwoLevel && await Repo.getSetting(_kCatsNotice) == null) {
      _catsUpgradeJustDone = true;
      await Repo.setSetting(_kCatsNotice, '1');
    }

    // 1.5.1 把出厂默认从「黑塔 · 永夜」（深色）换成了「圣地 · 审判白」（亮色）。
    // 手动切过皮肤的人有 `ui.theme`，不受影响；从没切过的**老用户**升级后界面会
    // 毫无征兆地变浅 —— 他没做过任何操作，只能理解成 bug。所以补一句话。
    //
    // 难点是认出「老用户」，而不是「装完就记账的新用户」。1.5.1 只换了默认色、
    // 表结构一列没动，升级路径上没有任何"我刚升级了"的信号（对比上面的
    // `Db.upgradedToTwoLevel`，那是数据迁移时自己打的标，这次没有对应物）。
    // 剩下能用的只有时间线：新装用户的第一笔账必然落在发布日**当天或之后**，
    // 所以「发布日之前就记过账」才等于「这个人 1.5.1 之前就在用」。
    // 反过来按「库里有账目」判，新用户记完一笔再启动就会被一条假提示打扰。
    if (await Repo.getSetting(_kTheme) == null &&
        await Repo.getSetting(_kThemeNotice) == null &&
        await _hasTxnBefore(_defaultSkinChangedAt)) {
      _themeDefaultNotice = true;
      await Repo.setSetting(_kThemeNotice, '1');
    }

    await loadAll();
    _ready = true;
    notifyListeners();
  }

  /// [date]（`YYYY-MM-DD`）**之前**有没有记过账。
  ///
  /// 只服务于「这是升级上来的老用户，还是刚装上的新用户」这一个判断，所以用
  /// `EXISTS` 而不是 `COUNT(*)`：SQLite 命中第一行就停，不必把 txn 表扫完 ——
  /// boot 是冷启动的关键路径，这里多花的每一毫秒都是用户盯启动页的时间。
  ///
  /// 严格小于而不是小于等于：日期正好等于发布日的那笔，既可能是老用户升级当天
  /// 记的，也可能是新用户装完当天记的，两者分不清 —— 宁可少提示一次，
  /// 也不要让新用户看到一条不属于他的"变更说明"。
  ///
  /// `txn.date` 是等宽定长的 `'YYYY-MM-DD'` TEXT，字符串比较即日期比较。
  Future<bool> _hasTxnBefore(String date) async {
    final db = await Db.open();
    final r = await db.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM txn WHERE date < ?) AS e',
      [date],
    );
    return ((r.first['e'] as int?) ?? 0) != 0;
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
    if (!_ready) return 0;
    final today = Fmt.date(DateTime.now());
    final ledgerChanged = _ledgerId != _seenLedgerId;
    // 同一天 + 同一个账本：什么都不用做。这就是「按账本各自核对一次」
    if (today == _seenDay && !ledgerChanged) return 0;

    // 先记下「我当时停在哪一期」，再决定要不要拨 ——
    // 拨完之后 _isCurrentPeriod 就变了，判断会失真
    final wasCurrent = _isCurrentPeriod;
    _seenDay = today;
    _seenLedgerId = _ledgerId;

    // 只在用户本来就停在「当前期」时才把游标拨到今天。
    // 他若正翻 9 月的旧账，切出去回条微信再回来被拽回本月，等于抢方向盘。
    if (wasCurrent) resetCycleToToday();

    final added = await catchUpRecurring();
    if (added > 0) _recurringJustAdded = added;
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
    if (_recurringDoneOn[_ledgerId] == today) {
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
    final id = _ledgerId;
    final added = await Repo.runDueRecurring(id);
    _recurringDoneOn[id] = today;

    // 补记会动账户余额：界面上的净值必须跟着重算，
    // 否则用户看到的是「明细里多了一笔房租，余额却没动」
    if (id == _ledgerId) {
      _accounts = await Repo.listAccounts();
      _netWorthCents = await Repo.totalBalanceCents();
    }
    return added;
  }

  /// 把当前期拨回「今天所在的那一期」
  void resetCycleToToday() {
    final (from, to) = cyc.cycleRange(DateTime.now(), _cycleStartDay);
    _cycleFrom = from;
    _cycleTo = to;
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
    if (_statBasis == StatBasis.period) {
      resetCycleToToday();
    } else {
      _month = Fmt.month(DateTime.now());
    }
    await loadStats();
  }

  Future<void> loadAll() async {
    _ledgers = await Repo.listLedgers();
    _accounts = await Repo.listAccounts();
    _netWorthCents = await Repo.totalBalanceCents();
    await _loadCategories();
    await _loadDebts();
    _goals = await Repo.listGoals();
    await _loadGoalFlows();
    _liftableCatIds = await Repo.liftableCategoryIds(_ledgerId);
    await loadTemplates();
    await loadCycle();
    await loadStats();
  }

  /// 整库被替换（从备份恢复）之后重读一遍。
  ///
  /// 比 loadAll 多做两件事：`current_ledger_id` 可能也变了要重取；
  /// 筛选条件里引用的分类/账户可能已经不存在，直接清掉。
  Future<void> reloadAfterRestore() async {
    _ledgerId = await Repo.currentLedgerId();
    _resetFilter();
    await loadAll();
    notifyListeners();
  }

  Future<void> loadTemplates() async {
    _templates = await Repo.listTemplates(_ledgerId);
    _recentTemplates = await Repo.recentTemplates(_ledgerId);
  }

  /// 取上一期的支出合计（只给「没设预算的期」的小总结用）。
  ///
  /// **有预算的期直接清空、一次都不查** —— `loadCycle` 每次记账都要跑，
  /// 不能为了一条不显示的文案给它加一次查询。
  Future<void> _loadPrevPeriod() async {
    if (totalBudgetCents != null || _cycleFrom.isEmpty) {
      prevPeriod = null;
      return;
    }
    final prevFrom = cyc.shiftCycleDate(_cycleFrom, _cycleStartDay, -1);
    final prevTo = Fmt.date(
      cyc
          .shiftCycle(DateTime.parse(prevFrom), _cycleStartDay, 1)
          .subtract(const Duration(days: 1)),
    );
    final t = await RepoStats.rangeTotals(_ledgerId, prevFrom, prevTo);
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
    final totals = await RepoStats.rangeTotals(_ledgerId, _cycleFrom, _cycleTo);
    _expenseCents = totals.$1;
    _incomeCents = totals.$2;
    _txnCount = totals.$3;
    totalBudgetCents = await Repo.totalBudgetCents(_ledgerId, _cycleFrom);
    await _loadPrevPeriod();
    _budgetStats = await RepoStats.budgetStats(
      ledgerId: _ledgerId,
      periodStart: _cycleFrom,
      from: _cycleFrom,
      to: _cycleTo,
    );
    // 多取一条只为判断有没有被截断：只比较条数的话，
    // 「正好 500 条」和「500 条之外还有」在调用方无法区分
    _txns = await Repo.rangeListTxns(
      ledgerId: _ledgerId,
      from: _cycleFrom,
      to: _cycleTo,
      limit: txnPageLimit + 1,
    );
    _txnTruncated = _txns.length > txnPageLimit;
    if (_txnTruncated) _txns = _txns.sublist(0, txnPageLimit);
    _isCurrentPeriod = cyc.isCurrentCycle(_cycleFrom, _cycleTo);
    notifyListeners();
  }

  /// 载入统计页数据。口径由 [_statBasis] 决定，字段也单独存（`stat*`），
  /// 所以切换口径不会动到明细页的数字。
  Future<void> loadStats() async {
    final byPeriod = _statBasis == StatBasis.period;
    _statFrom = byPeriod ? _cycleFrom : Fmt.monthStart(_month);
    _statTo = byPeriod ? _cycleTo : Fmt.monthEnd(_month);
    final basis = byPeriod ? DateBasis.period : DateBasis.date;

    final totals = await RepoStats.rangeTotals(
      _ledgerId,
      _statFrom,
      _statTo,
      basis: basis,
    );
    _statExpenseCents = totals.$1;
    _statIncomeCents = totals.$2;
    _statExpenseStats = await RepoStats.rangeCategoryStats(
      ledgerId: _ledgerId,
      from: _statFrom,
      to: _statTo,
      type: TxnType.expense,
      basis: basis,
    );
    _statIncomeStats = await RepoStats.rangeCategoryStats(
      ledgerId: _ledgerId,
      from: _statFrom,
      to: _statTo,
      type: TxnType.income,
      basis: basis,
    );
    _statDailyTotals = await RepoStats.rangeDailyTotals(
      _ledgerId,
      _statFrom,
      _statTo,
      basis: basis,
    );
    _statTrend = byPeriod
        ? await RepoStats.recentPeriods(
            ledgerId: _ledgerId,
            endFrom: _cycleFrom,
            startDay: _cycleStartDay,
            count: 6,
          )
        : await RepoStats.recentMonths(
            ledgerId: _ledgerId,
            endMonth: _month,
            count: 6,
          );
    notifyListeners();
  }

  /// 切换统计口径（统计页的「本期 / 本月」）
  Future<void> setStatBasis(StatBasis b) async {
    if (_statBasis == b) return;
    _statBasis = b;
    await loadStats();
  }

  /// 统计页翻一段：周期视图翻一期，月份视图翻一个月
  Future<void> shiftStat(int delta) async {
    if (_statBasis == StatBasis.period) {
      await shiftCycle(delta);
      return;
    }
    _month = Fmt.shiftMonth(_month, delta);
    await loadStats();
  }

  /// 明细页 / 计划页翻一期
  Future<void> shiftCycle(int delta) async {
    _cycleFrom = cyc.shiftCycleDate(_cycleFrom, _cycleStartDay, delta);
    _cycleTo = Fmt.date(
      cyc
          .shiftCycle(DateTime.parse(_cycleFrom), _cycleStartDay, 1)
          .subtract(const Duration(days: 1)),
    );
    await loadCycle();
    // 统计页停在周期视图时要跟着翻，否则切回图表页数字还停在上一期
    if (_statBasis == StatBasis.period) await loadStats();
  }

  /// 跳到某个日期所在的那一期（日历里点某天用）
  Future<void> goToCycleOf(String date) async {
    final (from, to) = cyc.cycleRange(DateTime.parse(date), _cycleStartDay);
    if (from == _cycleFrom && to == _cycleTo) return;
    _cycleFrom = from;
    _cycleTo = to;
    await loadCycle();
    if (_statBasis == StatBasis.period) await loadStats();
  }

  /// 跳到某个月（统计页的月份视图里点日历用）。
  ///
  /// 只动 `month` 与统计数据：明细页/预算走的是「期」，不该被月份跳转带偏。
  Future<void> goToMonth(String ym) async {
    if (_month == ym) return;
    _month = ym;
    await loadStats();
  }

  /// 切账本。返回补记的周期账单条数（0 = 这本账没有欠账）。
  Future<int> switchLedger(int id) async {
    _ledgerId = id;
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
      _recurringJustAdded = added;
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
      _accounts = await Repo.listAccounts();
      _netWorthCents = await Repo.totalBalanceCents();
      // 借贷的「已还多少」是按流水算的，动过流水就得重算
      await _loadDebts();
      await loadCycle();
      await loadStats();
      // 筛选态下必须重跑，否则删掉的记录还会挂在结果里
      if (_filter.isNotEmpty) await applyFilter(_filter);
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
    if (periodStart != _cycleFrom) {
      final (from, to) = cyc.cycleRange(
        DateTime.parse(periodStart),
        _cycleStartDay,
      );
      _cycleFrom = from;
      _cycleTo = to;
    }
    // 从图表/计划页的 FAB 记的账也一样：跳回明细，否则「记完看不见」只是换个形式
    _tabIndex = 0;
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
      _ledgerId,
      type: TxnType.expense,
      includeArchived: true,
    );
    final incAll = await Repo.listCategories(
      _ledgerId,
      type: TxnType.income,
      includeArchived: true,
    );
    // 停用的不进 [_allExpenseCats]：那些列表喂的是选择器、预算和统计，
    // 停用的分类出现在那里就等于没停用。
    _archivedExpenseCats = [
      for (final c in expAll)
        if (c.archived) c,
    ];
    _archivedIncomeCats = [
      for (final c in incAll)
        if (c.archived) c,
    ];
    _allExpenseCats = [
      for (final c in expAll)
        if (!c.archived) c,
    ];
    _allIncomeCats = [
      for (final c in incAll)
        if (!c.archived) c,
    ];
    _expenseCats = _topOnly(_allExpenseCats);
    _incomeCats = _topOnly(_allIncomeCats);
  }

  /// 借贷列表与索引一起重建，保证 `_debts` 与 `debtOf` 永远一致
  Future<void> _loadDebts() async {
    _debts = await Repo.listDebts(ledgerId: _ledgerId);
    _debtById = {for (final d in _debts) d.id: d};
  }

  static List<Category> _topOnly(List<Category> all) => [
    for (final c in all)
      if (c.parentId == null) c,
  ];

  Future<void> afterAccountChange() async {
    _accounts = await Repo.listAccounts();
    _netWorthCents = await Repo.totalBalanceCents();
    notifyListeners();
  }

  Future<void> afterGoalChange() async {
    _goals = await Repo.listGoals();
    await _loadGoalFlows();
    notifyListeners();
  }

  /// 重取全部目标流水并按目标分组（一次 SQL，见 [Repo.listAllGoalFlows]）。
  Future<void> _loadGoalFlows() async {
    final rows = await Repo.listAllGoalFlows();
    final grouped = <int, List<GoalFlow>>{};
    for (final f in rows) {
      (grouped[f.goalId] ??= <GoalFlow>[]).add(f);
    }
    _goalFlows = grouped;
  }

  Future<void> afterTemplateChange() async {
    await loadTemplates();
    notifyListeners();
  }

  Future<void> afterBudgetChange() async {
    totalBudgetCents = await Repo.totalBudgetCents(_ledgerId, _cycleFrom);
    // 预算被删掉时这个期会切到「小总结」底栏，环比数据要跟着补上
    await _loadPrevPeriod();
    _budgetStats = await RepoStats.budgetStats(
      ledgerId: _ledgerId,
      periodStart: _cycleFrom,
      from: _cycleFrom,
      to: _cycleTo,
    );
    notifyListeners();
  }


  Category? categoryOf(int? id) {
    if (id == null) return null;
    for (final c in _allExpenseCats) {
      if (c.id == id) return c;
    }
    for (final c in _allIncomeCats) {
      if (c.id == id) return c;
    }
    // 停用的也要能反查到：历史流水、模板、周期账单都还指着它，
    // 查不到就会被渲染成「已删除分类」。
    for (final c in _archivedExpenseCats) {
      if (c.id == id) return c;
    }
    for (final c in _archivedIncomeCats) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 某个一级分类的全部子分类，已按 `sort_order` 排好（查询时就是这个顺序）。
  List<Category> childrenOf(int? parentId) {
    if (parentId == null) return const [];
    return [
      for (final c in _allExpenseCats)
        if (c.parentId == parentId) c,
      for (final c in _allIncomeCats)
        if (c.parentId == parentId) c,
    ];
  }

  /// 某一类型下已停用的一级分类 —— 只有分类管理页用得上
  List<Category> archivedTopCats(TxnType type) =>
      _topOnly(type.isExpense ? _archivedExpenseCats : _archivedIncomeCats);

  /// 某个一级分类下已停用的子分类
  List<Category> archivedChildrenOf(int parentId) => [
    for (final c in _archivedExpenseCats)
      if (c.parentId == parentId) c,
    for (final c in _archivedIncomeCats)
      if (c.parentId == parentId) c,
  ];

  /// 子分类的父级；一级分类本身返回 null。
  /// 明细行要显示「正餐 · 餐饮」这种层级说明时用得上。
  Category? parentOf(Category? c) =>
      c?.parentId == null ? null : categoryOf(c!.parentId);

  Account? accountOf(int? id) {
    if (id == null) return null;
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ------------------------------------------------------------------ 筛选

  /// 明细页的展示源：筛选生效时看筛选结果，否则看本期全部。
  ///
  /// 这是「筛选 × 期」两个维度的组合，所以留在 Store 而不是 FilterView ——
  /// 视图只描述自己那一维，跨维度的事由 Store 拼。
  List<Txn> get visibleTxns => _filter.isNotEmpty ? _filteredTxns : _txns;

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
      Repo.searchTxns(ledgerId: _ledgerId, filter: f),
      Repo.sumFiltered(ledgerId: _ledgerId, filter: f),
    ).wait;
    _filter = f;
    _filteredTxns = items;
    _filterTruncated = truncated;
    _filterExpenseCents = expense;
    _filterIncomeCents = income;
    _filterCount = count;
    notifyListeners();
  }

  Future<void> clearFilter() => applyFilter(TxnFilter.none);

  void _resetFilter() {
    _filter = TxnFilter.none;
    _filteredTxns = [];
    _filterTruncated = false;
    _filterExpenseCents = 0;
    _filterIncomeCents = 0;
    _filterCount = 0;
  }

  /// 把当前期明细按日期分组（日期倒序，组内 id 倒序）
  List<(String date, List<Txn> items)> get groupedByDay => _group(_txns);

  /// 筛选态下的按日分组，与 groupedByDay 同构
  List<(String date, List<Txn> items)> get groupedVisibleByDay =>
      _group(visibleTxns);

  List<(String date, List<Txn> items)> _group(List<Txn> items) {
    final map = <String, List<Txn>>{};
    for (final t in items) {
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
    _cycleStartDay = day.clamp(1, 31);
    await Repo.setSetting(Repo.cycleStartDayKey, '$_cycleStartDay');
    await Repo.rebuildPeriods(_ledgerId);
    // 预算的 key 是期首日，账单日变了必须跟着挪，否则历史预算全部「悬空」
    await Repo.remapBudgetPeriods(_cycleStartDay);
    resetCycleToToday();
    await loadCycle();
    await loadStats();
  }
}
