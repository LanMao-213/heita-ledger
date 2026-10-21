import 'models.dart';

/// 记账模板（「记一笔」面板上的快捷入口）。
class TxnTemplate {
  const TxnTemplate({
    this.id,
    this.ledgerId = 0,
    required this.name,
    this.icon = 'tpl',
    required this.type,
    this.amountCents = 0,
    this.categoryId,
    this.accountId,
    this.note = '',
    this.sortOrder = 0,
    this.useCount = 0,
    this.lastUsedAt,
  });

  final int? id;
  final int ledgerId;
  final String name;
  final String icon;
  final TxnType type;
  final int amountCents;
  final int? categoryId;
  final int? accountId;
  final String note;
  final int sortOrder;

  /// 用过几次（`touch` 时 +1）。
  final int useCount;

  /// 最后一次用的时刻（决定「最近 3 个」的顺序）。
  final DateTime? lastUsedAt;

  /// 最近使用排序：**用过次数多的在前**，同次数按最后使用时间倒序，
  /// 再按 `sort_order`、`id` 兜底，保证同数据两次结果一致。
  ///
  /// 为什么不只按 `last_used_at`：偶尔用过一次的老模板会把天天用的挤下去。
  static int recentSort(TxnTemplate a, TxnTemplate b) {
    final int byCount = b.useCount.compareTo(a.useCount);
    if (byCount != 0) return byCount;

    final DateTime? al = a.lastUsedAt;
    final DateTime? bl = b.lastUsedAt;
    if (al != bl) {
      if (al == null) return 1;
      if (bl == null) return -1;
      return bl.compareTo(al);
    }
    final int byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  TxnTemplate copyWith({
    int? id,
    int? ledgerId,
    String? name,
    String? icon,
    TxnType? type,
    int? amountCents,
    Object? categoryId = kUnset,
    Object? accountId = kUnset,
    String? note,
    int? sortOrder,
    int? useCount,
    Object? lastUsedAt = kUnset,
  }) {
    return TxnTemplate(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      categoryId: categoryId == kUnset ? this.categoryId : categoryId as int?,
      accountId: accountId == kUnset ? this.accountId : accountId as int?,
      note: note ?? this.note,
      sortOrder: sortOrder ?? this.sortOrder,
      useCount: useCount ?? this.useCount,
      lastUsedAt: lastUsedAt == kUnset
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
    );
  }

  /// 覆盖 DDL 全部 12 列。
  Map<String, Object?> toMap() => <String, Object?>{
    TemplateCols.id: id,
    TemplateCols.ledgerId: ledgerId,
    TemplateCols.name: name,
    TemplateCols.icon: icon,
    TemplateCols.type: type.code,
    TemplateCols.amountCents: amountCents,
    TemplateCols.categoryId: categoryId,
    TemplateCols.accountId: accountId,
    TemplateCols.note: note,
    TemplateCols.sortOrder: sortOrder,
    TemplateCols.useCount: useCount,
    TemplateCols.lastUsedAt: lastUsedAt?.toIso8601String(),
  };

  factory TxnTemplate.fromMap(Map<String, Object?> m) => TxnTemplate(
    id: asIntOrNull(m[TemplateCols.id]),
    ledgerId: asInt(m[TemplateCols.ledgerId]),
    name: asString(m[TemplateCols.name]),
    icon: asString(m[TemplateCols.icon], 'tpl'),
    type: TxnType.parseOrExpense(asStringOrNull(m[TemplateCols.type])),
    amountCents: asInt(m[TemplateCols.amountCents]),
    categoryId: asIntOrNull(m[TemplateCols.categoryId]),
    accountId: asIntOrNull(m[TemplateCols.accountId]),
    note: asString(m[TemplateCols.note]),
    sortOrder: asInt(m[TemplateCols.sortOrder]),
    useCount: asInt(m[TemplateCols.useCount]),
    lastUsedAt: asDateTimeOrNull(m[TemplateCols.lastUsedAt]),
  );

  @override
  String toString() => 'TxnTemplate(#$id $name used=$useCount)';
}
