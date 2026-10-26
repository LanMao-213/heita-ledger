part of '../models.dart';

// ---------------------------------------------------------------------------
// 流水、筛选、借贷
// ---------------------------------------------------------------------------

/// 账目类型
enum TxnType {
  expense('expense', '支出'),
  income('income', '收入'),
  transfer('transfer', '转账');

  const TxnType(this.code, this.label);

  final String code;
  final String label;

  static TxnType fromCode(String c) => TxnType.values.firstWhere(
    (e) => e.code == c,
    orElse: () => TxnType.expense,
  );

  bool get isExpense => this == TxnType.expense;
  bool get isIncome => this == TxnType.income;
}

/// 归集口径。
///
/// - [period]：按**归属期**（`txn.period_start`）—— 明细、计划、预算用这个，
///   一笔 10 号到账的工资会被算进 15 号开始的那一期。
/// - [date]：按**真实发生日**（`txn.date`）—— 统计页的「月份」视图用这个，
///   它回答的是「10 月这一个月到底花了多少」，跟账单日无关。
///
/// 两个口径的数字会不一样，这是设计，不是 bug：切换按钮的文案要把这件事说清。
enum DateBasis { period, date }

class Txn {
  const Txn({
    required this.id,
    required this.ledgerId,
    required this.type,
    required this.amountCents,
    required this.date,
    this.categoryId,
    this.accountId,
    this.toAccountId,
    this.note = '',
    this.placeFrom,
    this.placeTo,
    this.person,
    this.subject,
    this.debtId,
    this.templateId,
    this.recurringId,
    this.createdAt = '',
    this.periodStart,
  });

  final int id;
  final int ledgerId;
  final TxnType type;
  final int amountCents;
  final String date; // YYYY-MM-DD
  final int? categoryId;
  final int? accountId;
  final int? toAccountId;
  final String note;
  final int? templateId;
  final int? recurringId;
  final String createdAt;

  // ---- 分类详情字段（v6）。四个都可空，只有分类声明了才在录入面板出现 ----
  //
  // 为什么做成四列而不是一个 JSON：这四类信息要能 `GROUP BY`（「给张三花了多少」
  // 「这条线路每月花多少」）。JSON 只能全表解析、也没法建索引。

  /// 出发地（出行类）
  final String? placeFrom;

  /// 目的地（出行类）
  final String? placeTo;

  /// 对象（人情类）
  final String? person;

  /// 名称（课程 / 书籍 / 订阅等）
  final String? subject;

  /// 关联的借贷往来（v7）。非空表示这笔是某笔借出/借入的本金或还款流水：
  /// 统计一律排除，明细里按「借出 · 张三」渲染，金额用中性色。
  final int? debtId;

  /// 归属期（`YYYY-MM-DD`，该期第一天）。
  ///
  /// **只读派生字段**：由 `Repo` 在写入时按 `date + 账单日 + 抬期规则` 算出来落库，
  /// 所以 [toMap] 故意不含它 —— 谁写库谁负责算，避免调用方漏传。
  /// 为 null 表示这条记录还没回填过（v4 之前的库，`boot()` 会补齐）。
  final String? periodStart;

  /// 支出记为负、收入记为正 —— 用于求和
  int get signedCents => type.isIncome ? amountCents : -amountCents;

  /// 按字段取值，没有就返回空串。
  /// 返回空串而不是 null：UI 里到处 `?? ''` 会把真正的「忘了填」和「不适用」混在一起。
  String detail(TxnField f) => switch (f) {
    TxnField.from => placeFrom ?? '',
    TxnField.to => placeTo ?? '',
    TxnField.person => person ?? '',
    TxnField.subject => subject ?? '',
  };

  /// 有值的详情字段，按枚举声明顺序。明细行、Excel 导出共用一个口径。
  List<(TxnField, String)> get filledDetails => [
    for (final f in TxnField.values)
      if (detail(f).isNotEmpty) (f, detail(f)),
  ];

  /// 一行摘要：地点两端合成 `家 → 公司`，其余原样拼在后面。
  /// 空串表示这条记录没有任何详情 —— 调用方据此决定要不要多画一行。
  String get detailSummary {
    final from = detail(TxnField.from);
    final to = detail(TxnField.to);
    final parts = <String>[
      if (from.isNotEmpty || to.isNotEmpty)
        '${from.isEmpty ? '—' : from} → ${to.isEmpty ? '—' : to}',
      if (person != null && person!.isNotEmpty) person!,
      if (subject != null && subject!.isNotEmpty) subject!,
    ];
    return parts.join(' · ');
  }

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
    id: m['id'] as int,
    ledgerId: m['ledger_id'] as int,
    type: TxnType.fromCode((m['type'] as String?) ?? 'expense'),
    amountCents: (m['amount_cents'] as int?) ?? 0,
    date: m['date'] as String,
    categoryId: m['category_id'] as int?,
    accountId: m['account_id'] as int?,
    toAccountId: m['to_account_id'] as int?,
    note: (m['note'] as String?) ?? '',
    placeFrom: _nz(m['place_from'] as String?),
    placeTo: _nz(m['place_to'] as String?),
    person: _nz(m['person'] as String?),
    subject: _nz(m['subject'] as String?),
    debtId: m['debt_id'] as int?,
    templateId: m['template_id'] as int?,
    recurringId: m['recurring_id'] as int?,
    createdAt: (m['created_at'] as String?) ?? '',
    periodStart: m['period_start'] as String?,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'ledger_id': ledgerId,
    'type': type.code,
    'amount_cents': amountCents,
    'date': date,
    'category_id': categoryId,
    'account_id': accountId,
    'to_account_id': toAccountId,
    'note': note,
    'place_from': _nz(placeFrom),
    'place_to': _nz(placeTo),
    'person': _nz(person),
    'subject': _nz(subject),
    'debt_id': debtId,
    'template_id': templateId,
    'recurring_id': recurringId,
    'created_at': createdAt.isEmpty
        ? DateTime.now().toIso8601String()
        : createdAt,
  };

  Txn copyWith({
    TxnType? type,
    int? amountCents,
    String? date,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    String? note,
    String? placeFrom,
    String? placeTo,
    String? person,
    String? subject,
    int? debtId,
    bool clearCategory = false,
    bool clearAccount = false,
  }) => Txn(
    id: id,
    ledgerId: ledgerId,
    type: type ?? this.type,
    amountCents: amountCents ?? this.amountCents,
    date: date ?? this.date,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    accountId: clearAccount ? null : (accountId ?? this.accountId),
    toAccountId: toAccountId ?? this.toAccountId,
    note: note ?? this.note,
    placeFrom: placeFrom ?? this.placeFrom,
    placeTo: placeTo ?? this.placeTo,
    person: person ?? this.person,
    subject: subject ?? this.subject,
    debtId: debtId ?? this.debtId,
    templateId: templateId,
    recurringId: recurringId,
    createdAt: createdAt,
    // 改了日期，旧的归属期就不再成立，等 Repo 写入时重算
    periodStart: date == null ? periodStart : null,
  );
}

/// 某一侧（支出 / 收入）的合计，口径是**交叉归集**：
/// 支出里记的负数算进收入，收入里记的负数算进支出。
///
/// 这是产品定的规则，语义是「这笔钱的方向反了，不是这一侧变少了」——
/// 代购代付后对方多给的钱，记成支出 −20，统计上应该体现为收入多了 20。
/// 转账两侧都不参与。
int sumBySide(Iterable<Txn> txns, TxnType side) {
  if (side == TxnType.transfer) return 0;
  var sum = 0;
  for (final t in txns) {
    if (t.type == TxnType.transfer) continue;
    // 借贷流水不是收支：借出去的钱不是消费，收回来的也不是收入。
    // 放在这里而不是各页面自己过滤 —— 漏一处就有一个「今日支出」是错的。
    if (t.debtId != null) continue;
    final sameSide = t.type == side;
    if (sameSide ? t.amountCents >= 0 : t.amountCents < 0) {
      sum += t.amountCents.abs();
    }
  }
  return sum;
}

/// 明细筛选条件。字段为 null 表示「这一项没设」，全部为 null 即「未筛选」。
///
/// ★ 刻意**不提供** `copyWith` + `clearXxx` 那一套：本轮的交互是「面板
///   整体返回一个新的 TxnFilter」+ `clearFilter()`，没有任何逐项清除的
///   调用点。六个字段配四个 clear 标志的手写 copyWith 是全方案最容易写错
///   的地方，没有调用点就先不写，等真需要时再加。
class TxnFilter {
  const TxnFilter({
    this.type,
    this.categoryId,
    this.accountId,
    this.minCents,
    this.maxCents,
    this.dateFrom,
    this.dateTo,
  });

  /// 收支类型，null = 不限。转账记录不参与收支两档
  final TxnType? type;

  /// 分类。只会是支出分类（收入不按分类筛）
  final int? categoryId;

  /// 账户。转账两端都算命中（`account_id` 或 `to_account_id`）
  final int? accountId;

  final int? minCents;
  final int? maxCents;

  /// `YYYY-MM-DD`，两端都含
  final String? dateFrom;
  final String? dateTo;

  /// 未筛选
  static const none = TxnFilter();

  bool get isEmpty =>
      type == null &&
      categoryId == null &&
      accountId == null &&
      minCents == null &&
      maxCents == null &&
      dateFrom == null &&
      dateTo == null;

  bool get isNotEmpty => !isEmpty;

  /// 只换收支类型，其余条件原样保留。
  ///
  /// 只改类型、保留其它条件（筛选面板用它）。
  ///
  /// 曾经的明细页顶部快捷筛选也用它 —— 那排已在 1.4.5 移除（跨全部历史、
  /// 与概览卡的本期口径冲突），现在类型只从筛选面板进。
  TxnFilter withType(TxnType? type) => TxnFilter(
    type: type,
    categoryId: categoryId,
    accountId: accountId,
    minCents: minCents,
    maxCents: maxCents,
    dateFrom: dateFrom,
    dateTo: dateTo,
  );

  /// 金额区间的短标签，如「¥50–200」「≥ ¥50」「≤ ¥200」。
  ///
  /// 分类名、账户名不在这里拼：模型层拿不到 Store 里的分类/账户字典，
  /// 那部分由页面负责。
  String? get amountLabel {
    if (minCents == null && maxCents == null) return null;
    final lo = minCents == null ? null : Fmt.money(minCents!, trimZero: true);
    final hi = maxCents == null ? null : Fmt.money(maxCents!, trimZero: true);
    if (lo != null && hi != null) return '¥$lo–$hi';
    if (lo != null) return '≥ ¥$lo';
    return '≤ ¥$hi';
  }

  /// 时间段的短标签，如「10-01 至 10-15」
  String? get dateLabel {
    if (dateFrom == null && dateTo == null) return null;
    if (dateFrom != null && dateTo != null) {
      return '${Fmt.md(dateFrom!)} 至 ${Fmt.md(dateTo!)}';
    }
    if (dateFrom != null) return '${Fmt.md(dateFrom!)} 起';
    return '截至 ${Fmt.md(dateTo!)}';
  }
}

/// 借贷方向。
///
/// 枚举名避开 Dart 关键字 `in`，但落库的 code 仍是 `in` / `out`，与
/// `debt.direction` 列一一对应 —— 改 code 就等于改数据，不能动。
enum DebtDirection {
  lent('out', '借出'),
  borrowed('in', '借入');

  const DebtDirection(this.code, this.label);

  final String code;
  final String label;

  static DebtDirection fromCode(String? c) => DebtDirection.values.firstWhere(
    (e) => e.code == c,
    orElse: () => DebtDirection.lent,
  );

  /// 借出 = 别人欠我（应收）；借入 = 我欠别人（应付）
  bool get isReceivable => this == DebtDirection.lent;

  /// 本金在账户上的方向：借出是钱出去，借入是钱进来
  bool get isMoneyOut => this == DebtDirection.lent;
}

/// 一笔借贷往来。
///
/// **已还金额不存库**（[repaidCents] 由 `Repo` 查完流水后填）：存冗余字段迟早
/// 和流水对不上，而「还剩多少」正是这套功能最核心的数字。
class Debt {
  const Debt({
    required this.id,
    required this.ledgerId,
    required this.direction,
    required this.counterparty,
    required this.amountCents,
    required this.date,
    this.accountId,
    this.dueDate,
    this.countInBudget = false,
    this.closedAt,
    this.note = '',
    this.createdAt = '',
    this.repaidCents = 0,
  });

  final int id;
  final int ledgerId;
  final DebtDirection direction;

  /// 对方名字，必填 —— 「谁欠我多少」全靠它分组
  final String counterparty;

  /// 本金，单位「分」
  final int amountCents;

  /// 发生日 `YYYY-MM-DD`
  final String date;

  /// 资金进出的账户
  final int? accountId;

  /// 约定还款日 `YYYY-MM-DD`，可空
  final String? dueDate;

  /// 借入时是否算进本期可用（借出恒为 false）
  final bool countInBudget;

  /// 非空 = 已结清
  final String? closedAt;

  final String note;
  final String createdAt;

  /// 已还金额（派生字段，由查询时按流水汇总，不落库）
  final int repaidCents;

  bool get isClosed => closedAt != null;

  /// 还剩多少没还。已结清直接为 0 —— 多还的部分不显示成负数。
  int get remainingCents =>
      isClosed ? 0 : (amountCents - repaidCents).clamp(0, amountCents);

  /// 逾期天数。未结清、有应还日、且已过当天才算；否则返回 null。
  int? get overdueDays {
    if (isClosed) return null;
    final raw = dueDate;
    if (raw == null || raw.isEmpty) return null;
    final due = DateTime.tryParse(raw);
    if (due == null) return null;
    final today = DateTime.now();
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(due.year, due.month, due.day)).inDays;
    return days > 0 ? days : null;
  }

  bool get isOverdue => overdueDays != null;

  factory Debt.fromMap(Map<String, Object?> m) => Debt(
    id: m['id'] as int,
    ledgerId: m['ledger_id'] as int,
    direction: DebtDirection.fromCode(m['direction'] as String?),
    counterparty: (m['counterparty'] as String?) ?? '',
    amountCents: (m['amount_cents'] as int?) ?? 0,
    date: m['date'] as String,
    accountId: m['account_id'] as int?,
    dueDate: _nz(m['due_date'] as String?),
    countInBudget: ((m['count_in_budget'] as int?) ?? 0) != 0,
    closedAt: _nz(m['closed_at'] as String?),
    note: (m['note'] as String?) ?? '',
    createdAt: (m['created_at'] as String?) ?? '',
    // 查询里的派生列（见 Repo.listDebts），没有就是 0
    repaidCents: (m['repaid_cents'] as int?) ?? 0,
  );

  /// 落库用。**不含 `repaid_cents`** —— 那是算出来的，不是存的。
  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'ledger_id': ledgerId,
    'direction': direction.code,
    'counterparty': counterparty,
    'amount_cents': amountCents,
    'account_id': accountId,
    'date': date,
    'due_date': _nz(dueDate),
    'count_in_budget': countInBudget ? 1 : 0,
    'closed_at': closedAt,
    'note': note,
    'created_at': createdAt.isEmpty
        ? DateTime.now().toIso8601String()
        : createdAt,
  };
}
