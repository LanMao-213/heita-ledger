// schema 等价比对工具（测试专用，不进 lib）。
//
// ## 它解决什么问题
//
// 迁移的坑分两种：
//   1. **数据错**（迁移把余额算歪了）—— 已有 `migrate_v5_to_v8_test.dart` 那种
//      断言能挡住：流水不变、余额不变、恒等式成立。
//   2. **结构错**（迁移漏了列 / 列类型不同 / 漏了索引）—— 数据一条没错，
//      但新代码 `UPDATE txn SET merchant = ?` 直接抛 `no such column`，
//      用户看到的是**升级后打不开 App**。这类错只有比对结构才能提前发现。
//
// 所以这个工具回答一个问题：
//   **「老库升上来的结构」与「全新装机的结构」是不是同一个东西？**
//
// ## 一条必须写死的判定口径
//
// SQLite 的 `ALTER TABLE ADD COLUMN` **只能追加到末尾**，所以迁移上来的表
// 列顺序天然与全新装机不同（全新装机按源码里的书写顺序建表）。
// 列顺序不影响任何按名取值的 SQL，因此：
//
//   - **硬差异**（必须为空）：表缺失/多余、列缺失/多余、类型、NOT NULL、
//     默认值、主键标记、索引名与索引 SQL。
//   - **软差异**（只报告，不算失败）：同一张表内**列顺序**不同。
//
// 把列顺序当硬失败，会让这个工具天天报红，最后没人看它 —— 那比不写更糟。
//
// ## 为什么算「索引 SQL」而不只算索引名
//
// 名字一样、列不一样（`(ledger_id, date)` 写成 `(date)`）时，
// 查得到数据但会全表扫，慢到用户以为卡死。只比名字会漏掉这种。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 一列的结构。
class ColumnDef {
  ColumnDef({
    required this.name,
    required this.type,
    required this.notNull,
    required this.defaultValue,
    required this.pk,
  });

  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final int pk;

  /// 只比这些属性，不比 cid（列顺序）。
  String get signature =>
      '${type.toUpperCase()}|notnull=${notNull ? 1 : 0}'
      '|default=${defaultValue ?? 'NULL'}|pk=$pk';

  @override
  String toString() => '$name($signature)';
}

/// 一个库的完整结构快照。
class SchemaSnapshot {
  SchemaSnapshot(this.tables, this.indexes);

  /// 表名 → (列名 → 列结构)。用 Map 而不是 List，就是为了让比对与列顺序无关。
  final Map<String, Map<String, ColumnDef>> tables;

  /// 索引名 → 归一化后的建索引 SQL。
  final Map<String, String> indexes;

  static Future<SchemaSnapshot> read(Database db) async {
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
      "AND name NOT LIKE 'android_%' ORDER BY name",
    );
    final tables = <String, Map<String, ColumnDef>>{};
    for (final row in tableRows) {
      final name = row['name'] as String;
      final cols = await db.rawQuery('PRAGMA table_info(`$name`)');
      tables[name] = {
        for (final c in cols)
          c['name'] as String: ColumnDef(
            name: c['name'] as String,
            type: (c['type'] as String?) ?? '',
            notNull: (c['notnull'] as int? ?? 0) != 0,
            defaultValue: c['dflt_value'] as String?,
            pk: c['pk'] as int? ?? 0,
          ),
      };
    }

    // sqlite_autoindex_* 是 UNIQUE 约束生成的隐式索引，名字由 SQLite 自己编号；
    // 表 DDL 里有没有 UNIQUE 已经由「列结构 + 业务不变量测试」间接保证，
    // 这里只比**显式创建**的索引。
    final indexRows = await db.rawQuery(
      "SELECT name, tbl_name, sql FROM sqlite_master "
      "WHERE type = 'index' AND sql IS NOT NULL ORDER BY name",
    );
    final indexes = <String, String>{};
    for (final row in indexRows) {
      indexes[row['name'] as String] = _normalizeSql(
        (row['sql'] as String?) ?? '',
      );
    }
    return SchemaSnapshot(tables, indexes);
  }

  /// 顺序无关的比对（列按名字比、索引按名字+SQL 比）。
  SchemaDiff diffTo(SchemaSnapshot other) {
    final hard = <String>[];
    final soft = <String>[];

    for (final name in tables.keys) {
      if (!other.tables.containsKey(name)) {
        hard.add('表 $name 只在「迁移库」存在，全新装机没有');
      }
    }
    for (final name in other.tables.keys) {
      if (!tables.containsKey(name)) {
        hard.add('表 $name 全新装机有，迁移库**缺失**');
      }
    }

    for (final name in tables.keys) {
      final mine = tables[name]!;
      final theirs = other.tables[name];
      if (theirs == null) continue;

      for (final col in mine.keys) {
        if (!theirs.containsKey(col)) {
          hard.add('$name.$col 只在迁移库存在，全新装机没有');
        }
      }
      for (final col in theirs.keys) {
        if (!mine.containsKey(col)) {
          hard.add('$name.$col 全新装机有，迁移库**缺失**');
        }
      }
      for (final col in mine.keys) {
        final a = mine[col]!;
        final b = theirs[col];
        if (b == null) continue;
        if (a.signature != b.signature) {
          hard.add('$name.$col 结构不同：迁移库 ${a.signature} ≠ 全新装机 ${b.signature}');
        }
      }

      // 列顺序（软差异）
      final orderA = mine.keys.join(',');
      final orderB = theirs.keys.join(',');
      if (orderA != orderB) {
        soft.add('$name 列顺序不同（ALTER 追加列导致，不影响按名取值）');
      }
    }

    for (final name in indexes.keys) {
      if (!other.indexes.containsKey(name)) {
        hard.add('索引 $name 只在迁移库存在');
      }
    }
    for (final name in other.indexes.keys) {
      if (!indexes.containsKey(name)) {
        hard.add('索引 $name 全新装机有，迁移库**缺失**（查询会退化成全表扫）');
      }
    }
    for (final name in indexes.keys) {
      final b = other.indexes[name];
      if (b == null) continue;
      if (indexes[name] != b) {
        hard.add('索引 $name 定义不同：\n    迁移库 ${indexes[name]}\n    全新装机 $b');
      }
    }

    return SchemaDiff(hard: hard, soft: soft);
  }

  /// 供失败时打印现场用。
  String describe() {
    final b = StringBuffer();
    b.writeln('表 ${tables.length} 张，索引 ${indexes.length} 个');
    for (final e in tables.entries) {
      b.writeln('  ${e.key}: ${e.value.values.map((c) => c.name).join(', ')}');
    }
    return b.toString();
  }
}

class SchemaDiff {
  SchemaDiff({required this.hard, required this.soft});

  final List<String> hard;
  final List<String> soft;

  bool get ok => hard.isEmpty;

  String report() {
    final b = StringBuffer();
    if (hard.isEmpty) {
      b.writeln('结构一致（软差异 ${soft.length} 条）');
    } else {
      b.writeln('发现 ${hard.length} 处**硬差异**：');
      for (final s in hard) {
        b.writeln('  - $s');
      }
    }
    if (soft.isNotEmpty) {
      b.writeln('软差异（可接受）：');
      for (final s in soft) {
        b.writeln('  ~ $s');
      }
    }
    return b.toString();
  }
}

/// 小写 + 折叠空白，避免「多一个空格」被判成结构不同。
String _normalizeSql(String sql) =>
    sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// 建一个空库并把 `sql` 全跑一遍（测试里造夹具用）。
Future<void> execAll(Database db, List<String> statements) async {
  for (final s in statements) {
    await db.execute(s);
  }
}
