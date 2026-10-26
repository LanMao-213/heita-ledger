/// 备份**字段级**兼容层。
///
/// ## 为什么需要单独一层
///
/// 恢复一条备份，本质上是「把若干年前的 JSON 塞进今天的表结构」。版本差异
/// 有三种，处理方式完全不同：
///
/// | 差异 | 例子 | 处理 |
/// |---|---|---|
/// | 旧备份**少**列 | v5 的 `txn` 没有 `place_from` / `person` / `debt_id` | 不填，走列的默认值（NULL / DEFAULT），不算错误 |
/// | 旧备份**多**列 | 某列后来被改名或废弃（如 `budget.month` → `period_start`） | 换名或丢弃，**不能让整次恢复失败** |
/// | 必填列缺失 | 手工改坏的备份里 `txn` 没有 `date` | 明确报错，说清是哪张表哪一列 |
///
/// 之前只有一条特例（`budget.month` → `period_start`）硬编码在 `Repo` 里，
/// 其余情况全靠 SQLite：多一列就 `no such column` 整次失败，少一列则
/// 静默走默认值 —— 前者用户只看到一串英文，后者没人知道发生过什么。
///
/// 这一层把三件事做成**规则**而不是散落的 if：
/// 1. 未知列丢弃并记账（[ConformReport.dropped]）；
/// 2. 缺列时按列的 `NOT NULL` / `DEFAULT` 判断可否放过；
/// 3. 类型对齐（JSON 里的 `true/false` → `1/0`）。
///
/// ## 设计约束
///
/// - **纯函数**：不碰数据库、不碰文件，传入 `PRAGMA table_info` 的结果即可测；
/// - **不改语义**：能映射的映射（`month` → `period_start`），映射不了才丢；
/// - **有账可查**：每一次丢弃 / 补齐都进 [ConformReport]，界面可以告诉用户。
library;

/// 一列的结构信息（来自 `PRAGMA table_info`）。
class BackupColumn {
  const BackupColumn({
    required this.name,
    required this.type,
    required this.notNull,
    required this.hasDefault,
    required this.pk,
  });

  final String name;
  final String type;
  final bool notNull;

  /// 有 `DEFAULT` 就允许缺值 —— 缺了它会自动补上，不用我们操心。
  final bool hasDefault;
  final int pk;

  bool get integer => type.toUpperCase().contains('INT');

  static BackupColumn fromPragma(Map<String, Object?> row) => BackupColumn(
    name: row['name'] as String,
    type: (row['type'] as String?) ?? '',
    notNull: (row['notnull'] as int? ?? 0) != 0,
    hasDefault: (row['dflt_value'] as String?) != null,
    pk: row['pk'] as int? ?? 0,
  );
}

/// 兼容动作的账本。调用方可以在恢复完成后告诉用户「有 N 个旧字段被忽略」。
class ConformReport {
  /// 被丢弃的旧列，形如 `txn.old_column`
  final List<String> dropped = [];

  /// 被换名的旧列，形如 `budget.month → period_start`
  final List<String> renamed = [];

  /// 类型被纠正的格子，形如 `account.include_in_total: bool→int`
  final List<String> coerced = [];

  bool get clean => dropped.isEmpty && renamed.isEmpty && coerced.isEmpty;

  /// 给界面用的一句话；没有动作时为 null（不占版面）。
  String? get summary {
    if (clean) return null;
    final parts = <String>[
      if (dropped.isNotEmpty) '忽略 ${dropped.length} 个旧字段',
      if (renamed.isNotEmpty) '换算 ${renamed.length} 个字段名',
      if (coerced.isNotEmpty) '纠正 ${coerced.length} 个值类型',
    ];
    return parts.join(' · ');
  }
}

/// 必填列缺失时抛这个 —— 调用方应把它翻成用户能看懂的话。
class BackupFieldException implements Exception {
  BackupFieldException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 旧列名 → 新列名的映射（**只在目标列缺失时启用**）。
///
/// `budget.month`（v4 及更早）→ `period_start`（v5 起）：账单日为 1 时
/// `2026-10` → `2026-10-01` 无损，这也是当年迁移的口径。
const _renames = <String, Map<String, String>>{
  'budget': {'month': 'period_start'},
};

/// 换名后需要补的后缀（`2026-10` + `-01`）。
const _renameSuffix = <String, String>{
  'budget.month': '-01',
};

/// 把一行旧数据整成当前 schema 的形状。
///
/// @param columns 当前表的列（键为列名），由调用方用 `PRAGMA table_info` 取
Map<String, Object?> conformRow({
  required String table,
  required Map<String, Object?> row,
  required Map<String, BackupColumn> columns,
  required ConformReport report,
}) {
  final out = <String, Object?>{};

  for (final entry in row.entries) {
    final key = entry.key;
    final value = entry.value;
    final col = columns[key];

    if (col != null) {
      out[key] = _coerce(table, col, value, report);
      continue;
    }

    // 未知列：先看能不能换成现名，换不了就丢
    final target = _renames[table]?[key];
    if (target != null && columns.containsKey(target) && !out.containsKey(target)) {
      final suffix = _renameSuffix['$table.$key'] ?? '';
      out[target] = value is String ? '$value$suffix' : value;
      report.renamed.add('$table.$key → $target');
      continue;
    }
    report.dropped.add('$table.$key');
  }

  // 缺列检查：只有「NOT NULL 且没有默认值」才算错
  for (final col in columns.values) {
    if (out.containsKey(col.name)) continue;
    if (col.pk != 0) continue; // 主键缺了由 SQLite 自增，不是问题
    if (col.notNull && !col.hasDefault) {
      throw BackupFieldException(
        '备份里的「$table」缺少必填字段「${col.name}」，这份文件可能被改坏了',
      );
    }
  }

  return out;
}

Object? _coerce(
  String table,
  BackupColumn col,
  Object? value,
  ConformReport report,
) {
  if (value == null) return null;
  if (col.integer && value is bool) {
    report.coerced.add('$table.${col.name}: bool→int');
    return value ? 1 : 0;
  }
  // JSON 里数字统一解成 int/double；整数值的 double 直接落 int，
  // 否则 SQLite 会把 12.0 存成 REAL，和 INTEGER 列对不上（`==` 查询仍可用，
  // 但导出的 JSON 会一版 int 一版 double，对比时很难看）。
  if (col.integer && value is double && value == value.roundToDouble()) {
    return value.toInt();
  }
  return value;
}
