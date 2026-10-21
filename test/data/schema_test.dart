import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/db/migrations.dart';
import 'package:heita_ledger/data/db/schema.dart';
import 'package:sqflite/sqflite.dart';

import '../support/db_fixture.dart';

/// schema v1 的物理层断言。
///
/// 这一组测试的目的只有一个：**让 DDL 与代码里的列名清单不可能脱节**。
/// 原版 `txn.updated_at`（DDL 有、`toMap` 从不写、无人读）能活到 1.4.5，
/// 就是因为没有任何一条测试同时看两边。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  test('10 张表全部建出来了，且 PRAGMA 列名与 kTableColumns 完全一致（双向）', () async {
    final Database db = await Db.database();

    final List<Map<String, Object?>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );
    final Set<String> actual = tables
        .map((Map<String, Object?> row) => row['name']! as String)
        .toSet();
    expect(actual, kTableColumns.keys.toSet(), reason: '表集合必须完全一致');

    for (final String table in kTableColumns.keys) {
      final List<Map<String, Object?>> info = await db.rawQuery(
        'PRAGMA table_info($table)',
      );
      final Map<String, String> declared = kTableColumns[table]!;
      final Set<String> actualColumns = info
          .map((Map<String, Object?> row) => row['name']! as String)
          .toSet();

      // 双向：少一列（DDL 加了没登记）、多一列（登记了但没建）都要红
      expect(
        actualColumns.difference(declared.keys.toSet()),
        isEmpty,
        reason: '$table 多出了未登记的列',
      );
      expect(
        declared.keys.toSet().difference(actualColumns),
        isEmpty,
        reason: '$table 缺列',
      );

      for (final Map<String, Object?> row in info) {
        final String name = row['name']! as String;
        expect(
          row['type'],
          declared[name],
          reason: '$table.$name 的声明类型与登记不一致',
        );
      }
    }
  });

  test('所有 *_cents 列都是 INTEGER（金额单位是分，单位混淆是 R8）', () async {
    final Database db = await Db.database();
    int checked = 0;
    for (final String table in kTableColumns.keys) {
      final List<Map<String, Object?>> info = await db.rawQuery(
        'PRAGMA table_info($table)',
      );
      for (final Map<String, Object?> row in info) {
        final String name = row['name']! as String;
        if (!name.endsWith('_cents')) continue;
        expect(
          row['type'],
          'INTEGER',
          reason: '$table.$name 必须是 INTEGER（单位分）',
        );
        checked++;
      }
    }
    // v1 里共 9 个金额列：account 2 / txn 1 / budget 1 / debt 1 / recurring 1 /
    // txn_template 1 / saving_goal 2。数字变了说明 DDL 被改过，需要重新审。
    expect(checked, 9);
  });

  test('索引与唯一性全部按 kIndexes 建好（含 3 条部分唯一索引）', () async {
    final Database db = await Db.database();
    for (final MapEntry<String, ({String table, bool unique})> entry
        in kIndexes.entries) {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'PRAGMA index_list(${entry.value.table})',
      );
      final Map<String, Object?>? hit = rows
          .cast<Map<String, Object?>?>()
          .firstWhere(
            (Map<String, Object?>? row) => row?['name'] == entry.key,
            orElse: () => null,
          );
      expect(hit, isNotNull, reason: '索引 ${entry.key} 不存在');
      expect(
        hit!['unique'],
        entry.value.unique ? 1 : 0,
        reason: '${entry.key} 的唯一性不符合预期',
      );
    }
  });

  test('加强 ②：同一期插两行总预算 → 第二行抛 UNIQUE（ux_budget_total）', () async {
    final Database db = await Db.database();
    final int ledgerId = await Db.ensureCurrentLedgerId();

    await db.insert(Tables.budget, <String, Object?>{
      'ledger_id': ledgerId,
      'period_start': '2026-10-01',
      'category_id': null,
      'amount_cents': 600000,
    });

    await expectLater(
      db.insert(Tables.budget, <String, Object?>{
        'ledger_id': ledgerId,
        'period_start': '2026-10-01',
        'category_id': null,
        'amount_cents': 800000,
      }),
      throwsA(isA<DatabaseException>()),
      reason: '总预算（category_id IS NULL）在同一期只能有一行',
    );
  });

  test('加强 ②：同一期同一分类插两行分类预算 → 第二行抛 UNIQUE（ux_budget_cat）', () async {
    final Database db = await Db.database();
    final int ledgerId = await Db.ensureCurrentLedgerId();
    final int? catId = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT id FROM ${Tables.category} WHERE ledger_id = ? AND type = ? '
        'AND parent_id IS NULL ORDER BY sort_order LIMIT 1',
        <Object?>[ledgerId, 'expense'],
      ),
    );
    expect(catId, isNotNull);

    await db.insert(Tables.budget, <String, Object?>{
      'ledger_id': ledgerId,
      'period_start': '2026-10-01',
      'category_id': catId,
      'amount_cents': 100000,
    });

    await expectLater(
      db.insert(Tables.budget, <String, Object?>{
        'ledger_id': ledgerId,
        'period_start': '2026-10-01',
        'category_id': catId,
        'amount_cents': 200000,
      }),
      throwsA(isA<DatabaseException>()),
      reason: '同一期同一分类只能有一行预算（I10）',
    );
  });

  test('总预算与分类预算互不冲突（部分索引按 category_id 分流）', () async {
    final Database db = await Db.database();
    final int ledgerId = await Db.ensureCurrentLedgerId();
    final int? catId = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT id FROM ${Tables.category} WHERE ledger_id = ? LIMIT 1',
        <Object?>[ledgerId],
      ),
    );

    await db.insert(Tables.budget, <String, Object?>{
      'ledger_id': ledgerId,
      'period_start': '2026-11-01',
      'category_id': null,
      'amount_cents': 600000,
    });
    await db.insert(Tables.budget, <String, Object?>{
      'ledger_id': ledgerId,
      'period_start': '2026-11-01',
      'category_id': catId,
      'amount_cents': 100000,
    });

    expect(await Db.rowCount(Tables.budget), 2);
  });

  test('加强 ③：txn.period_start 是 NOT NULL —— 不带该列插入直接抛错', () async {
    final Database db = await Db.database();
    final int ledgerId = await Db.ensureCurrentLedgerId();

    await expectLater(
      db.insert(Tables.txn, <String, Object?>{
        'ledger_id': ledgerId,
        'type': 'expense',
        'amount_cents': -1200,
        'date': '2026-10-16',
        'created_at': '2026-10-16T10:00:00.000',
      }),
      throwsA(isA<DatabaseException>()),
      reason: '漏算归属期的流水必须插入失败，不能悄悄消失',
    );

    // 带上 period_start 就能插
    final int id = await db.insert(Tables.txn, <String, Object?>{
      'ledger_id': ledgerId,
      'type': 'expense',
      'amount_cents': -1200,
      'date': '2026-10-16',
      'period_start': '2026-10-15',
      'created_at': '2026-10-16T10:00:00.000',
    });
    expect(id, greaterThan(0));
  });

  test('加强 ①：同 recurring_id + date 的第二行抛 UNIQUE（ux_txn_recurring_date）', () async {
    final Database db = await Db.database();
    final int ledgerId = await Db.ensureCurrentLedgerId();

    Map<String, Object?> row(int recurringId) => <String, Object?>{
      'ledger_id': ledgerId,
      'type': 'expense',
      'amount_cents': -300000,
      'date': '2026-10-01',
      'period_start': '2026-10-01',
      'recurring_id': recurringId,
      'created_at': '2026-10-01T08:00:00.000',
    };

    await db.insert(Tables.txn, row(7));
    await expectLater(
      db.insert(Tables.txn, row(7)),
      throwsA(isA<DatabaseException>()),
      reason: '补记幂等的物理保障（I11）',
    );

    // 不同规则、或者 recurring_id 为 NULL（手记）都不受约束
    await db.insert(Tables.txn, row(8));
    await db.insert(Tables.txn, <String, Object?>{
      'ledger_id': ledgerId,
      'type': 'expense',
      'amount_cents': -500,
      'date': '2026-10-01',
      'period_start': '2026-10-01',
      'created_at': '2026-10-01T09:00:00.000',
    });
    await db.insert(Tables.txn, <String, Object?>{
      'ledger_id': ledgerId,
      'type': 'expense',
      'amount_cents': -600,
      'date': '2026-10-01',
      'period_start': '2026-10-01',
      'created_at': '2026-10-01T09:01:00.000',
    });
    expect(await Db.rowCount(Tables.txn), 4);
  });

  test('没有 4 个死列（ledger.archived / account.archived / saving_goal.archived / txn.updated_at）',
      () async {
    final Database db = await Db.database();
    Future<Set<String>> cols(String table) async {
      final List<Map<String, Object?>> info = await db.rawQuery(
        'PRAGMA table_info($table)',
      );
      return info
          .map((Map<String, Object?> row) => row['name']! as String)
          .toSet();
    }

    expect(await cols(Tables.ledger), isNot(contains('archived')));
    expect(await cols(Tables.account), isNot(contains('archived')));
    expect(await cols(Tables.savingGoal), isNot(contains('archived')));
    expect(await cols(Tables.txn), isNot(contains('updated_at')));
  });

  test('外键开着：ledger 被删时分类级联删除', () async {
    final Database db = await Db.database();
    final int ledgerId = await Db.ensureCurrentLedgerId();
    final int before = await Db.rowCount(Tables.category);
    expect(before, greaterThan(0));

    await db.delete(Tables.ledger, where: 'id = ?', whereArgs: <Object?>[ledgerId]);
    expect(await Db.rowCount(Tables.category), 0);
  });

  test('backfillMissingPeriods 在 v1 上恒为 0（period_start 非空）', () async {
    final Database db = await Db.database();
    expect(await backfillMissingPeriods(db), 0);
  });

  test('kSchemaVersion 是 1 且与迁移文件的常量同源', () {
    expect(kSchemaVersion, 1);
    expect(Tables.all.length, 10);
  });
}
