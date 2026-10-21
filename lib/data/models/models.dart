/// 数据模型层的**唯一入口**：共用枚举 + 各表列名常量 + 全部模型的 barrel。
///
/// 约定（架构设计 §2.1）：
/// - 字段名以 `_cents` 结尾的，类型必须是 `int`（单位分）；
/// - 每个模型的 `toMap()` **必须覆盖该表 DDL 的全部列**（含 `id`，允许为 null
///   表示自增）。原版 `txn.updated_at` 这种「建了列、toMap 从不写、没人读」
///   的死列，就是靠 `model_map_test` 的双向断言挡住的。
/// - `fromMap()` 只做类型归一，**不做业务换算**（日期字符串 → `LocalDate` 除外）。
///
/// 关于循环引用：本文件既定义枚举、又 `export` 各模型文件，而模型文件又
/// `import 'models.dart'` 取枚举。Dart 的库循环是合法的（不是 `part`，各自
/// 独立编译），这里刻意这么组织，是为了让「列名」「枚举」「模型」三样东西
/// 永远只有一个 import 入口。
library;

import 'package:flutter/foundation.dart';

export 'account.dart';
export 'budget.dart';
export 'category.dart';
export 'debt.dart';
export 'ledger.dart';
export 'recurring.dart';
export 'saving_goal.dart';
export 'setting.dart';
export 'txn.dart';
export 'txn_template.dart';

// ---------------------------------------------------------------- 共用枚举

/// 账目类型。
///
/// **借贷不在这里**：借出/借入复用 `expense`/`income` + 非空 `debt_id`
/// （口径 3.5）。做成独立枚举要改遍明细分组、筛选、Excel 类型列、统计、
/// 周期归集、备份 7 处，漏一处就有一个数字错。
enum TxnType {
  expense('expense', '支出'),
  income('income', '收入'),
  transfer('transfer', '转账');

  const TxnType(this.code, this.label);

  /// 落库值（**唯一真源**，不许在 SQL 里手写 `'expense'`）。
  final String code;

  /// 界面文案。
  final String label;

  bool get isIncome => this == TxnType.income;
  bool get isExpense => this == TxnType.expense;
  bool get isTransfer => this == TxnType.transfer;

  /// 认不出 / null → `null`（导入路径要能容忍脏值，而不是猜）。
  static TxnType? tryParse(String? code) {
    for (final TxnType t in TxnType.values) {
      if (t.code == code) return t;
    }
    return null;
  }

  /// 同 [tryParse]，但脏值按「支出」处理（Excel 口径：其余一律支出）。
  static TxnType parseOrExpense(String? code) => tryParse(code) ?? TxnType.expense;
}

/// 交易的四个详情字段。挂在**子分类**上，全部选填。
///
/// 为什么是四个固定列而不是 JSON / 属性表：这四类信息需要能 `GROUP BY` 出
/// 「给某人花了多少」，塞进 JSON 就只能全表解析。代价是 4 列里经常 3 列为空。
enum TxnField {
  from('出发地'),
  to('目的地'),
  person('对象'),
  subject('名称');

  const TxnField(this.label);

  /// 录入框上的中文标签。
  final String label;

  /// 数据库列名。加字段时**只能往后加**，不能改名 —— 老库靠这个列名迁移。
  String get column => switch (this) {
    TxnField.from => 'place_from',
    TxnField.to => 'place_to',
    TxnField.person => 'person',
    TxnField.subject => 'subject',
  };

  /// 输入框里的示例文字。
  String get hint => switch (this) {
    TxnField.from => '从哪出发',
    TxnField.to => '到哪去',
    TxnField.person => '给谁 / 谁给的',
    TxnField.subject => '课程名 / 书名',
  };
}

/// 账户种类（7 值，与原版一致；DDL 里有 CHECK）。
enum AccountKind {
  cash('cash', '现金'),
  debit('debit', '储蓄卡'),
  credit('credit', '信用卡'),
  alipay('alipay', '支付宝'),
  wechat('wechat', '微信'),
  invest('invest', '投资'),
  other('other', '其他');

  const AccountKind(this.code, this.label);

  final String code;
  final String label;

  static AccountKind parseOrOther(String? code) {
    for (final AccountKind k in AccountKind.values) {
      if (k.code == code) return k;
    }
    return AccountKind.other;
  }
}

/// 借贷方向。
enum DebtDirection {
  /// 借出：别人欠我（应收）。
  out('out', '借出'),

  /// 借入：我欠别人（应付）。落库值是 `in`。
  in_('in', '借入');

  const DebtDirection(this.code, this.label);

  final String code;
  final String label;

  /// 借出 = 应收（`debt.direction = 'out'`）。
  bool get isReceivable => this == DebtDirection.out;

  static DebtDirection parseOrOut(String? code) =>
      code == DebtDirection.in_.code ? DebtDirection.in_ : DebtDirection.out;
}

/// 周期账单频率。
enum RecurFreq {
  daily('daily', '每天'),
  weekly('weekly', '每周'),
  monthly('monthly', '每月'),
  yearly('yearly', '每年');

  const RecurFreq(this.code, this.label);

  final String code;
  final String label;

  static RecurFreq parseOrMonthly(String? code) {
    for (final RecurFreq f in RecurFreq.values) {
      if (f.code == code) return f;
    }
    return RecurFreq.monthly;
  }
}

// -------------------------------------------------------------- 列名常量
//
// repo 里**不许出现裸字符串列名**：改列名时只改这里，编译期就能发现漏改。

/// `setting` 表列名。
abstract final class SettingCols {
  static const String k = 'k';
  static const String v = 'v';
}

/// `ledger` 表列名。
abstract final class LedgerCols {
  static const String id = 'id';
  static const String name = 'name';
  static const String icon = 'icon';
  static const String sortOrder = 'sort_order';
  static const String createdAt = 'created_at';
}

/// `account` 表列名。
abstract final class AccountCols {
  static const String id = 'id';
  static const String name = 'name';
  static const String kind = 'kind';
  static const String openingCents = 'opening_cents';
  static const String balanceCents = 'balance_cents';
  static const String includeInTotal = 'include_in_total';
  static const String sortOrder = 'sort_order';
}

/// `category` 表列名。
abstract final class CategoryCols {
  static const String id = 'id';
  static const String ledgerId = 'ledger_id';
  static const String type = 'type';
  static const String name = 'name';
  static const String icon = 'icon';
  static const String parentId = 'parent_id';
  static const String sortOrder = 'sort_order';
  static const String archived = 'archived';
}

/// `txn` 表列名（18 列，含 id）。
abstract final class TxnCols {
  static const String id = 'id';
  static const String ledgerId = 'ledger_id';
  static const String type = 'type';
  static const String amountCents = 'amount_cents';
  static const String categoryId = 'category_id';
  static const String accountId = 'account_id';
  static const String toAccountId = 'to_account_id';
  static const String date = 'date';
  static const String periodStart = 'period_start';
  static const String note = 'note';
  static const String placeFrom = 'place_from';
  static const String placeTo = 'place_to';
  static const String person = 'person';
  static const String subject = 'subject';
  static const String debtId = 'debt_id';
  static const String templateId = 'template_id';
  static const String recurringId = 'recurring_id';
  static const String createdAt = 'created_at';
}

/// `budget` 表列名。
abstract final class BudgetCols {
  static const String id = 'id';
  static const String ledgerId = 'ledger_id';
  static const String periodStart = 'period_start';
  static const String categoryId = 'category_id';
  static const String amountCents = 'amount_cents';
}

/// `debt` 表列名。
abstract final class DebtCols {
  static const String id = 'id';
  static const String ledgerId = 'ledger_id';
  static const String direction = 'direction';
  static const String counterparty = 'counterparty';
  static const String amountCents = 'amount_cents';
  static const String accountId = 'account_id';
  static const String date = 'date';
  static const String dueDate = 'due_date';
  static const String countInBudget = 'count_in_budget';
  static const String closedAt = 'closed_at';
  static const String note = 'note';
  static const String createdAt = 'created_at';
}

/// `recurring` 表列名。
abstract final class RecurringCols {
  static const String id = 'id';
  static const String ledgerId = 'ledger_id';
  static const String type = 'type';
  static const String amountCents = 'amount_cents';
  static const String categoryId = 'category_id';
  static const String accountId = 'account_id';
  static const String note = 'note';
  static const String freq = 'freq';
  static const String interval = 'interval';
  static const String nextRunDate = 'next_run_date';
  static const String endDate = 'end_date';
  static const String enabled = 'enabled';
}

/// `txn_template` 表列名。
abstract final class TemplateCols {
  static const String id = 'id';
  static const String ledgerId = 'ledger_id';
  static const String name = 'name';
  static const String icon = 'icon';
  static const String type = 'type';
  static const String amountCents = 'amount_cents';
  static const String categoryId = 'category_id';
  static const String accountId = 'account_id';
  static const String note = 'note';
  static const String sortOrder = 'sort_order';
  static const String useCount = 'use_count';
  static const String lastUsedAt = 'last_used_at';
}

/// `saving_goal` 表列名。
abstract final class GoalCols {
  static const String id = 'id';
  static const String name = 'name';
  static const String icon = 'icon';
  static const String targetCents = 'target_cents';
  static const String savedCents = 'saved_cents';
  static const String dueMonth = 'due_month';
  static const String sortOrder = 'sort_order';
}

// ------------------------------------------------------------------ 派生值

/// 一个范围内的合计（**交叉归集后的口径**，见 `TxnSum.bySide`）。
@immutable
class RangeTotals {
  const RangeTotals({
    required this.expenseCents,
    required this.incomeCents,
    required this.count,
  });

  static const RangeTotals zero = RangeTotals(
    expenseCents: 0,
    incomeCents: 0,
    count: 0,
  );

  /// 支出侧（已按交叉归集：支出里的负数不算在这里）。
  final int expenseCents;

  /// 收入侧（已按交叉归集：收入里的负数不算在这里）。
  final int incomeCents;

  /// 笔数（借贷流水**算**笔数，只是不算金额 —— 用户要在列表里看到它）。
  final int count;

  /// 结余 = 收入 − 支出。
  int get netCents => incomeCents - expenseCents;

  RangeTotals operator +(RangeTotals other) => RangeTotals(
    expenseCents: expenseCents + other.expenseCents,
    incomeCents: incomeCents + other.incomeCents,
    count: count + other.count,
  );

  @override
  bool operator ==(Object other) =>
      other is RangeTotals &&
      other.expenseCents == expenseCents &&
      other.incomeCents == incomeCents &&
      other.count == count;

  @override
  int get hashCode => Object.hash(expenseCents, incomeCents, count);

  @override
  String toString() =>
      'RangeTotals(exp=$expenseCents, inc=$incomeCents, n=$count)';
}

/// `copyWith` 里区分「没传」与「显式传 null」的哨兵。
///
/// 可空外键（`category_id` / `account_id` / `parent_id` / `period_start`）必须
/// 能表达「把它清空」，`int? x = null` 做不到这件事。
const Object kUnset = Object();

// ------------------------------------------------------------ fromMap 助手

/// `Object?` → `int`（SQLite 可能给 int / double / null）。
int asInt(Object? v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

/// `Object?` → `int?`
int? asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// `Object?` → `bool`（SQLite 存 0/1）
bool asBool(Object? v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final String s = v.toString();
  return s == '1' || s.toLowerCase() == 'true';
}

/// `Object?` → `String`（null → 空串）
String asString(Object? v, [String fallback = '']) => v?.toString() ?? fallback;

/// `Object?` → `String?`（空串归一为 null：库里不许出现「填过又删掉」的空串）
String? asStringOrNull(Object? v) {
  if (v == null) return null;
  final String s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// `Object?` → `DateTime?`（ISO8601 文本）
DateTime? asDateTimeOrNull(Object? v) {
  if (v == null) return null;
  final String s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// `bool` → SQLite 的 0/1
int boolToInt(bool v) => v ? 1 : 0;
