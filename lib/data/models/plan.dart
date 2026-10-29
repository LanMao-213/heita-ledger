part of '../models.dart';

// ---------------------------------------------------------------------------
// 预算 / 目标 / 周期规则 / 模板
// ---------------------------------------------------------------------------

/// 预算：`categoryId == null` 表示该账本该月的**总预算**
class Budget {
  const Budget({
    required this.id,
    required this.ledgerId,
    required this.periodStart,
    this.categoryId,
    required this.amountCents,
  });

  final int id;
  final int ledgerId;

  /// 归属期第一天（`YYYY-MM-DD`）。
  ///
  /// 预算按「期」存（v5 起，D13 改为预算也按周期）。账单日默认 1 时它就等于月初，
  /// 与老的自然月预算一一对应。
  final String periodStart;
  final int? categoryId;
  final int amountCents;

  bool get isTotal => categoryId == null;

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
    id: m['id'] as int,
    ledgerId: m['ledger_id'] as int,
    periodStart: m['period_start'] as String,
    categoryId: m['category_id'] as int?,
    amountCents: (m['amount_cents'] as int?) ?? 0,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'ledger_id': ledgerId,
    'period_start': periodStart,
    'category_id': categoryId,
    'amount_cents': amountCents,
  };
}

class SavingGoal {
  const SavingGoal({
    required this.id,
    required this.name,
    this.icon = 'target',
    required this.targetCents,
    this.savedCents = 0,
    this.monthlyCents = 0,
    this.dueMonth,
    this.sortOrder = 0,
    this.archived = false,
  });

  final int id;
  final String name;
  final String icon;
  final int targetCents;
  final int savedCents;

  /// 每月定投额（分）。0 = 没设，此时只显示进度环，不显示「预计何时达成」。
  ///
  /// ★ 它是**用户声明的计划**，不是已发生的事实；真正的存入记录在 `goal_flow`。
  ///   两者分开存，是因为「打算每月存 500」和「这个月确实存了 500」是两件事，
  ///   混在一起就会出现「计划完成率」这种自欺欺人的数字。
  final int monthlyCents;
  final String? dueMonth; // YYYY-MM
  final int sortOrder;
  final bool archived;

  double get progress =>
      targetCents <= 0 ? 0 : (savedCents / targetCents).clamp(0.0, 1.0);

  int get remainCents => (targetCents - savedCents).clamp(0, targetCents);

  bool get done => savedCents >= targetCents;

  factory SavingGoal.fromMap(Map<String, Object?> m) => SavingGoal(
    id: m['id'] as int,
    name: m['name'] as String,
    icon: (m['icon'] as String?) ?? 'target',
    targetCents: (m['target_cents'] as int?) ?? 0,
    savedCents: (m['saved_cents'] as int?) ?? 0,
    monthlyCents: (m['monthly_cents'] as int?) ?? 0,
    dueMonth: m['due_month'] as String?,
    sortOrder: (m['sort_order'] as int?) ?? 0,
    archived: ((m['archived'] as int?) ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'name': name,
    'icon': icon,
    'target_cents': targetCents,
    'saved_cents': savedCents,
    'monthly_cents': monthlyCents,
    'due_month': dueMonth,
    'sort_order': sortOrder,
    'archived': archived ? 1 : 0,
  };

  SavingGoal copyWith({
    String? name,
    String? icon,
    int? targetCents,
    int? savedCents,
    int? monthlyCents,
    String? dueMonth,
    int? sortOrder,
    bool? archived,
  }) => SavingGoal(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    targetCents: targetCents ?? this.targetCents,
    savedCents: savedCents ?? this.savedCents,
    monthlyCents: monthlyCents ?? this.monthlyCents,
    dueMonth: dueMonth ?? this.dueMonth,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
  );
}

/// 储蓄目标的一次存/取流水（v10）。
///
/// `cents` 带符号：正 = 存入，负 = 取出。与 `saving_goal.saved_cents` 的关系是
/// `saved_cents = Σ(goal_flow.cents)`（老数据例外，见 `Db._version = 10` 的注释）。
class GoalFlow {
  const GoalFlow({
    required this.id,
    required this.goalId,
    required this.date,
    required this.cents,
    this.accountId,
    this.note = '',
  });

  final int id;
  final int goalId;
  final String date; // YYYY-MM-DD
  final int cents;
  final int? accountId;
  final String note;

  bool get isDeposit => cents >= 0;

  factory GoalFlow.fromMap(Map<String, Object?> m) => GoalFlow(
    id: m['id'] as int,
    goalId: m['goal_id'] as int,
    date: m['date'] as String,
    cents: (m['cents'] as int?) ?? 0,
    accountId: m['account_id'] as int?,
    note: (m['note'] as String?) ?? '',
  );
}

/// 周期账单规则。
///
/// ★ 实现真相：单机应用没有后台服务，做不到定时执行。
///   真正机制是**每次打开 App 时扫描 `next_run_date <= 今天` 的规则并补记**，
///   补记的交易日期用规则**应触发的日期**（而不是「补记当天」），
///   这样账目才对得上。
class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.ledgerId,
    required this.type,
    required this.amountCents,
    required this.nextRunDate,
    this.categoryId,
    this.accountId,
    this.note = '',
    this.freq = 'monthly',
    this.interval = 1,
    this.endDate,
    this.enabled = true,
  });

  final int id;
  final int ledgerId;
  final TxnType type;
  final int amountCents;
  final int? categoryId;
  final int? accountId;
  final String note;

  /// daily / weekly / monthly / yearly
  final String freq;
  final int interval;
  final String nextRunDate;
  final String? endDate;
  final bool enabled;

  factory RecurringRule.fromMap(Map<String, Object?> m) => RecurringRule(
    id: m['id'] as int,
    ledgerId: m['ledger_id'] as int,
    type: TxnType.fromCode((m['type'] as String?) ?? 'expense'),
    amountCents: (m['amount_cents'] as int?) ?? 0,
    categoryId: m['category_id'] as int?,
    accountId: m['account_id'] as int?,
    note: (m['note'] as String?) ?? '',
    freq: (m['freq'] as String?) ?? 'monthly',
    interval: (m['interval'] as int?) ?? 1,
    nextRunDate: m['next_run_date'] as String,
    endDate: m['end_date'] as String?,
    enabled: ((m['enabled'] as int?) ?? 1) == 1,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'ledger_id': ledgerId,
    'type': type.code,
    'amount_cents': amountCents,
    'category_id': categoryId,
    'account_id': accountId,
    'note': note,
    'freq': freq,
    'interval': interval,
    'next_run_date': nextRunDate,
    'end_date': endDate,
    'enabled': enabled ? 1 : 0,
  };
}

class TxnTemplate {
  const TxnTemplate({
    required this.id,
    required this.ledgerId,
    required this.name,
    required this.type,
    required this.amountCents,
    this.icon = 'tpl',
    this.categoryId,
    this.accountId,
    this.note = '',
    this.sortOrder = 0,
    this.useCount = 0,
    this.lastUsedAt,
  });

  final int id;
  final int ledgerId;
  final String name;
  final String icon;
  final TxnType type;

  /// 0 表示「金额留空」—— 用模板时只省掉选分类和账户，金额现填
  final int amountCents;
  final int? categoryId;
  final int? accountId;
  final String note;
  final int sortOrder;

  /// 被使用过多少次、最后一次是什么时候。
  /// 只用于「最近使用」排序，不参与用户编辑，所以 toMap 里不带它们。
  final int useCount;
  final String? lastUsedAt;

  bool get hasAmount => amountCents > 0;

  factory TxnTemplate.fromMap(Map<String, Object?> m) => TxnTemplate(
    id: m['id'] as int,
    ledgerId: m['ledger_id'] as int,
    name: m['name'] as String,
    icon: (m['icon'] as String?) ?? 'tpl',
    type: TxnType.fromCode((m['type'] as String?) ?? 'expense'),
    amountCents: (m['amount_cents'] as int?) ?? 0,
    categoryId: m['category_id'] as int?,
    accountId: m['account_id'] as int?,
    note: (m['note'] as String?) ?? '',
    sortOrder: (m['sort_order'] as int?) ?? 0,
    useCount: (m['use_count'] as int?) ?? 0,
    lastUsedAt: m['last_used_at'] as String?,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'ledger_id': ledgerId,
    'name': name,
    'icon': icon,
    'type': type.code,
    'amount_cents': amountCents,
    'category_id': categoryId,
    'account_id': accountId,
    'note': note,
    'sort_order': sortOrder,
  };

  TxnTemplate copyWith({
    String? name,
    String? icon,
    TxnType? type,
    int? amountCents,
    int? categoryId,
    int? accountId,
    String? note,
    int? sortOrder,
    bool clearCategory = false,
    bool clearAccount = false,
  }) => TxnTemplate(
    id: id,
    ledgerId: ledgerId,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    type: type ?? this.type,
    amountCents: amountCents ?? this.amountCents,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    accountId: clearAccount ? null : (accountId ?? this.accountId),
    note: note ?? this.note,
    sortOrder: sortOrder ?? this.sortOrder,
    useCount: useCount,
    lastUsedAt: lastUsedAt,
  );
}

// ---------------------------------------------------------------------------
// 聚合结果（不是表，是查询产物）
// ---------------------------------------------------------------------------
