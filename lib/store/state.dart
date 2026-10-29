part of '../store.dart';

// ---------------------------------------------------------------------------
// 只读投影
// ---------------------------------------------------------------------------
//
// 这里的每一个 getter 都对应 `Store` 里的一个私有字段（`_txns` → `txns`）。
//
// ## 为什么不直接把这些字段写成 public
//
// 1.5.0 之前它们是 `List<Txn> txns = [];` 这样的公开**可变**字段，任何页面都能
//
//     Store.i.txns = [];          // 编译通过，界面空了，库里还在
//
// 这类误写不会报错，只会让「内存里的投影」和「库里的真相」分叉；分叉之后
// 所有基于投影的合计、预算结余、余额都会跟着错，而且**看不出是哪里错的**。
// 改成「字段私有 + 同名只读 getter」之后：
//
// - `s.txns` 照旧能读，调用点一行都不用改；
// - `s.txns = ...` 直接编译不过 —— 写入只能走 `Store` 的方法（那些方法
//   在写完库之后会按固定顺序重算投影，见 `loadAll` / `afterXxxChange`）。
//
// ## 为什么用 extension 而不是把 getter 写进类里
//
// 类体不能跨文件（part 是在顶层文本插入，不能续写一个 class）。放进类里
// 会让 `store.dart` 再长 60 行，而它已经是全项目最长的文件。extension 可以
// 放在 part 里、能读私有字段（同库私有作用域）、并且对 import 方自动可见。
//
// ## 边界（诚实说明）
//
// 这层保证的是「不能被整体替换」，**不是**「内容不可变」：
// `s.txns.add(x)` 仍然会改到这个 list。要彻底封死得返回
// `UnmodifiableListView`，但那会在每次访问时分配一个包装对象，而 `txns`
// 在列表渲染里是逐帧读的。这类就地修改目前一处都没有（`grep` 可查），
// 所以用「约定 + review」而不是「逐帧分配」来兜。

/// 账本与账户、分类、模板、目标、当期流水等**主数据**的只读投影。
extension StoreRead on Store {
  // ---- 启动与界面偏好

  /// 首次 `boot()` 是否已经完成（未完成时页面该显示骨架屏）
  bool get ready => _ready;

  /// 记账成功时是否震动
  bool get hapticsEnabled => _hapticsEnabled;

  /// 当前配色（`HeitaThemeId`）
  HeitaThemeId get themeId => _themeId;

  /// 底部 Tab 下标
  int get tabIndex => _tabIndex;

  // ---- 账本

  List<Ledger> get ledgers => _ledgers;

  /// 当前账本 id
  int get ledgerId => _ledgerId;

  // ---- 账户

  List<Account> get accounts => _accounts;

  /// 计入总资产的账户余额之和（不含「不计入总资产」的账户）
  int get netWorthCents => _netWorthCents;

  /// 默认支出账户 id。
  ///
  /// null 有两种含义且不区分：从没设过、或者设过的账户被删了 —— 两者的
  /// 处理完全一样（记账面板回落到第一个账户），所以不必再存一个「是否失效」标志。
  int? get defaultExpenseAccountId => _defaultExpenseAccountId;

  // ---- 分类

  /// 全部支出分类（含子分类，含已归档）
  List<Category> get allExpenseCats => _allExpenseCats;

  /// 全部收入分类（含子分类，含已归档）
  List<Category> get allIncomeCats => _allIncomeCats;

  /// 记账面板可选的一级支出分类（已归档的不在这里）
  List<Category> get expenseCats => _expenseCats;

  /// 记账面板可选的一级收入分类
  List<Category> get incomeCats => _incomeCats;

  /// 已归档的支出分类（分类管理页用来「恢复」）
  List<Category> get archivedExpenseCats => _archivedExpenseCats;

  /// 已归档的收入分类
  List<Category> get archivedIncomeCats => _archivedIncomeCats;

  /// 抬期白名单：这些分类的收入可以把归属期推到下一期
  Set<int> get liftableCatIds => _liftableCatIds;

  // ---- 模板与目标

  List<TxnTemplate> get templates => _templates;

  /// 最近用过的模板（记账面板顶部那排）
  List<TxnTemplate> get recentTemplates => _recentTemplates;

  List<SavingGoal> get goals => _goals;

  // ---- 当期

  /// 账单日（1-28）。1 表示自然月。
  int get cycleStartDay => _cycleStartDay;

  /// 当前归属期首日 `yyyy-MM-dd`
  String get cycleFrom => _cycleFrom;

  /// 当前归属期末日 `yyyy-MM-dd`（含）
  String get cycleTo => _cycleTo;

  /// 当前看的是不是「含今天的那一期」
  bool get isCurrentPeriod => _isCurrentPeriod;

  /// 当期支出合计（分）。负数按交叉归集，转账不计。
  int get expenseCents => _expenseCents;

  /// 当期收入合计（分）
  int get incomeCents => _incomeCents;

  /// 当期流水条数（未截断时的真实条数）
  int get txnCount => _txnCount;

  /// 当期流水是否因为超过 [txnPageLimit] 被截断
  bool get txnTruncated => _txnTruncated;

  /// 当期流水（按日期倒序；可能被 [txnPageLimit] 截断）
  List<Txn> get txns => _txns;

  List<Debt> get debts => _debts;

  /// 分类维度的预算执行情况（含「未分类」这一行）
  List<BudgetStat> get budgetStats => _budgetStats;

  // ---- 一次性提示

  /// 本次启动补记了几条周期账单（>0 时首页顶一条提示）
  int get recurringJustAdded => _recurringJustAdded;

  /// 是否要提示「分类升级成两级了」。只在真的从老库升上来、且没提示过时为真。
  bool get catsUpgradeJustDone => _catsUpgradeJustDone;

  /// 是否要提示「默认皮肤已改成『圣地 · 审判白』」。
  /// 只在「从没手动选过皮肤 + 从没提示过 + 库里有账目」三条同时成立时为真。
  bool get themeDefaultNotice => _themeDefaultNotice;

  // ------------------------------------------------------------- 储蓄目标

  /// 某个目标的存/取流水（最近在前）。没有流水时是空表，不是 null ——
  /// 调用方（预计时间计算）本来就要处理「一条都没有」这一档。
  List<GoalFlow> goalFlows(int goalId) => _goalFlows[goalId] ?? const <GoalFlow>[];

  /// 某个目标的预计达成时间。
  ///
  /// `today` 由这里取一次，不交给纯函数自己取 —— 一屏里「今天」只该有一个来源，
  /// 否则列表里几张卡在跨零点时可能算出不同的窗口。
  GoalEta goalEta(SavingGoal g) => projectGoal(
    targetCents: g.targetCents,
    savedCents: g.savedCents,
    flows: goalFlows(g.id),
    today: Fmt.today(),
  );

  /// 设了月度定投、但这个自然月还**没存过**的目标。
  ///
  /// 为什么按「自然月」而不是「周期」：定投这件事在用户心里就是「每个月存一笔」，
  /// 与账单日无关。用周期会让「15 号开始的这一期」和日历月错位，
  /// 用户看到提醒时会觉得日子不对。
  ///
  /// 只统计**存入**流水：取出不抵消「这个月已经存过了」这件事，
  /// 否则用户存完又取一点，提醒会重新冒出来 —— 那是骚扰不是提醒。
  List<SavingGoal> get goalsNeedMonthlyDeposit {
    final month = Fmt.today().substring(0, 7);
    return [
      for (final g in _goals)
        if (!g.archived &&
            !g.done &&
            g.monthlyCents > 0 &&
            !goalFlows(g.id).any(
              (f) => f.cents > 0 && f.date.startsWith(month),
            ))
          g,
    ];
  }
}
