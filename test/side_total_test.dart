// 负数按「交叉归集」统计的口径自检。
//
// 规则（产品定）：支出里记的负数算进**收入**，收入里记的负数算进**支出**。
// 语义是「这笔钱的方向反了」，而不是这一侧变少了。
//
// 最容易错的地方：合计改了、饼图没改，于是饼图分项之和 ≠ 合计。这里一起钉住。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/data/repo_stats.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_side_total.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  late int ledgerId;
  late int catFood;
  late int catSalary;
  late int accA;
  late int accB;
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
    catSalary = await Repo.insertCategory(
      Category(id: 0, ledgerId: ledgerId, type: TxnType.income, name: '工资'),
    );
    accA = await Repo.insertAccount(const Account(id: 0, name: '现金'));
    accB = await Repo.insertAccount(const Account(id: 0, name: '银行卡'));
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  Future<void> add(TxnType type, int cents, {int? cat, int? toAcc}) =>
      Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: type,
          amountCents: cents,
          date: '$month-10',
          categoryId: cat,
          accountId: accA,
          toAccountId: toAcc,
        ),
      ).then((_) {});

  /// 支出 100、支出 −20、收入 1000、收入 −30、一笔转账
  Future<void> seed() async {
    await add(TxnType.expense, 10000, cat: catFood);
    await add(TxnType.expense, -2000, cat: catFood);
    await add(TxnType.income, 100000, cat: catSalary);
    await add(TxnType.income, -3000, cat: catSalary);
    await add(TxnType.transfer, 50000, toAcc: accB);
  }

  test('月合计：支出负数进收入，收入负数进支出，转账不计', () async {
    await seed();
    final (exp, inc, cnt) = await RepoStats.monthTotals(ledgerId, month);
    // 支出 = 10000（支出正数）+ 3000（收入负数）
    expect(exp, 13000);
    // 收入 = 100000（收入正数）+ 2000（支出负数）
    expect(inc, 102000);
    expect(cnt, 5); // 笔数含转账
  });

  test('饼图分项按同口径交叉，且分项之和等于合计', () async {
    await seed();
    final (exp, inc, _) = await RepoStats.monthTotals(ledgerId, month);

    final expStats = await RepoStats.categoryStats(
      ledgerId: ledgerId,
      month: month,
      type: TxnType.expense,
    );
    final incStats = await RepoStats.categoryStats(
      ledgerId: ledgerId,
      month: month,
      type: TxnType.income,
    );

    // 支出饼：餐饮 10000 + 工资 3000（收入负数落进来）
    expect(expStats.length, 2);
    expect(expStats.map((e) => e.name), containsAll(['餐饮', '工资']));
    expect(expStats.fold<int>(0, (a, e) => a + e.totalCents), exp);

    // 收入饼：工资 100000 + 餐饮 2000（支出负数落进来）
    expect(incStats.length, 2);
    expect(incStats.map((e) => e.name), containsAll(['工资', '餐饮']));
    expect(incStats.fold<int>(0, (a, e) => a + e.totalCents), inc);
  });

  test('内存侧的 sumBySide 与 SQL 同口径', () async {
    await seed();
    final txns = await Repo.listTxns(ledgerId: ledgerId, month: month);
    final (exp, inc, _) = await RepoStats.monthTotals(ledgerId, month);
    expect(sumBySide(txns, TxnType.expense), exp);
    expect(sumBySide(txns, TxnType.income), inc);
    expect(sumBySide(txns, TxnType.transfer), 0);
  });

  test('全是正数时口径与过去一致', () async {
    await add(TxnType.expense, 10000, cat: catFood);
    await add(TxnType.income, 50000, cat: catSalary);
    final (exp, inc, _) = await RepoStats.monthTotals(ledgerId, month);
    expect(exp, 10000);
    expect(inc, 50000);
  });
}
