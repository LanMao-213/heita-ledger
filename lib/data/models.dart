import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'category_seed.dart';

/// 空白字符串一律落库为 NULL。
///
/// 不清成 NULL 的话，「填过又删掉」和「从来没过」在库里长成两种样子
/// （空串 / NULL），后面按字段筛选「有对象的记录」就会漏掉一半。
String? _nz(String? v) {
  final t = (v ?? '').trim();
  return t.isEmpty ? null : t;
}

/// 金额与日期的统一格式约定。
///
/// ★ 金额全程用**整数存「分」**，杜绝浮点误差（0.1+0.2≠0.3 这类问题
///   在记账软件里会累积成真金白银的差错）。
/// ★ 日期用 **TEXT `YYYY-MM-DD`**：可直接字典序排序、`LIKE '2026-10%'`
///   按月筛选、`substr(date,1,7)` 做月分组，比时间戳更好读也更好查。
abstract final class Fmt {
  /// 分 → 「1,234.56」
  static String money(int cents, {bool sign = false, bool trimZero = false}) {
    final neg = cents < 0;
    final v = cents.abs();
    final yuan = v ~/ 100;
    final fen = v % 100;

    final buf = StringBuffer();
    final s = yuan.toString();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }

    var out = '$buf.${fen.toString().padLeft(2, '0')}';
    if (trimZero && fen == 0) out = buf.toString();

    if (neg) return '-$out';
    if (sign && cents > 0) return '+$out';
    return out;
  }

  /// 分 → 「¥1,234.56」
  static String yuan(int cents, {bool sign = false}) =>
      '¥${money(cents, sign: sign)}';

  /// 分 → 紧凑写法「1.2万」「3,456」，用于卡片上的大数字
  static String compact(int cents) {
    final yuan = cents / 100.0;
    if (yuan.abs() >= 10000) {
      final w = yuan / 10000.0;
      final s = w.toStringAsFixed(w.abs() >= 100 ? 0 : 1);
      return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}万';
    }
    return money(cents, trimZero: true, sign: true);
  }

  /// 「2026-10-16」→「10-16」
  static String md(String date) => date.length >= 10 ? date.substring(5) : date;

  /// 「2026-10-16」→「10月16日 周四」
  static String friendly(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    final d = DateTime.tryParse(date);
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    final day = int.tryParse(parts[2]) ?? 1;
    final wd = d == null ? '' : ' 周${week[d.weekday - 1]}';
    return '${int.tryParse(parts[1]) ?? 0}月$day日$wd';
  }

  /// 「2026-10」→「2026年10月」
  static String monthLabel(String ym) {
    final p = ym.split('-');
    if (p.length != 2) return ym;
    return '${p[0]}年${int.tryParse(p[1]) ?? 0}月';
  }

  /// 今天，`YYYY-MM-DD`
  static String today() => date(DateTime.now());

  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String month(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// 某月天数
  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// 月份偏移，`shiftMonth('2026-01', -1)` → `2025-12`
  static String shiftMonth(String ym, int delta) {
    final p = ym.split('-');
    final y = int.parse(p[0]);
    final m = int.parse(p[1]);
    final t = DateTime(y, m + delta);
    return month(t);
  }

  static int parseCents(String input) {
    final s = input.trim().replaceAll(',', '');
    if (s.isEmpty) return 0;
    final d = double.tryParse(s);
    if (d == null) return 0;
    return (d * 100).round();
  }
}

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

/// 账户类型
enum AccountKind {
  cash('cash', '现金', 'wallet'),
  debit('debit', '储蓄卡', 'card'),
  credit('credit', '信用卡', 'card'),
  alipay('alipay', '支付宝', 'wallet'),
  wechat('wechat', '微信', 'wallet'),
  invest('invest', '投资', 'invest'),
  other('other', '其他', 'more');

  const AccountKind(this.code, this.label, this.icon);

  final String code;
  final String label;
  final String icon;

  static AccountKind fromCode(String c) => AccountKind.values.firstWhere(
    (e) => e.code == c,
    orElse: () => AccountKind.other,
  );
}

class Ledger {
  const Ledger({
    required this.id,
    required this.name,
    this.icon = 'book',
    this.sortOrder = 0,
    this.archived = false,
  });

  final int id;
  final String name;
  final String icon;
  final int sortOrder;
  final bool archived;

  factory Ledger.fromMap(Map<String, Object?> m) => Ledger(
    id: m['id'] as int,
    name: m['name'] as String,
    icon: (m['icon'] as String?) ?? 'book',
    sortOrder: (m['sort_order'] as int?) ?? 0,
    archived: ((m['archived'] as int?) ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'name': name,
    'icon': icon,
    'sort_order': sortOrder,
    'archived': archived ? 1 : 0,
  };

  Ledger copyWith({
    String? name,
    String? icon,
    int? sortOrder,
    bool? archived,
  }) => Ledger(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
  );
}

class Account {
  const Account({
    required this.id,
    required this.name,
    this.kind = AccountKind.cash,
    this.balanceCents = 0,
    this.openingCents = 0,
    this.includeInTotal = true,
    this.sortOrder = 0,
    this.archived = false,
  });

  final int id;
  final String name;
  final AccountKind kind;
  final int balanceCents;

  /// 期初 / 手工校准值（schema v8）。
  ///
  /// 恒等式：`balanceCents == openingCents + 该账户流水合计`。
  /// 用户手填「实际余额」时改的是 opening（见 `Repo.setAccountBalance`），
  /// 流水只负责增减 balance —— 两者分开之后余额才可对账。
  final int openingCents;
  final bool includeInTotal;
  final int sortOrder;
  final bool archived;

  String get icon => kind.icon;

  factory Account.fromMap(Map<String, Object?> m) => Account(
    id: m['id'] as int,
    name: m['name'] as String,
    kind: AccountKind.fromCode((m['kind'] as String?) ?? 'cash'),
    balanceCents: (m['balance_cents'] as int?) ?? 0,
    openingCents: (m['opening_cents'] as int?) ?? 0,
    includeInTotal: ((m['include_in_total'] as int?) ?? 1) == 1,
    sortOrder: (m['sort_order'] as int?) ?? 0,
    archived: ((m['archived'] as int?) ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'name': name,
    'kind': kind.code,
    'balance_cents': balanceCents,
    'opening_cents': openingCents,
    'include_in_total': includeInTotal ? 1 : 0,
    'sort_order': sortOrder,
    'archived': archived ? 1 : 0,
  };

  Account copyWith({
    String? name,
    AccountKind? kind,
    int? balanceCents,
    int? openingCents,
    bool? includeInTotal,
    int? sortOrder,
    bool? archived,
  }) => Account(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    balanceCents: balanceCents ?? this.balanceCents,
    openingCents: openingCents ?? this.openingCents,
    includeInTotal: includeInTotal ?? this.includeInTotal,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
  );
}

class Category {
  const Category({
    required this.id,
    required this.ledgerId,
    required this.type,
    required this.name,
    this.icon = 'more',
    this.parentId,
    this.sortOrder = 0,
    this.archived = false,
  });

  final int id;
  final int ledgerId;
  final TxnType type;
  final String name;
  final String icon;
  final int? parentId;
  final int sortOrder;
  final bool archived;

  factory Category.fromMap(Map<String, Object?> m) => Category(
    id: m['id'] as int,
    ledgerId: m['ledger_id'] as int,
    type: TxnType.fromCode((m['type'] as String?) ?? 'expense'),
    name: m['name'] as String,
    icon: (m['icon'] as String?) ?? 'more',
    parentId: m['parent_id'] as int?,
    sortOrder: (m['sort_order'] as int?) ?? 0,
    archived: ((m['archived'] as int?) ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'ledger_id': ledgerId,
    'type': type.code,
    'name': name,
    'icon': icon,
    'parent_id': parentId,
    'sort_order': sortOrder,
    'archived': archived ? 1 : 0,
  };

  Category copyWith({
    String? name,
    String? icon,
    int? parentId,
    int? sortOrder,
    bool? archived,
  }) => Category(
    id: id,
    ledgerId: ledgerId,
    type: type,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    parentId: parentId ?? this.parentId,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
  );
}

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
    this.dueMonth,
    this.sortOrder = 0,
    this.archived = false,
  });

  final int id;
  final String name;
  final String icon;
  final int targetCents;
  final int savedCents;
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
    'due_month': dueMonth,
    'sort_order': sortOrder,
    'archived': archived ? 1 : 0,
  };

  SavingGoal copyWith({
    String? name,
    String? icon,
    int? targetCents,
    int? savedCents,
    String? dueMonth,
    int? sortOrder,
    bool? archived,
  }) => SavingGoal(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    targetCents: targetCents ?? this.targetCents,
    savedCents: savedCents ?? this.savedCents,
    dueMonth: dueMonth ?? this.dueMonth,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
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

/// 分类统计，用于饼图与排行
class CatStat {
  const CatStat({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.totalCents,
    required this.count,
  });

  final int categoryId;
  final String name;
  final String icon;
  final int totalCents;
  final int count;
}

/// 分类 + 预算，用于计划页的进度条
class BudgetStat {
  const BudgetStat({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.spentCents,
    required this.budgetCents,
  });

  final int categoryId;
  final String name;
  final String icon;
  final int spentCents;
  final int budgetCents;

  bool get over => budgetCents > 0 && spentCents > budgetCents;

  double get ratio => budgetCents <= 0 ? 0 : (spentCents / budgetCents);

  int get overCents => over ? spentCents - budgetCents : 0;
}

/// 饼图切片用的取色：按金额从大到小套灰阶，保证深浅有意义
Color monoSlot(int index) => kMono[index % kMono.length];

// --------------------------------------------------------------- 借贷往来

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
