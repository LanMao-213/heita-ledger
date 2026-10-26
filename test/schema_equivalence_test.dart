// 迁移结构等价性自检（P1-2）。
//
// 与 `migrate_v5_to_v8_test.dart` 的分工：
//   · 那份管**数据**：流水不增删、余额一分不动、期初回填正确、体检干净。
//   · 这份管**结构**：老库升上来的表/列/索引，与全新装机的结构是否等价。
//
// 为什么结构也要测：漏一列时数据可能一条没错，但新代码写这一列会直接抛
// `no such column` —— 用户看到的是「升级后打不开」。这类错只能在结构层发现。
//
// v9（`txn.merchant`）落地前必须先有这个 harness：
//   往 `test/support/schema_diff.dart` 之外不用改，只要把 v9 的迁移写完，
//   这份测试自动开始守护它（因为迁移链终点跟着 `Db.schemaVersion` 走）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/schema_diff.dart';

const _migratedDb = 'test_schema_from_v5.db';
const _freshDb = 'test_schema_fresh.db';

Future<String> _pathOf(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

Future<void> _delete(String name) async {
  final f = File(await _pathOf(name));
  if (f.existsSync()) f.deleteSync();
}

/// v5 的库结构（历史快照，**不要跟着源码改**）。
///
/// 这是 1.1.x 时代真实装过的形状：分类还是一层平铺、`txn` 有 `period_start`
/// 但没有详情列与 `debt_id`、`account` 没有 `opening_cents`。
/// 索引列表同样按 v5 的实际情形给（`idx_txn_ledger_period` 是 v4 加
/// `period_start` 时一起建的）。
const _v5Tables = <String>[
  '''
  CREATE TABLE ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT 'book',
    sort_order INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT '')''',
  '''
  CREATE TABLE account (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'cash',
    balance_cents INTEGER NOT NULL DEFAULT 0,
    include_in_total INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0)''',
  '''
  CREATE TABLE category (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id INTEGER NOT NULL, type TEXT NOT NULL,
    name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT 'more',
    parent_id INTEGER, sort_order INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0)''',
  '''
  CREATE TABLE txn (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id INTEGER NOT NULL, type TEXT NOT NULL,
    amount_cents INTEGER NOT NULL, category_id INTEGER,
    account_id INTEGER, to_account_id INTEGER,
    date TEXT NOT NULL, period_start TEXT,
    note TEXT NOT NULL DEFAULT '',
    template_id INTEGER, recurring_id INTEGER,
    created_at TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT '')''',
  '''
  CREATE TABLE budget (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id INTEGER NOT NULL, period_start TEXT NOT NULL,
    category_id INTEGER, amount_cents INTEGER NOT NULL DEFAULT 0,
    UNIQUE (ledger_id, period_start, category_id))''',
  '''
  CREATE TABLE saving_goal (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT 'target',
    target_cents INTEGER NOT NULL DEFAULT 0,
    saved_cents INTEGER NOT NULL DEFAULT 0,
    due_month TEXT, sort_order INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0)''',
  '''
  CREATE TABLE recurring (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id INTEGER NOT NULL, type TEXT NOT NULL,
    amount_cents INTEGER NOT NULL, category_id INTEGER,
    account_id INTEGER, note TEXT NOT NULL DEFAULT '',
    freq TEXT NOT NULL DEFAULT 'monthly',
    interval INTEGER NOT NULL DEFAULT 1,
    next_run_date TEXT NOT NULL, end_date TEXT,
    enabled INTEGER NOT NULL DEFAULT 1)''',
  '''
  CREATE TABLE txn_template (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id INTEGER NOT NULL, name TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT 'tpl', type TEXT NOT NULL,
    amount_cents INTEGER NOT NULL DEFAULT 0,
    category_id INTEGER, account_id INTEGER,
    note TEXT NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL DEFAULT 0,
    use_count INTEGER NOT NULL DEFAULT 0,
    last_used_at TEXT)''',
  '''
  CREATE TABLE setting (k TEXT PRIMARY KEY, v TEXT NOT NULL)''',
];

/// v5 已存在的索引（必须与当年建库语句一致，否则「索引缺失」会是假警报）。
const _v5Indexes = <String>[
  'CREATE INDEX idx_txn_ledger_date ON txn (ledger_id, date)',
  'CREATE INDEX idx_txn_ledger_period ON txn (ledger_id, period_start)',
  'CREATE INDEX idx_txn_category ON txn (category_id)',
  'CREATE INDEX idx_txn_account ON txn (account_id)',
  'CREATE INDEX idx_recurring_next ON recurring (enabled, next_run_date)',
];

Future<void> _makeV5(String name) async {
  await _delete(name);
  final db = await databaseFactory.openDatabase(
    await _pathOf(name),
    options: OpenDatabaseOptions(
      version: 5,
      onCreate: (db, _) async {
        await execAll(db, _v5Tables);
        await execAll(db, _v5Indexes);
      },
    ),
  );
  await db.close();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await Db.close();
    await _delete(_migratedDb);
    await _delete(_freshDb);
  });

  tearDown(() async {
    await Db.close();
    await _delete(_migratedDb);
    await _delete(_freshDb);
  });

  test('v5 老库迁移上来的结构 == 全新装机的结构', () async {
    // --- 迁移库：v5 打开即跑 onUpgrade(v5→当前) ---
    await _makeV5(_migratedDb);
    Db.fileName = _migratedDb;
    final migratedDb = await Db.open();
    expect(await migratedDb.getVersion(), Db.schemaVersion,
        reason: '迁移没跑到当前版本');
    final migrated = await SchemaSnapshot.read(migratedDb);
    await Db.close();

    // --- 全新装机 ---
    Db.fileName = _freshDb;
    final freshDb = await Db.open();
    final fresh = await SchemaSnapshot.read(freshDb);
    await Db.close();

    final diff = migrated.diffTo(fresh);
    expect(
      diff.hard,
      isEmpty,
      reason: '${diff.report()}\n--- 迁移库现场 ---\n${migrated.describe()}',
    );
  });

  // ------------------------------------------------------------------
  // 工具自检：比对器本身必须能抓到错，否则它「永远通过」比不存在更危险
  // （这条经验来自 10-24 的隐私扫描器：写好之后一直 exit 1，没人发现）。
  // ------------------------------------------------------------------
  test('自检：漏一列能被抓出来', () async {
    Db.fileName = _freshDb;
    final db = await Db.open();
    final before = await SchemaSnapshot.read(db);
    await db.execute('ALTER TABLE txn ADD COLUMN __probe INTEGER');
    final after = await SchemaSnapshot.read(db);
    await Db.close();

    final diff = before.diffTo(after);
    expect(diff.ok, isFalse);
    expect(diff.hard.any((s) => s.contains('__probe')), isTrue,
        reason: '新增的列必须被报成硬差异');
  });

  test('自检：漏一个索引能被抓出来', () async {
    Db.fileName = _freshDb;
    final db = await Db.open();
    final before = await SchemaSnapshot.read(db);
    await db.execute('DROP INDEX idx_txn_category');
    final after = await SchemaSnapshot.read(db);
    await Db.close();

    final diff = before.diffTo(after);
    expect(diff.ok, isFalse);
    expect(diff.hard.any((s) => s.contains('idx_txn_category')), isTrue);
  });

  test('自检：列顺序不同只算软差异，不报红', () async {
    Db.fileName = _freshDb;
    final db = await Db.open();
    final before = await SchemaSnapshot.read(db);
    // SQLite 无法直接改列顺序，这里用「同一份快照换一个顺序」验证判定口径
    final reordered = SchemaSnapshot({
      for (final e in before.tables.entries)
        e.key: Map.fromEntries(e.value.entries.toList().reversed),
    }, before.indexes);
    await Db.close();

    final diff = before.diffTo(reordered);
    expect(diff.ok, isTrue, reason: diff.report());
    expect(diff.soft, isNotEmpty, reason: '列顺序差异应当被记录下来');
  });
}
