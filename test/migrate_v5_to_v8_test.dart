// v5 → v8 四次迁移的完整链路自检。
//
// 为什么单独写这一条（1.4.5）：真机上那台装着 1.1.4 的手机，库里是 **v5**。
// 装 1.4.5 等于一次性跑 v5→v6→v7→v8 三次迁移，而在此之前每个版本只有
// 自己那一节的单测片段 —— 从没有人把四次串起来在"有数据的库"上跑过一遍。
//
// 迁移一旦出错不可逆（`onDowngrade` 会拦住装回旧包），所以这段必须先在本地钉死：
//   · 流水一行不多一行不少，金额合计不变
//   · 账户余额一分不动，`opening_cents` 回填后恒等式成立
//   · 老分类靠「原地改名 / 降级」落位，**交易的 category_id 不变**
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/integrity.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_migrate_v5.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 造一个 v5 的库：分类还是一层平铺（交通 / 通讯 / 餐饮 / 工资 / 提成），
/// `txn` 已有 `period_start` 但没有 4 个详情列和 `debt_id`，
/// `account` 没有 `opening_cents`，`budget` 已按 `period_start` 存。
Future<void> _makeV5Db() async {
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();

  final db = await databaseFactory.openDatabase(
    await _dbPath(),
    options: OpenDatabaseOptions(
      version: 5,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE ledger (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT 'book',
            sort_order INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT '')''');
        await db.execute('''
          CREATE TABLE account (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'cash',
            balance_cents INTEGER NOT NULL DEFAULT 0,
            include_in_total INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('''
          CREATE TABLE category (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id INTEGER NOT NULL, type TEXT NOT NULL,
            name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT 'more',
            parent_id INTEGER, sort_order INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('''
          CREATE TABLE txn (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id INTEGER NOT NULL, type TEXT NOT NULL,
            amount_cents INTEGER NOT NULL, category_id INTEGER,
            account_id INTEGER, to_account_id INTEGER,
            date TEXT NOT NULL, period_start TEXT,
            note TEXT NOT NULL DEFAULT '',
            template_id INTEGER, recurring_id INTEGER,
            created_at TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL DEFAULT '')''');
        await db.execute('''
          CREATE TABLE budget (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id INTEGER NOT NULL, period_start TEXT NOT NULL,
            category_id INTEGER, amount_cents INTEGER NOT NULL DEFAULT 0,
            UNIQUE (ledger_id, period_start, category_id))''');
        await db.execute('''
          CREATE TABLE saving_goal (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT 'target',
            target_cents INTEGER NOT NULL DEFAULT 0,
            saved_cents INTEGER NOT NULL DEFAULT 0,
            due_month TEXT, sort_order INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('''
          CREATE TABLE recurring (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id INTEGER NOT NULL, type TEXT NOT NULL,
            amount_cents INTEGER NOT NULL, category_id INTEGER,
            account_id INTEGER, note TEXT NOT NULL DEFAULT '',
            freq TEXT NOT NULL DEFAULT 'monthly',
            interval INTEGER NOT NULL DEFAULT 1,
            next_run_date TEXT NOT NULL, end_date TEXT,
            enabled INTEGER NOT NULL DEFAULT 1)''');
        await db.execute('''
          CREATE TABLE txn_template (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id INTEGER NOT NULL, name TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT 'tpl', type TEXT NOT NULL,
            amount_cents INTEGER NOT NULL DEFAULT 0,
            category_id INTEGER, account_id INTEGER,
            note TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            use_count INTEGER NOT NULL DEFAULT 0,
            last_used_at TEXT)''');
        await db.execute('''
          CREATE TABLE setting (k TEXT PRIMARY KEY, v TEXT NOT NULL)''');

        await db.insert('ledger', {'name': '日常账本'});
        await db.insert('account', {
          'name': '现金',
          'balance_cents': 50000,
          'sort_order': 0,
        });
        await db.insert('account', {
          'name': '支付宝',
          'balance_cents': 123456,
          'sort_order': 1,
        });

        // 老的一套一层分类（v5 之前就这么平铺）
        const cats = <(String, String)>[
          ('交通', 'transport'),
          ('通讯', 'comm'),
          ('餐饮', 'food'),
          ('工资', 'salary'),
          ('提成', 'bonus'),
        ];
        for (var i = 0; i < cats.length; i++) {
          final (name, icon) = cats[i];
          await db.insert('category', {
            'ledger_id': 1,
            'type': (name == '工资' || name == '提成') ? 'income' : 'expense',
            'name': name,
            'icon': icon,
            'parent_id': null,
            'sort_order': i,
            'archived': 0,
          });
        }

        // 三笔真实流水：交通 200.00、通讯 50.00、工资 3000.00
        await db.insert('txn', {
          'ledger_id': 1,
          'type': 'expense',
          'amount_cents': 20000,
          'category_id': 1, // 交通
          'account_id': 1, // 现金
          'date': '2026-10-05',
          'period_start': '2026-10-05',
        });
        await db.insert('txn', {
          'ledger_id': 1,
          'type': 'expense',
          'amount_cents': 5000,
          'category_id': 2, // 通讯
          'account_id': 2, // 支付宝
          'date': '2026-10-06',
          'period_start': '2026-10-06',
        });
        await db.insert('txn', {
          'ledger_id': 1,
          'type': 'income',
          'amount_cents': 300000,
          'category_id': 4, // 工资
          'account_id': 1, // 现金
          'date': '2026-10-01',
          'period_start': '2026-10-01',
        });

        await db.insert('budget', {
          'ledger_id': 1,
          'period_start': '2026-10-01',
          'category_id': null,
          'amount_cents': 600000,
        });

        for (final (k, v) in [
          ('current_ledger_id', '1'),
          ('app_name', '黑塔消费日记'),
          ('schema_ready', '1'),
        ]) {
          await db.insert('setting', {'k': k, 'v': v});
        }
      },
    ),
  );
  await db.close();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  test('v5 升到 v8：流水不变、余额不变、期初回填正确、体检干净', () async {
    await _makeV5Db();

    // 触发 v5 → v8（Db._version 当前为 8）
    final db = await Db.open();

    // 1. 流水：一行不多、一行不少，金额合计不变
    final txns = await db.query('txn', orderBy: 'id');
    expect(txns.length, 3, reason: '迁移不能增删任何一笔交易');
    final expense = txns
        .where((t) => t['type'] == 'expense')
        .fold<int>(0, (a, t) => a + (t['amount_cents'] as int));
    final income = txns
        .where((t) => t['type'] == 'income')
        .fold<int>(0, (a, t) => a + (t['amount_cents'] as int));
    expect(expense, 25000);
    expect(income, 300000);

    // 2. 账户余额一分不动，期初按「余额 − 流水」回填
    final accounts = await db.query('account', orderBy: 'id');
    final cash = Account.fromMap(accounts[0]);
    final alipay = Account.fromMap(accounts[1]);
    expect(cash.balanceCents, 50000);
    expect(alipay.balanceCents, 123456);
    // 现金：-20000 + 300000 = 280000 → 期初 = 50000 - 280000
    expect(cash.openingCents, 50000 - 280000);
    // 支付宝：-5000 → 期初 = 123456 + 5000
    expect(alipay.openingCents, 123456 + 5000);

    // 3. 分类：老 id 原地复用，交易一行都没动
    final transportTxn = txns.firstWhere((t) => t['amount_cents'] == 20000);
    expect(transportTxn['category_id'], 1, reason: '交通那笔的 category_id 不该变');
    final cat1 = await db.query('category', where: 'id = 1');
    expect(cat1.first['name'], '出行', reason: '「交通」原地改名为「出行」');
    expect(cat1.first['parent_id'], isNull, reason: '出行是一级分类');

    // 通讯 → 降级成「居家 / 话费网费」，但 id 还是 2
    final cat2 = await db.query('category', where: 'id = 2');
    expect(cat2.first['name'], '话费网费');
    expect(cat2.first['parent_id'], isNotNull, reason: '降级后有父级');
    final parent2 = await db.query(
      'category',
      where: 'id = ?',
      whereArgs: [cat2.first['parent_id']],
    );
    expect(parent2.first['name'], '居家');

    // 提成 → 奖金 的子分类（收入侧）
    final cat5 = await db.query('category', where: 'id = 5');
    expect(cat5.first['name'], '提成');
    expect(cat5.first['parent_id'], isNotNull);

    // 新增的两级分类齐备
    final topExpense = await db.query(
      'category',
      where: "type = 'expense' AND parent_id IS NULL AND archived = 0",
    );
    expect(topExpense.length, greaterThanOrEqualTo(9), reason: '支出 9 个一级分类');

    // 4. 预算：期与金额都不变
    final budgets = await db.query('budget');
    expect(budgets.length, 1);
    expect(budgets.first['period_start'], '2026-10-01');
    expect(budgets.first['amount_cents'], 600000);

    // 5. 迁移完第一次体检就该是干净的
    final report = await Integrity.check();
    expect(report.ok, isTrue, reason: report.summary);

    // 6. 升级之后照常记账，恒等式继续成立
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: 1,
        type: TxnType.expense,
        amountCents: 3000,
        date: '2026-10-07',
        categoryId: 1, // 出行
        accountId: 1,
      ),
    );
    final after = Account.fromMap(
      (await db.query('account', where: 'id = 1')).first,
    );
    expect(after.balanceCents, 50000 - 3000);
    expect((await Integrity.check()).ok, isTrue);
  });

  test('v5 的旧备份恢复到 v8 库：认一次基准之后就自洽', () async {
    await _makeV5Db();
    await Db.open();

    // 老备份里没有 opening_cents（v7 及以前），恢复时那一列会是 NULL/缺失。
    // 这里按真实路径走：dump → 抹掉这一列 → replaceTables → 认基准。
    final tables = await Repo.dumpTables();
    final restored = tables.map(
      (k, rows) => MapEntry(
        k,
        rows.map((r) {
          final copy = Map<String, Object?>.from(r);
          if (k == 'account') copy.remove('opening_cents');
          return copy;
        }).toList(),
      ),
    );

    await Repo.replaceTables(restored);
    // 备份恢复不会走 onUpgrade，所以基准要显式认一次（BackupService.restore 里同款）
    await Integrity.adoptCurrentBalances();

    final report = await Integrity.check();
    expect(
      report.ok,
      isTrue,
      reason: '恢复老备份后必须自洽，否则第一次体检会报一堆假的余额不一致：'
          '${report.summary}',
    );

    final db = await Db.open();
    final accounts = await db.query('account', orderBy: 'id');
    expect(Account.fromMap(accounts[0]).balanceCents, 50000);
    expect(Account.fromMap(accounts[1]).balanceCents, 123456);
  });
}
