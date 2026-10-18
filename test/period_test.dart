// 归属期（period_start）落地自检 —— F5 阶段 2。
//
// 这一阶段**不改任何查询**，所以界面上看不出区别；真正会出事的地方全在暗处：
// 1) 老库升级后 `period_start` 全为空 → 阶段 3 一旦切查询，历史记录会集体消失；
// 2) 写入路径漏算（新增/改日期/周期账单自动补记）→ 那条记录停在旧期，
//    表现是「合计里有这笔、明细里找不到」，用户无法自查；
// 3) 抬期把两个月工资挤进同一期 → 数字对不上，却看不出是算法错。
//
// 所以这里钉的是「每一笔落在哪一期」，而不是界面。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/cycle.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_period.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 造一个 v3 老库：`txn` 没有 `period_start`，其余走 onUpgrade 会碰到的表都建齐。
Future<void> _makeV3Db() async {
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();

  final db = await databaseFactory.openDatabase(
    await _dbPath(),
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE ledger (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT NOT NULL,
            icon        TEXT NOT NULL DEFAULT 'book',
            sort_order  INTEGER NOT NULL DEFAULT 0,
            archived    INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute('''
          CREATE TABLE category (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id   INTEGER NOT NULL,
            type        TEXT    NOT NULL,
            name        TEXT    NOT NULL,
            icon        TEXT    NOT NULL DEFAULT 'more',
            parent_id   INTEGER,
            sort_order  INTEGER NOT NULL DEFAULT 0,
            archived    INTEGER NOT NULL DEFAULT 0
          )''');
        // ★ v3 的 txn：没有 period_start
        await db.execute('''
          CREATE TABLE txn (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id     INTEGER NOT NULL,
            type          TEXT    NOT NULL,
            amount_cents  INTEGER NOT NULL,
            category_id   INTEGER,
            account_id    INTEGER,
            to_account_id INTEGER,
            date          TEXT    NOT NULL,
            note          TEXT    NOT NULL DEFAULT '',
            template_id   INTEGER,
            recurring_id  INTEGER,
            created_at    TEXT    NOT NULL DEFAULT '',
            updated_at    TEXT    NOT NULL DEFAULT ''
          )''');
        await db.execute(
          'CREATE TABLE setting (k TEXT PRIMARY KEY, v TEXT NOT NULL)',
        );

        await db.insert('ledger', {
          'name': '老账本',
          'icon': 'book',
          'sort_order': 0,
          'archived': 0,
          'created_at': '',
        });
        await db.insert('category', {
          'ledger_id': 1,
          'type': 'expense',
          'name': '餐饮',
          'icon': 'food',
          'sort_order': 0,
          'archived': 0,
        });
        // 老数据：一笔 10 月 10 日的支出
        await db.insert('txn', {
          'ledger_id': 1,
          'type': 'expense',
          'amount_cents': 1250,
          'category_id': 1,
          'date': '2026-10-10',
          'note': '午饭',
        });
      },
    ),
  );
  await db.close();
}

void main() {
  late int ledgerId;
  late int catFood;
  late int catSalary;
  late int catBonus;
  late int catCommission;
  late int catParttime;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 各测试文件各用各的库文件，避免并行时抢同一个 sqlite 文件
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();

    await Db.open();
    ledgerId = await Repo.currentLedgerId();

    final expenses = await Repo.listCategories(ledgerId, type: TxnType.expense);
    final incomes = await Repo.listCategories(ledgerId, type: TxnType.income);
    catFood = expenses.firstWhere((c) => c.name == '餐饮').id;
    catSalary = incomes.firstWhere((c) => c.name == '工资').id;
    catBonus = incomes.firstWhere((c) => c.name == '奖金').id;
    catCommission = incomes.firstWhere((c) => c.name == '提成').id;
    catParttime = incomes.firstWhere((c) => c.name == '兼职').id;
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  /// 记一笔，直接返回落库后的 period_start
  Future<String?> add({
    required TxnType type,
    required String date,
    required int categoryId,
    int cents = 1000,
  }) async {
    final id = await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: type,
        amountCents: cents,
        date: date,
        categoryId: categoryId,
      ),
    );
    final db = await Db.open();
    final row = await db.query(
      'txn',
      columns: ['period_start'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return row.first['period_start'] as String?;
  }

  /// 按 id 读回整条记录。
  ///
  /// 不能用 `listTxns(month:)` 读：阶段 3 起它按**归属期**筛，账单日 15 时
  /// 10-10 那笔属于 09-15 期，按月查会查不到 —— 那正是这个阶段要的效果。
  Future<Txn> byId(int id) async {
    final db = await Db.open();
    final row = await db.query('txn', where: 'id = ?', whereArgs: [id]);
    return Txn.fromMap(row.first);
  }

  group('账单日默认 1（= 自然月，老用户行为不变）', () {
    test('支出落在月初', () async {
      expect(
        await add(
          type: TxnType.expense,
          date: '2026-10-10',
          categoryId: catFood,
        ),
        '2026-10-01',
      );
    });

    test('工资不抬期：账单日为 1 时没有日期能早于当月 1 号', () async {
      expect(
        await add(
          type: TxnType.income,
          date: '2026-10-10',
          categoryId: catSalary,
        ),
        '2026-10-01',
      );
    });

    test('跨年：12 月的期仍是当月 1 号', () async {
      expect(
        await add(
          type: TxnType.expense,
          date: '2026-12-31',
          categoryId: catFood,
        ),
        '2026-12-01',
      );
    });
  });

  group('账单日 15', () {
    setUp(() async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
    });

    test('支出按真实日期归期，不抬', () async {
      expect(
        await add(
          type: TxnType.expense,
          date: '2026-10-10',
          categoryId: catFood,
        ),
        '2026-09-15',
        reason: '10-10 在 09-15 那一期里，支出永不抬期',
      );
      expect(
        await add(
          type: TxnType.expense,
          date: '2026-10-20',
          categoryId: catFood,
        ),
        '2026-10-15',
      );
    });

    test('工资 / 奖金 / 提成在账单日前到账 → 抬到下期', () async {
      for (final (name, id) in [
        ('工资', catSalary),
        ('奖金', catBonus),
        ('提成', catCommission),
      ]) {
        expect(
          await add(type: TxnType.income, date: '2026-10-10', categoryId: id),
          '2026-10-15',
          reason: '$name 应进抬期池（D23）',
        );
      }
    });

    test('账单日前一天也抬（date < 账单日，不要求更早）', () async {
      expect(
        await add(
          type: TxnType.income,
          date: '2026-10-14',
          categoryId: catSalary,
        ),
        '2026-10-15',
      );
    });

    test('已经在期内就不动，不会抬两期', () async {
      expect(
        await add(
          type: TxnType.income,
          date: '2026-10-17',
          categoryId: catSalary,
        ),
        '2026-10-15',
      );
    });

    test('上个月的工资不会被再抬一次（两个月工资不挤进一期）', () async {
      expect(
        await add(
          type: TxnType.income,
          date: '2026-09-20',
          categoryId: catSalary,
        ),
        '2026-09-15',
      );
    });

    test('兼职 / 理财 这类不固定的收入不进池', () async {
      expect(
        await add(
          type: TxnType.income,
          date: '2026-10-10',
          categoryId: catParttime,
        ),
        '2026-09-15',
      );
    });
  });

  group('写入路径', () {
    test('改日期会重算归属期', () async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      final id = await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.expense,
          amountCents: 2000,
          date: '2026-10-20',
          categoryId: catFood,
        ),
      );
      final db = await Db.open();

      var row = await db.query(
        'txn',
        columns: ['period_start'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.first['period_start'], '2026-10-15');

      final old = await byId(id);
      await Repo.updateTxn(old, old.copyWith(date: '2026-10-10'));

      row = await db.query(
        'txn',
        columns: ['period_start', 'date'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.first['date'], '2026-10-10', reason: '真实日期要改');
      expect(
        row.first['period_start'],
        '2026-09-15',
        reason: '改了日期但没重算，这笔会停在 10-15 那期',
      );
    });

    test('改分类会重算归属期（支出 → 工资）', () async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      final id = await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.expense,
          amountCents: 800000,
          date: '2026-10-10',
          categoryId: catFood,
        ),
      );
      final db = await Db.open();
      final before = await db.query(
        'txn',
        columns: ['period_start'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(before.first['period_start'], '2026-09-15');

      final old = await byId(id);
      await Repo.updateTxn(
        old,
        Txn(
          id: id,
          ledgerId: ledgerId,
          type: TxnType.income,
          amountCents: 800000,
          date: '2026-10-10',
          categoryId: catSalary,
        ),
      );

      final after = await db.query(
        'txn',
        columns: ['period_start'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(after.first['period_start'], '2026-10-15', reason: '变成工资类收入后就该抬期');
    });

    test('手动关掉抬期：工资留在真实日期那一期', () async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      final id = await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.income,
          amountCents: 800000,
          date: '2026-10-10',
          categoryId: catSalary,
        ),
        liftToNext: false,
      );
      final db = await Db.open();
      final row = await db.query(
        'txn',
        columns: ['period_start'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(
        row.first['period_start'],
        '2026-09-15',
        reason: '用户明确说「不算下期」，就不该被白名单强行抬走',
      );
    });

    test('手动打开抬期：兼职也能算进下一期', () async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      final id = await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.income,
          amountCents: 30000,
          date: '2026-10-10',
          categoryId: catParttime,
        ),
        liftToNext: true,
      );
      final db = await Db.open();
      final row = await db.query(
        'txn',
        columns: ['period_start'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.first['period_start'], '2026-10-15');
    });

    test('手动开关能反推回来（编辑旧记录时面板要知道它开着）', () async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      final id = await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.income,
          amountCents: 50000,
          date: '2026-10-10',
          categoryId: catParttime,
        ),
        liftToNext: true,
      );
      final row = await byId(id);
      expect(row.periodStart, '2026-10-15');
      // 真实日期所在期是 09-15，与落库的 10-15 不同 → 反推为「开着」
      expect(row.periodStart != periodStartOf(row.date, 15), isTrue);
    });

    test('所有记录都有 period_start，没有漏网的 NULL', () async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      for (final (type, cat) in [
        (TxnType.expense, catFood),
        (TxnType.income, catSalary),
        (TxnType.income, catParttime),
      ]) {
        await add(type: type, date: '2026-10-10', categoryId: cat);
      }
      final db = await Db.open();
      final nulls = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM txn WHERE period_start IS NULL',
      );
      expect(nulls.first['c'], 0);
    });
  });

  group('改账单日', () {
    test('rebuildPeriods 重写全部历史', () async {
      // 先在默认账单日下记两笔
      await add(type: TxnType.expense, date: '2026-10-20', categoryId: catFood);
      await add(
        type: TxnType.income,
        date: '2026-10-10',
        categoryId: catSalary,
      );

      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      final changed = await Repo.rebuildPeriods(ledgerId);
      expect(changed, 2, reason: '两笔都要改：一笔换期、一笔抬期');

      final db = await Db.open();
      final rows = await db.query(
        'txn',
        columns: ['type', 'period_start'],
        orderBy: 'id',
      );
      expect(rows[0]['period_start'], '2026-10-15');
      expect(rows[1]['period_start'], '2026-10-15');
    });

    test('账单日改回 1：归属期回到月初', () async {
      await Repo.setSetting(Repo.cycleStartDayKey, '15');
      await add(type: TxnType.expense, date: '2026-10-03', categoryId: catFood);

      await Repo.setSetting(Repo.cycleStartDayKey, '1');
      await Repo.rebuildPeriods(ledgerId);

      final db = await Db.open();
      final rows = await db.query(
        'txn',
        columns: ['period_start'],
        orderBy: 'id',
      );
      expect(rows.first['period_start'], '2026-10-01');
    });

    test('非法值回落到 1', () async {
      await Repo.setSetting(Repo.cycleStartDayKey, 'abc');
      expect(await Repo.cycleStartDay(), 1);
      await Repo.setSetting(Repo.cycleStartDayKey, '99');
      expect(await Repo.cycleStartDay(), 31);
    });
  });

  group('v3 → v4 迁移', () {
    test('加列成功、老数据 period_start 为空、回填后等于月初', () async {
      await Db.close();
      await _makeV3Db();

      final db = await Db.open(); // 触发 onUpgrade

      final cols = await db.rawQuery('PRAGMA table_info(txn)');
      expect(
        cols.any((c) => c['name'] == 'period_start'),
        isTrue,
        reason: 'ALTER TABLE 没执行',
      );

      var rows = await db.query('txn', columns: ['period_start']);
      expect(rows.length, 1, reason: '老数据不能被迁移弄丢');
      expect(rows.first['period_start'], isNull);

      final filled = await Repo.backfillMissingPeriods();
      expect(filled, 1);

      rows = await db.query('txn', columns: ['period_start', 'date']);
      expect(rows.first['date'], '2026-10-10', reason: '真实日期一个字不改');
      expect(
        rows.first['period_start'],
        '2026-10-01',
        reason: '账单日默认 1，归属期 = 月初',
      );
    });

    test('迁移可重复执行（已升级的库再打开一次不抛异常）', () async {
      await Db.close();
      await _makeV3Db();
      await Db.open();
      await Db.close();
      await Db.open(); // 第二次打开不应再走 ALTER
      final cols = await (await Db.open()).rawQuery('PRAGMA table_info(txn)');
      expect(cols.where((c) => c['name'] == 'period_start').length, 1);
    });

    test('回填是幂等的', () async {
      await Db.close();
      await _makeV3Db();
      await Db.open();
      expect(await Repo.backfillMissingPeriods(), 1);
      expect(await Repo.backfillMissingPeriods(), 0, reason: '第二次没有可补的');
    });
  });
}
