import 'models.dart';

/// 储蓄目标。全局（跨账本）：目标跟着人走，不跟着账本走。
///
/// 与流水**不联动**：存钱/取钱只改 `saved_cents`，不生成流水
/// （否则「存钱」会变成一笔支出，预算与统计全被污染）。
class SavingGoal {
  const SavingGoal({
    this.id,
    required this.name,
    this.icon = 'target',
    this.targetCents = 0,
    this.savedCents = 0,
    this.dueMonth,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final String icon;
  final int targetCents;
  final int savedCents;

  /// 目标月份 `YYYY-MM`，可空。
  final String? dueMonth;
  final int sortOrder;

  /// 还差多少（目标 − 已存，最小 0）。
  int get remainingCents {
    final int left = targetCents - savedCents;
    return left < 0 ? 0 : left;
  }

  /// 已存比例 0–1（不截断上界，超额存款时 > 1，界面自己 clamp）。
  double get progress {
    if (targetCents <= 0) return 0;
    return savedCents / targetCents;
  }

  bool get isDone => targetCents > 0 && savedCents >= targetCents;

  SavingGoal copyWith({
    int? id,
    String? name,
    String? icon,
    int? targetCents,
    int? savedCents,
    Object? dueMonth = kUnset,
    int? sortOrder,
  }) {
    return SavingGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      targetCents: targetCents ?? this.targetCents,
      savedCents: savedCents ?? this.savedCents,
      dueMonth: dueMonth == kUnset ? this.dueMonth : dueMonth as String?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// 覆盖 DDL 全部 7 列。
  Map<String, Object?> toMap() => <String, Object?>{
    GoalCols.id: id,
    GoalCols.name: name,
    GoalCols.icon: icon,
    GoalCols.targetCents: targetCents,
    GoalCols.savedCents: savedCents,
    GoalCols.dueMonth: dueMonth,
    GoalCols.sortOrder: sortOrder,
  };

  factory SavingGoal.fromMap(Map<String, Object?> m) => SavingGoal(
    id: asIntOrNull(m[GoalCols.id]),
    name: asString(m[GoalCols.name]),
    icon: asString(m[GoalCols.icon], 'target'),
    targetCents: asInt(m[GoalCols.targetCents]),
    savedCents: asInt(m[GoalCols.savedCents]),
    dueMonth: asStringOrNull(m[GoalCols.dueMonth]),
    sortOrder: asInt(m[GoalCols.sortOrder]),
  );

  @override
  String toString() => 'SavingGoal(#$id $name $savedCents/$targetCents)';
}
