part of '../models.dart';

// ---------------------------------------------------------------------------
// 账本 / 账户 / 分类
// ---------------------------------------------------------------------------

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
