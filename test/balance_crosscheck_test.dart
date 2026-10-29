// 余额的**第三方交叉校验**。
//
// ## 为什么这条测试非有不可
//
// `1.6.0` 把余额公式收敛成了 `sql_fragments.dart` 的 `kAccountFlowSql`，让「对账
// 查询 / 体检的期望值 / 删账本后的重算」三处共用同一份 —— 好处是公式不会再各自
// 漂，代价是**这份唯一的公式写错了，没有任何一条测试会红**（自己验自己恒真）。
//
// 结构上还剩一条独立实现：账户余额平时是由 Dart 增量维护的（`_applyBalanceDelta`
// 按类型逐笔加减），而体检是 SQL 重算。两者对不上就报「余额漂移」。所以公式错
// 的表现是「存量余额与重算值分歧」，理论上能被抓到。
//
// 但这条链有个前提：**增量维护本身是对的**。若某天有人把增量维护也改成调
// `kAccountFlowSql`，交叉核对就消失了，体检会变成「拿公式验公式」。
//
// 因此这里补上第三条腿：一个**结构上完全不同**的实现（三段独立扫描 + UNION ALL，
// 而不是单次扫描 + OR + CASE），手工算出期望值，与存库余额、体检重算值三方对齐。
// 任何两份不一致都会在这里红。
//
// 这也是 QA 在 1.6.0 验收里建议的（当时记为 1.6.x），本轮补上。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/integrity.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_balance_crosscheck.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 独立实现：不用 `kAccountFlowSql`，改用三段互不重叠的扫描再求和。
///
/// 三段分别是「本账户名下的收入/支出」「本账户转出的」「本账户转入的」——
/// 与生产代码那种「一次扫描 + WHERE ... OR ... + 单个 CASE」是两种写法，
/// 符号写反、漏掉 `to_account_id` 那一端，都会在这里显形。
///
/// 表达式里刻意重复 `type` 条件：生产代码靠 `ELSE 0` 兜底，这里靠 `WHERE` 过滤，
/// 两条路都必须得到同一个数。
Future<int> _independentFlowCents(int accountId) async {
  final db = await Db.open();
  final rows = await db.rawQuery('''
    SELECT COALESCE(SUM(d), 0) AS s FROM (
      SELECT CASE t.type
               WHEN 'income'  THEN  t.amount_cents
               WHEN 'expense' THEN -t.amount_cents
               ELSE 0
             END AS d
        FROM txn t
       WHERE t.account_id = ? AND t.type IN ('income', 'expense')
      UNION ALL
      SELECT -t.amount_cents AS d
        FROM txn t
       WHERE t.type = 'transfer' AND t.account_id = ?
      UNION ALL
      SELECT t.amount_cents AS d
        FROM txn t
       WHERE t.type = 'transfer' AND t.to_account_id = ?
    )''', [accountId, accountId, accountId]);
  return (rows.first['s'] as int?) ?? 0;
}

Future<int> _storedBalance(int accountId) async {
  final accounts = await Repo.listAccounts();
  return accounts.firstWhere((a) => a.id == accountId).balanceCents;
}

Future<int> _openingOf(int accountId) async {
  final accounts = await Repo.listAccounts();
  return accounts.firstWhere((a) => a.id == accountId).openingCents;
}

/// 让 A、B 之间发生全部四种资金流向，返回 (A, B) 的 id。
///
/// 覆盖矩阵：A 收 / A 支 / A 转出 / A 转入 / B 只收 —— 「只出现在
/// `to_account_id` 上的账户」正是最容易在公式里被漏掉的那一格。
Future<(int, int)> _seedFourFlows() async {
  await Store.i.boot();
  final a = await Repo.insertAccount(
    const Account(id: 0, name: 'A 钱包', balanceCents: 100000),
  );
  final b = await Repo.insertAccount(
    const Account(id: 0, name: 'B 银行卡', balanceCents: 0),
  );
  final ledger = Store.i.ledgerId;
  final cats = await Repo.listCategories(ledger);

  Future<void> add(TxnType type, int cents, {int? to}) => Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledger,
      type: type,
      amountCents: cents,
      date: '2026-10-05',
      categoryId: type == TxnType.transfer || cats.isEmpty ? null : cats.first.id,
      accountId: a,
      toAccountId: to,
    ),
  );

  /// 转账要能反过来（B → A），否则「A 只出现在 to_account_id 上」这一格
  /// 永远测不到 —— 而它正是公式里最容易漏的一端。
  Future<void> move(int from, int? to, int cents) => Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledger,
      type: TxnType.transfer,
      amountCents: cents,
      date: '2026-10-06',
      accountId: from,
      toAccountId: to,
    ),
  );

  await add(TxnType.income, 20000); // A +200
  await add(TxnType.expense, 30000); // A −300
  await move(a, b, 15000); // A −150, B +150
  await move(b, a, 5000); // B −50,  A +50
  return (a, b);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  test('收入/支出/转账两端：存库余额 == 独立实现 == 期初 + 流水', () async {
    final (a, b) = await _seedFourFlows();

    // 手算：A = 1000 + 200 − 300 − 150 + 50 = 800；B = 0 + 150 − 50 = 100
    expect(await _independentFlowCents(a), 20000 - 30000 - 15000 + 5000);
    expect(await _independentFlowCents(b), 15000 - 5000);

    expect(
      await _storedBalance(a),
      100000 + 20000 - 30000 - 15000 + 5000,
      reason: 'A 的存库余额与独立算出的 800.00 不一致 —— '
          '要么增量维护漏了某一类，要么符号写反了',
    );
    expect(
      await _storedBalance(b),
      0 + 15000 - 5000,
      reason: 'B 只在 `to_account_id` 上出现过，这一格最容易在公式里被漏掉',
    );

    // 恒等式：余额 = 期初 + 流水合计（两个账户都要成立）
    expect(
      await _storedBalance(a),
      await _openingOf(a) + await _independentFlowCents(a),
    );
    expect(
      await _storedBalance(b),
      await _openingOf(b) + await _independentFlowCents(b),
    );

    final report = await Integrity.check();
    expect(report.ok, isTrue, reason: '三方都对齐时体检必须干净');
    expect(report.checkedAccounts, greaterThanOrEqualTo(2));
  });

  test('故意改坏余额：体检要红，且「重算」给出的值必须等于独立实现', () async {
    final (a, _) = await _seedFourFlows();
    final good = await _storedBalance(a);

    // 绕开所有重算路径，直接改库 —— 等价于「增量维护算错过一次」
    final db = await Db.open();
    await db.rawUpdate(
      'UPDATE account SET balance_cents = ? WHERE id = ?',
      [good + 1, a],
    );

    final report = await Integrity.check();
    expect(report.ok, isFalse, reason: '差 1 分也必须能被体检抓到');
    expect(
      report.issues.any((i) => i.kind == IntegrityKind.balanceDrift),
      isTrue,
      reason: '应当报「账户余额与流水不一致」这一类',
    );

    // 决定性一步：`recalcBalances` 用的是 `kAccountFlowSql`，
    // 修出来的值必须和上面的独立实现完全一致 —— 两份公式真正对上。
    await Integrity.recalcBalances();
    expect(
      await _storedBalance(a),
      await _openingOf(a) + await _independentFlowCents(a),
      reason: '重算（kAccountFlowSql）与独立实现给出了不同的数，'
          '说明至少有一份公式是错的',
    );
    expect((await Integrity.check()).ok, isTrue);
  });

  test('删掉一笔转账后，两端都回到一致（增量的反向冲回与公式同源）', () async {
    final (a, b) = await _seedFourFlows();
    final txns = await Repo.rangeListTxns(
      ledgerId: Store.i.ledgerId,
      from: '2026-10-01',
      to: '2026-10-31',
    );
    final transfer = txns.firstWhere((t) => t.type == TxnType.transfer);
    await Repo.deleteTxn(transfer);

    expect(await _storedBalance(a), await _openingOf(a) + await _independentFlowCents(a));
    expect(await _storedBalance(b), await _openingOf(b) + await _independentFlowCents(b));
    expect((await Integrity.check()).ok, isTrue);
  });
}
