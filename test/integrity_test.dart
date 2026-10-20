// 数据体检的自检。
//
// 为什么单独测这一条：账户余额是**增量**维护的（`Repo._applyBalanceDelta`），
// 漏一次就永久偏离，而且不会报错、界面也看不出来 —— 用户只会觉得
// 「我明明没花这么多」。`Integrity.check()` 是唯一能发现这件事的地方，
// 它自己错了就等于把最后一道保险也拆了。
//
// 特别钉住一条回归：**用户手填的余额不能被当成漂移**。
// 手填改的是 `opening_cents`（基准），不是 `balance_cents`。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/integrity.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_integrity.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  late int ledgerId;
  late int catFood;
  late int accCash;
  final month = Fmt.month(DateTime.now());

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();

    await Db.open();
    ledgerId = await Repo.currentLedgerId();
    catFood = await Repo.insertCategory(
      Category(id: 0, ledgerId: ledgerId, type: TxnType.expense, name: '餐饮'),
    );
    accCash = await Repo.insertAccount(const Account(id: 0, name: '现金'));
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  Future<void> spend(int cents) => Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.expense,
      amountCents: cents,
      date: '$month-10',
      categoryId: catFood,
      accountId: accCash,
    ),
  );

  List<IntegrityKind> kinds(IntegrityReport r) =>
      r.issues.map((i) => i.kind).toList();

  test('刚建好的库是干净的', () async {
    final r = await Integrity.check();
    expect(r.ok, isTrue, reason: r.summary);
    // 建库时会种下 4 个默认账户 + 这里加的 1 个
    expect(r.checkedAccounts, 5);
  });

  test('正常记账后余额仍然对得上（事务化没有改变结果）', () async {
    await spend(2000); // 20.00
    await spend(500); // 5.00

    final r = await Integrity.check();
    expect(r.ok, isTrue, reason: '余额增量与「期初 + 流水合计」必须一致');

    final acc = (await Repo.listAccounts()).firstWhere((a) => a.id == accCash);
    expect(acc.balanceCents, -2500);
    expect(acc.openingCents, 0);
  });

  test('余额被外部改坏 → 体检能发现，重算能修好，且不动期初', () async {
    await spend(2000);

    // 模拟「漏了一次 _applyBalanceDelta」：只有余额变了，没有对应流水
    final db = await Db.open();
    await db.rawUpdate(
      'UPDATE account SET balance_cents = balance_cents + 7777 WHERE id = ?',
      [accCash],
    );

    final before = await Integrity.check();
    expect(before.ok, isFalse);
    expect(kinds(before), contains(IntegrityKind.balanceDrift));
    expect(before.hasFixable, isTrue);

    final fixed = await Integrity.recalcBalances();
    expect(fixed, 1);

    final after = await Integrity.check();
    expect(after.ok, isTrue, reason: '重算之后必须自洽');

    final acc = (await Repo.listAccounts()).firstWhere((a) => a.id == accCash);
    expect(acc.balanceCents, -2000, reason: '余额按流水回到真实值');
    expect(acc.openingCents, 0, reason: '重算不该动期初（那是用户填的基准）');
  });

  test('用户手填余额不算漂移', () async {
    await spend(2000); // 余额 -20.00

    // 用户在账户页把余额改成 100.00（现实里就是「钱包里实际有 100」）
    final acc = (await Repo.listAccounts()).firstWhere((a) => a.id == accCash);
    await Repo.saveAccount(acc, 10000);

    final r = await Integrity.check();
    expect(
      r.ok,
      isTrue,
      reason: '手填改的是 opening，不是 balance —— 不能被报成漂移',
    );

    final now = (await Repo.listAccounts()).firstWhere((a) => a.id == accCash);
    expect(now.balanceCents, 10000);
    expect(now.openingCents, 12000, reason: '100.00 - (-20.00) = 120.00');

    // 手填之后再记一笔，余额继续跟着走
    await spend(500);
    expect(
      (await Integrity.check()).ok,
      isTrue,
      reason: '手填之后继续记账，恒等式仍然成立',
    );
  });

  test('报价里带 % 或 _ 不会被当成通配符（搜索转义）', () async {
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 100,
        date: '$month-11',
        categoryId: catFood,
        accountId: accCash,
        note: '满减 50% 优惠',
      ),
    );
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 200,
        date: '$month-12',
        categoryId: catFood,
        accountId: accCash,
        note: 'a_b 测试',
      ),
    );

    final (percent, _) = await Repo.searchTxns(
      ledgerId: ledgerId,
      keyword: '50%',
    );
    expect(percent.length, 1, reason: '「50%」应该只命中真写了 50% 的那笔');

    final (underscore, _) = await Repo.searchTxns(
      ledgerId: ledgerId,
      keyword: 'a_b',
    );
    expect(underscore.length, 1, reason: '「a_b」不能命中「aab」');
  });

  test('孤儿分类引用能被发现', () async {
    await spend(2000);
    final db = await Db.open();
    // 模拟老版本绕过外键留下的悬空分类 id（category_id 是软关联，没有 FK）
    await db.rawUpdate('UPDATE txn SET category_id = 999999');

    final r = await Integrity.check();
    expect(kinds(r), contains(IntegrityKind.orphanRef));
    expect(r.hasFixable, isFalse, reason: '孤儿引用不能靠重算余额解决');
  });

  test('缺归属期的流水能被发现', () async {
    await spend(2000);
    final db = await Db.open();
    await db.rawUpdate('UPDATE txn SET period_start = NULL');

    final r = await Integrity.check();
    expect(kinds(r), contains(IntegrityKind.missingPeriod));
  });

  test('带余额新建账户不会自造漂移', () async {
    // dev 种子 / Excel 导入都会「建账户时直接给一个初始余额」。
    // 新建账户还没有流水，所以期初必须等于这个余额，否则体检第一条就报错。
    await Repo.insertAccount(
      const Account(id: 0, name: '带余额的卡', balanceCents: 500000),
    );

    final r = await Integrity.check();
    expect(
      r.ok,
      isTrue,
      reason: '建账户时给的余额就是期初，不能算成漂移：${r.summary}',
    );

    final acc = (await Repo.listAccounts()).firstWhere(
      (a) => a.name == '带余额的卡',
    );
    expect(acc.balanceCents, 500000);
    expect(acc.openingCents, 500000);

    // 之后再记账，余额照常增减
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 30000,
        date: '$month-20',
        categoryId: catFood,
        accountId: acc.id,
      ),
    );
    expect((await Integrity.check()).ok, isTrue);
  });

  test('借贷已还超过本金能被发现', () async {    final debtId = await Repo.createDebt(
      Debt(
        id: 0,
        ledgerId: ledgerId,
        direction: DebtDirection.lent, // 借出 100.00
        counterparty: '张三',
        amountCents: 10000,
        accountId: accCash,
        date: '$month-05',
      ),
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 10000,
        date: '$month-05',
        accountId: accCash,
      ),
    );

    // 还款 120.00 —— 比本金还多，正常入口会拦住，这里直接写库模拟历史脏数据
    final db = await Db.open();
    await db.insert('txn', {
      'ledger_id': ledgerId,
      'type': 'income',
      'amount_cents': 12000,
      'date': '$month-06',
      'period_start': '$month-06',
      'account_id': accCash,
      'debt_id': debtId,
      'note': '',
      'created_at': '',
      'updated_at': '',
    });

    final r = await Integrity.check();
    expect(kinds(r), contains(IntegrityKind.debtOverRepaid));
  });

  test('v7 老库升到 v8：余额一分不动，期初被正确回填', () async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();

    // 造一个 v7 的库：account 没有 opening_cents，余额是用户手填过的 880.00，
    // 另有 1 笔 120.00 的支出。升级后必须满足 880 = 期初 + (−120)。
    final old = await databaseFactory.openDatabase(
      await _dbPath(),
      options: OpenDatabaseOptions(
        version: 7,
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
            CREATE TABLE txn (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ledger_id INTEGER NOT NULL, type TEXT NOT NULL,
              amount_cents INTEGER NOT NULL, category_id INTEGER,
              account_id INTEGER, to_account_id INTEGER,
              date TEXT NOT NULL, period_start TEXT,
              note TEXT NOT NULL DEFAULT '',
              place_from TEXT, place_to TEXT, person TEXT, subject TEXT,
              debt_id INTEGER, template_id INTEGER, recurring_id INTEGER,
              created_at TEXT NOT NULL DEFAULT '',
              updated_at TEXT NOT NULL DEFAULT '')''');
          await db.execute('''
            CREATE TABLE category (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ledger_id INTEGER NOT NULL, type TEXT NOT NULL,
              name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT 'more',
              parent_id INTEGER, sort_order INTEGER NOT NULL DEFAULT 0,
              archived INTEGER NOT NULL DEFAULT 0)''');
          await db.execute('''
            CREATE TABLE debt (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ledger_id INTEGER NOT NULL, direction TEXT NOT NULL,
              counterparty TEXT NOT NULL, amount_cents INTEGER NOT NULL,
              account_id INTEGER, date TEXT NOT NULL, due_date TEXT,
              count_in_budget INTEGER NOT NULL DEFAULT 0,
              closed_at TEXT, note TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL DEFAULT '')''');

          await db.insert('ledger', {'name': '老账本'});
          await db.insert('account', {'name': '现金', 'balance_cents': 88000});
          await db.insert('txn', {
            'ledger_id': 1,
            'type': 'expense',
            'amount_cents': 12000,
            'account_id': 1,
            'date': '2026-10-10',
            'period_start': '2026-10-10',
          });
        },
      ),
    );
    await old.close();

    final db = await Db.open(); // 触发 v7 → v8
    final rows = await db.query('account', where: 'id = 1');
    final acc = Account.fromMap(rows.first);

    expect(acc.balanceCents, 88000, reason: '升级不能改用户看到的余额');
    expect(
      acc.openingCents,
      100000,
      reason: '880.00 − (−120.00) = 1000.00，这样 余额 = 期初 + 流水 立刻成立',
    );

    final r = await Integrity.check();
    expect(r.ok, isTrue, reason: '升级完第一次体检就该是干净的：${r.summary}');
  });
}
