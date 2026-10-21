import 'models.dart';

/// 账本。纯数据，不含任何 IO。
class Ledger {
  const Ledger({
    this.id,
    required this.name,
    this.icon = 'book',
    this.sortOrder = 0,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final String icon;
  final int sortOrder;
  final DateTime createdAt;

  Ledger copyWith({
    int? id,
    String? name,
    String? icon,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return Ledger(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 覆盖 DDL 全部 5 列。`id` 为 null 表示交给自增。
  Map<String, Object?> toMap() => <String, Object?>{
    LedgerCols.id: id,
    LedgerCols.name: name,
    LedgerCols.icon: icon,
    LedgerCols.sortOrder: sortOrder,
    LedgerCols.createdAt: createdAt.toIso8601String(),
  };

  factory Ledger.fromMap(Map<String, Object?> m) => Ledger(
    id: asIntOrNull(m[LedgerCols.id]),
    name: asString(m[LedgerCols.name]),
    icon: asString(m[LedgerCols.icon], 'book'),
    sortOrder: asInt(m[LedgerCols.sortOrder]),
    createdAt: asDateTimeOrNull(m[LedgerCols.createdAt]) ?? DateTime(1970),
  );

  @override
  String toString() => 'Ledger(#$id $name)';
}
