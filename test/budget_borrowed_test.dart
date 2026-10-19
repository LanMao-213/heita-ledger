// 借入「计入预算」的口径。
//
// 用户确认过的规则：借入打开「计入预算」时，**本期可用金额加上本金并标注
// 「含借入」，预算额度本身不动**。这条规则以前只存了个 flag、界面没人读，
// 等于没实现 —— 这几条把它钉住。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_budget_borrowed.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<void> _freshDb() async {
  await Db.close();
  Db.fileName = _dbName;
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();
  await Db.open();
}

Future<int> _lend({
  required int ledgerId,
  required int accountId,
  required DebtDirection direction,
  required int cents,
  required String date,
  bool countInBudget = false,
}) => Repo.createDebt(
  Debt(
    id: 0,
    ledgerId: ledgerId,
    direction: direction,
    counterparty: '张三',
    amountCents: cents,
    date: date,
    accountId: accountId,
    countInBudget: countInBudget,
  ),
  Txn(
    id: 0,
    ledgerId: ledgerId,
    type: TxnType.expense,
    amountCents: cents,
    date: date,
    accountId: accountId,
  ),
);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  test('借入计入预算：额度不动，可用额度加本金', () async {
    await _freshDb();
    await Store.i.boot();
    final s = Store.i;
    final acc = s.accounts.first.id;

    await Repo.setBudget(
      ledgerId: s.ledgerId,
      periodStart: s.cycleFrom,
      amountCents: 600000,
    );
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.expense,
        amountCents: 100000,
        date: Fmt.today(),
        accountId: acc,
      ),
    );
    await s.afterTxnChange();
    expect(s.totalBudgetCents, 600000);
    expect(s.borrowedInBudgetCents, 0);
    expect(s.budgetLeftCents, 500000);

    await _lend(
      ledgerId: s.ledgerId,
      accountId: acc,
      direction: DebtDirection.borrowed,
      cents: 300000,
      date: Fmt.today(),
      countInBudget: true,
    );
    await s.afterTxnChange();

    expect(s.borrowedInBudgetCents, 300000);
    expect(s.totalBudgetCents, 600000, reason: '额度是用户设的数，不能被借款改写');
    expect(s.budgetAvailableCents, 900000, reason: '可用 = 额度 + 借入');
    expect(s.budgetLeftCents, 800000, reason: '已花 1000，可用 9000，剩 8000');
    expect(s.overBudget, isFalse);
    // 借入不影响「这个月花了多少」
    expect(s.expenseCents, 100000);
  });

  test('借入没勾「计入预算」：可用额度不动', () async {
    await _freshDb();
    await Store.i.boot();
    final s = Store.i;
    final acc = s.accounts.first.id;
    await Repo.setBudget(
      ledgerId: s.ledgerId,
      periodStart: s.cycleFrom,
      amountCents: 600000,
    );

    await _lend(
      ledgerId: s.ledgerId,
      accountId: acc,
      direction: DebtDirection.borrowed,
      cents: 300000,
      date: Fmt.today(),
    );
    await s.afterTxnChange();

    expect(s.borrowedInBudgetCents, 0);
    expect(s.budgetAvailableCents, 600000);
  });

  test('借出即使传了 true 也不计入（数据层兜住）', () async {
    await _freshDb();
    await Store.i.boot();
    final s = Store.i;
    final acc = s.accounts.first.id;

    await _lend(
      ledgerId: s.ledgerId,
      accountId: acc,
      direction: DebtDirection.lent,
      cents: 500000,
      date: Fmt.today(),
      countInBudget: true,
    );
    await s.afterTxnChange();

    expect(s.borrowedInBudgetCents, 0, reason: '钱出去了，不是可花的钱');
    final d = (await Repo.listDebts(ledgerId: s.ledgerId)).single;
    expect(d.countInBudget, isFalse, reason: '落库时也应被纠正');
  });

  test('上期借的钱不抬本期额度', () async {
    await _freshDb();
    await Store.i.boot();
    final s = Store.i;
    final acc = s.accounts.first.id;
    await Repo.setBudget(
      ledgerId: s.ledgerId,
      periodStart: s.cycleFrom,
      amountCents: 600000,
    );

    // 上期的日期：本期起始日往前 40 天
    final last = DateTime.parse(s.cycleFrom).subtract(const Duration(days: 40));
    await _lend(
      ledgerId: s.ledgerId,
      accountId: acc,
      direction: DebtDirection.borrowed,
      cents: 300000,
      date: Fmt.date(last),
      countInBudget: true,
    );
    await s.afterTxnChange();

    expect(s.borrowedInBudgetCents, 0);
    expect(s.budgetAvailableCents, 600000);
  });
}
