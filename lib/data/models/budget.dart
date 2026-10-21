import '../../core/local_date.dart';
import 'models.dart';

/// 一条预算。`categoryId == null` 是**总预算**，非空是分类预算。
///
/// 按**归属期**存（`periodStart`），不是自然月 —— 账单日 ≠ 1 时月份不是归属单元。
class Budget {
  const Budget({
    this.id,
    this.ledgerId = 0,
    required this.periodStart,
    this.categoryId,
    this.amountCents = 0,
  });

  final int? id;
  final int ledgerId;
  final LocalDate periodStart;
  final int? categoryId;
  final int amountCents;

  /// 总预算那一行。
  bool get isTotal => categoryId == null;

  Budget copyWith({
    int? id,
    int? ledgerId,
    LocalDate? periodStart,
    Object? categoryId = kUnset,
    int? amountCents,
  }) {
    return Budget(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      periodStart: periodStart ?? this.periodStart,
      categoryId: categoryId == kUnset ? this.categoryId : categoryId as int?,
      amountCents: amountCents ?? this.amountCents,
    );
  }

  /// 覆盖 DDL 全部 5 列。
  Map<String, Object?> toMap() => <String, Object?>{
    BudgetCols.id: id,
    BudgetCols.ledgerId: ledgerId,
    BudgetCols.periodStart: periodStart.iso,
    BudgetCols.categoryId: categoryId,
    BudgetCols.amountCents: amountCents,
  };

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
    id: asIntOrNull(m[BudgetCols.id]),
    ledgerId: asInt(m[BudgetCols.ledgerId]),
    periodStart:
        LocalDate.tryParse(asString(m[BudgetCols.periodStart])) ??
        LocalDate.fromDateTime(DateTime(1970)),
    categoryId: asIntOrNull(m[BudgetCols.categoryId]),
    amountCents: asInt(m[BudgetCols.amountCents]),
  );

  @override
  String toString() =>
      'Budget(#$id ${periodStart.iso} cat=$categoryId $amountCents)';
}

/// 预算派生值（口径 3.1 的唯一实现）。
///
/// ★ 最容易踩的一条：**额度 ≠ 可用额度**。借入（`count_in_budget = 1` 且落在
/// 本期）只抬「可用额度」，不改额度本身 —— 把 total 当 available 去算剩余，
/// 借入一打开进度条和剩余就对不上。
class BudgetStats {
  const BudgetStats({
    required this.totalBudgetCents,
    required this.usedCents,
    this.borrowedInBudgetCents = 0,
  });

  static const BudgetStats empty = BudgetStats(
    totalBudgetCents: null,
    usedCents: 0,
  );

  /// 该期总预算额度；**没有记录 → null**（不是 0）。
  final int? totalBudgetCents;

  /// 已用（本期支出侧，交叉归集 + 排除借贷）。
  final int usedCents;

  /// 本期计入预算的借入（只抬可用额度）。
  final int borrowedInBudgetCents;

  bool get hasBudget => totalBudgetCents != null;

  /// 可用额度 = 总额度 + 本期借入。
  int get availableCents => (totalBudgetCents ?? 0) + borrowedInBudgetCents;

  /// 剩余。**没设预算时返回 0**（不是负数）—— 界面据此隐藏进度条。
  int get leftCents => hasBudget ? availableCents - usedCents : 0;

  bool get overBudget => hasBudget && usedCents > availableCents;

  /// 超支金额；没超就是 0。
  int get overCents => overBudget ? usedCents - availableCents : 0;

  /// 花掉的比例，**不截断**（超支时 > 1，界面自己 `clamp(0,1)`）。
  double get usedRatio {
    if (!hasBudget) return 0;
    final int cap = availableCents;
    if (cap <= 0) return 0;
    return usedCents / cap;
  }

  BudgetStats copyWith({
    Object? totalBudgetCents = kUnset,
    int? usedCents,
    int? borrowedInBudgetCents,
  }) {
    return BudgetStats(
      totalBudgetCents: totalBudgetCents == kUnset
          ? this.totalBudgetCents
          : totalBudgetCents as int?,
      usedCents: usedCents ?? this.usedCents,
      borrowedInBudgetCents:
          borrowedInBudgetCents ?? this.borrowedInBudgetCents,
    );
  }

  @override
  String toString() =>
      'BudgetStats(total=$totalBudgetCents used=$usedCents borrowed=$borrowedInBudgetCents)';
}
