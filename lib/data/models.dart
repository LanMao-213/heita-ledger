import 'package:flutter/material.dart';

import '../design/tokens.dart';

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
  static String yuan(int cents, {bool sign = false}) => '¥${money(cents, sign: sign)}';

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
  static String md(String date) =>
      date.length >= 10 ? date.substring(5) : date;

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

  static TxnType fromCode(String c) =>
      TxnType.values.firstWhere((e) => e.code == c, orElse: () => TxnType.expense);

  bool get isExpense => this == TxnType.expense;
  bool get isIncome => this == TxnType.income;
}

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

  static AccountKind fromCode(String c) => AccountKind.values
      .firstWhere((e) => e.code == c, orElse: () => AccountKind.other);
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

  Ledger copyWith({String? name, String? icon, int? sortOrder, bool? archived}) =>
      Ledger(
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
    this.includeInTotal = true,
    this.sortOrder = 0,
    this.archived = false,
  });

  final int id;
  final String name;
  final AccountKind kind;
  final int balanceCents;
  final bool includeInTotal;
  final int sortOrder;
  final bool archived;

  String get icon => kind.icon;

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int,
        name: m['name'] as String,
        kind: AccountKind.fromCode((m['kind'] as String?) ?? 'cash'),
        balanceCents: (m['balance_cents'] as int?) ?? 0,
        includeInTotal: ((m['include_in_total'] as int?) ?? 1) == 1,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        archived: ((m['archived'] as int?) ?? 0) == 1,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'name': name,
        'kind': kind.code,
        'balance_cents': balanceCents,
        'include_in_total': includeInTotal ? 1 : 0,
        'sort_order': sortOrder,
        'archived': archived ? 1 : 0,
      };

  Account copyWith({
    String? name,
    AccountKind? kind,
    int? balanceCents,
    bool? includeInTotal,
    int? sortOrder,
    bool? archived,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        balanceCents: balanceCents ?? this.balanceCents,
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
  }) =>
      Category(
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
    this.templateId,
    this.recurringId,
    this.createdAt = '',
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

  /// 支出记为负、收入记为正 —— 用于求和
  int get signedCents => type.isIncome ? amountCents : -amountCents;

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
        templateId: m['template_id'] as int?,
        recurringId: m['recurring_id'] as int?,
        createdAt: (m['created_at'] as String?) ?? '',
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
        'template_id': templateId,
        'recurring_id': recurringId,
        'created_at': createdAt.isEmpty ? DateTime.now().toIso8601String() : createdAt,
      };

  Txn copyWith({
    TxnType? type,
    int? amountCents,
    String? date,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    String? note,
    bool clearCategory = false,
    bool clearAccount = false,
  }) =>
      Txn(
        id: id,
        ledgerId: ledgerId,
        type: type ?? this.type,
        amountCents: amountCents ?? this.amountCents,
        date: date ?? this.date,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        accountId: clearAccount ? null : (accountId ?? this.accountId),
        toAccountId: toAccountId ?? this.toAccountId,
        note: note ?? this.note,
        templateId: templateId,
        recurringId: recurringId,
        createdAt: createdAt,
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
    required this.month,
    this.categoryId,
    required this.amountCents,
  });

  final int id;
  final int ledgerId;
  final String month; // YYYY-MM
  final int? categoryId;
  final int amountCents;

  bool get isTotal => categoryId == null;

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as int,
        ledgerId: m['ledger_id'] as int,
        month: m['month'] as String,
        categoryId: m['category_id'] as int?,
        amountCents: (m['amount_cents'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'ledger_id': ledgerId,
        'month': month,
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
  }) =>
      SavingGoal(
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
  }) =>
      TxnTemplate(
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
