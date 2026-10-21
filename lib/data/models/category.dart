import 'models.dart';

/// 分类。两级硬上限：[parentId] 要么为 null（一级），要么指向一个一级分类。
class Category {
  const Category({
    this.id,
    this.ledgerId = 0,
    required this.type,
    required this.name,
    this.icon = 'more',
    this.parentId,
    this.sortOrder = 0,
    this.archived = false,
  });

  final int? id;
  final int ledgerId;
  final TxnType type;
  final String name;
  final String icon;

  /// null = 一级分类。
  final int? parentId;

  /// 排序号，**按同级分组**各自从 0 起。
  final int sortOrder;

  /// 停用（不再出现在录入里，但历史账目照常显示名字）。
  final bool archived;

  bool get isTop => parentId == null;
  bool get isChild => parentId != null;

  Category copyWith({
    int? id,
    int? ledgerId,
    TxnType? type,
    String? name,
    String? icon,
    Object? parentId = kUnset,
    int? sortOrder,
    bool? archived,
  }) {
    return Category(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      type: type ?? this.type,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      parentId: parentId == kUnset ? this.parentId : parentId as int?,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  /// 覆盖 DDL 全部 8 列。
  Map<String, Object?> toMap() => <String, Object?>{
    CategoryCols.id: id,
    CategoryCols.ledgerId: ledgerId,
    CategoryCols.type: type.code,
    CategoryCols.name: name,
    CategoryCols.icon: icon,
    CategoryCols.parentId: parentId,
    CategoryCols.sortOrder: sortOrder,
    CategoryCols.archived: boolToInt(archived),
  };

  factory Category.fromMap(Map<String, Object?> m) => Category(
    id: asIntOrNull(m[CategoryCols.id]),
    ledgerId: asInt(m[CategoryCols.ledgerId]),
    type: TxnType.parseOrExpense(asStringOrNull(m[CategoryCols.type])),
    name: asString(m[CategoryCols.name]),
    icon: asString(m[CategoryCols.icon], 'more'),
    parentId: asIntOrNull(m[CategoryCols.parentId]),
    sortOrder: asInt(m[CategoryCols.sortOrder]),
    archived: asBool(m[CategoryCols.archived]),
  );

  @override
  String toString() => 'Category(#$id $name parent=$parentId)';
}

/// 两级分类树。构建 O(n)，之后 O(1) 查子级。
///
/// 为什么不每次都 `WHERE parent_id = ?` 查一遍：录入面板要在同一次构建里
/// 反复取「某个一级下的子分类」（轮盘滚动时每帧都要），查询会变成 N+1。
class CategoryTree {
  CategoryTree(Iterable<Category> all)
    : _all = List<Category>.unmodifiable(all),
      _byId = <int, Category>{
        for (final Category c in all)
          if (c.id != null) c.id!: c,
      },
      _children = _groupChildren(all),
      _tops = _topList(all);

  /// 空树（首帧 / 账本还没加载时用，避免到处判 null）。
  static final CategoryTree empty = CategoryTree(const <Category>[]);

  final List<Category> _all;
  final Map<int, Category> _byId;
  final Map<int, List<Category>> _children;
  final List<Category> _tops;

  static Map<int, List<Category>> _groupChildren(Iterable<Category> all) {
    final Map<int, List<Category>> m = <int, List<Category>>{};
    for (final Category c in all) {
      if (c.isChild) m.putIfAbsent(c.parentId!, () => <Category>[]).add(c);
    }
    for (final List<Category> list in m.values) {
      list.sort(_bySortOrder);
    }
    return m;
  }

  static List<Category> _topList(Iterable<Category> all) {
    final List<Category> tops = <Category>[
      for (final Category c in all)
        if (c.isTop) c,
    ]..sort(_bySortOrder);
    return List<Category>.unmodifiable(tops);
  }

  static int _bySortOrder(Category a, Category b) {
    final int byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  /// 全部分类（含停用的，按落库顺序）。
  List<Category> get all => _all;

  /// 一级分类（含停用；界面自己按 `archived` 过滤）。
  List<Category> get tops => _tops;

  /// 某个一级下的子分类（按 sort_order）。
  List<Category> childrenOf(int? parentId) =>
      List<Category>.unmodifiable(_children[parentId] ?? const <Category>[]);

  Category? byId(int? id) => id == null ? null : _byId[id];

  /// 分类名（子分类显示成「餐饮 · 正餐」）。
  String displayName(int? id) {
    final Category? c = byId(id);
    if (c == null) return '未分类';
    if (c.isTop) return c.name;
    final Category? parent = byId(c.parentId);
    return parent == null ? c.name : '${parent.name} · ${c.name}';
  }

  /// 一级分类名（子分类返回父级名，用于抬期白名单与预算归集）。
  String? topNameOf(int? id) {
    final Category? c = byId(id);
    if (c == null) return null;
    if (c.isTop) return c.name;
    return byId(c.parentId)?.name;
  }

  /// 这个分类自身 + 它的子分类 id（一级传父级，返回整棵子树的一层）。
  ///
  /// 预算「已花」与筛选都要它：记到「正餐」必须能算进「餐饮」的进度条。
  List<int> selfAndChildIds(int? id) {
    final Category? c = byId(id);
    if (c == null) return const <int>[];
    if (c.isChild) return <int>[c.id!];
    return <int>[
      c.id!,
      for (final Category child in childrenOf(c.id)) child.id!,
    ];
  }

  /// 按类型过滤的一级分类（录入面板的两个轮盘）。
  List<Category> topsOf(TxnType type, {bool includeArchived = false}) => <Category>[
    for (final Category c in _tops)
      if (c.type == type && (includeArchived || !c.archived)) c,
  ];

  bool get isEmpty => _all.isEmpty;
}
