import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 往来 repo：本金流水 + 余额 + 超额拦截 + 自动结清 + 删除回滚。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<int> lend(int amount, {int? accountId, String who = '张三'}) async {
    final int ledger = await currentLedger();
    final int acc = accountId ?? await defaultAccountId();
    return Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.out,
        counterparty: who,
        amountCents: amount,
        accountId: acc,
        date: const LocalDate(2026, 10, 1),
        dueDate: const LocalDate(2026, 11, 30),
        createdAt: DateTime(2026, 10, 1),
      ),
      cycleStartDay: 1,
    );
  }

  test('记借出：debt 行 + 本金流水（expense + debt_id）+ 余额三写', () async {
    final int acc = await defaultAccountId();
    final int id = await lend(50000, accountId: acc);

    final Debt? d = await Repo.debt.byId(id);
    expect(d?.direction, DebtDirection.out);
    expect(d?.countInBudget, isFalse, reason: '借出强制不计入预算');
    expect(d?.isClosed, isFalse);

    final List<Txn> rows = await Repo.txn.byDebt(id);
    expect(rows.length, 1);
    expect(rows.single.type, TxnType.expense);
    expect(rows.single.amountCents, 50000);
    expect(rows.single.periodStart, const LocalDate(2026, 10, 1));

    expect(await balanceOf(acc), -50000);
  });

  test('记借入：本金是 income，计入预算的标记保留', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final int id = await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.in_,
        counterparty: '李四',
        amountCents: 20000,
        accountId: acc,
        date: const LocalDate(2026, 10, 2),
        countInBudget: true,
        createdAt: DateTime(2026, 10, 2),
      ),
      cycleStartDay: 1,
    );

    expect((await Repo.debt.byId(id))?.countInBudget, isTrue);
    final List<Txn> rows = await Repo.txn.byDebt(id);
    expect(rows.single.type, TxnType.income);
    expect(await balanceOf(acc), 20000);
  });

  test('还款超过剩余 → ArgumentError，且一行都不写', () async {
    final int acc = await defaultAccountId();
    final int id = await lend(10000, accountId: acc);
    final Debt d = (await Repo.debt.byId(id))!;

    await expectLater(
      Repo.repayDebt(target: d, amountCents: 10001, cycleStartDay: 1),
      throwsArgumentError,
    );
    expect(await Repo.txn.byDebt(id), hasLength(1), reason: '失败不许留半截流水');
    expect(await balanceOf(acc), -10000);
  });

  test('还满 → 同事务写 closed_at，余额回到 0', () async {
    final int acc = await defaultAccountId();
    final int id = await lend(10000, accountId: acc);

    final Debt after = await Repo.repayDebt(
      target: (await Repo.debt.byId(id))!,
      amountCents: 10000,
      cycleStartDay: 1,
      date: const LocalDate(2026, 10, 20),
    );

    expect(after.isClosed, isTrue);
    expect(after.remainingCents(RepaidIndex.empty), 0);
    expect(await balanceOf(acc), 0);
  });

  test('多还的部分显示为 0，不是负数（remainingCents clamp）', () async {
    final int id = await lend(10000);
    final RepaidIndex index = RepaidIndex.fromTxns(<Txn>[
      Txn(
        type: TxnType.income,
        amountCents: 11000,
        date: const LocalDate(2026, 10, 5),
        debtId: id,
        createdAt: DateTime(2026, 10, 5),
      ),
    ]);
    final Debt d = (await Repo.debt.byId(id))!;
    expect(d.remainingCents(index), 0);
  });

  test('删往来：回滚每笔流水的余额影响 → 删流水 → 删 debt，单事务', () async {
    final int acc = await defaultAccountId();
    final int id = await lend(50000, accountId: acc);
    await Repo.repayDebt(
      target: (await Repo.debt.byId(id))!,
      amountCents: 20000,
      cycleStartDay: 1,
    );
    expect(await balanceOf(acc), -30000);

    await Repo.deleteDebt(id);

    expect(await Repo.debt.byId(id), isNull);
    expect(await Repo.txn.byDebt(id), isEmpty);
    expect(await balanceOf(acc), 0, reason: '删往来要把钱「还」回账户');
    expect(await Repo.stats.balanceMatches(acc), isTrue);
  });

  test('repaidIndex 一条 GROUP BY 查回全部；totals 给出应收应付', () async {
    final int ledger = await currentLedger();
    final int out = await lend(50000);
    final int acc = await defaultAccountId();
    final int inDebt = await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.in_,
        counterparty: '李四',
        amountCents: 20000,
        accountId: acc,
        date: const LocalDate(2026, 10, 3),
        createdAt: DateTime(2026, 10, 3),
      ),
      cycleStartDay: 1,
    );

    await Repo.repayDebt(
      target: (await Repo.debt.byId(out))!,
      amountCents: 20000,
      cycleStartDay: 1,
    );

    final RepaidIndex index = await Repo.debt.repaidIndex(ledger);
    expect(index.repaidForId(out, receivable: true), 20000);
    expect(index.repaidForId(inDebt, receivable: false), 0);

    final ({int receivable, int payable}) totals = await Repo.debt.totals(ledger);
    expect(totals.receivable, 30000);
    expect(totals.payable, 20000);
  });

  test('手动结清只动 closed_at，不动流水与余额', () async {
    final int acc = await defaultAccountId();
    final int id = await lend(10000, accountId: acc);
    final int txnsBefore = (await Repo.txn.byDebt(id)).length;

    await Repo.debt.setClosed(id, true);
    expect((await Repo.debt.byId(id))?.isClosed, isTrue);
    expect((await Repo.txn.byDebt(id)).length, txnsBefore);
    expect(await balanceOf(acc), -10000);

    await Repo.debt.setClosed(id, false);
    expect((await Repo.debt.byId(id))?.isClosed, isFalse);
  });

  test('逾期天数从 due_date 算起', () async {
    final int id = await lend(10000);
    final Debt d = (await Repo.debt.byId(id))!;
    expect(d.overdueDays(today: const LocalDate(2026, 11, 30)), isNull);
    expect(d.overdueDays(today: const LocalDate(2026, 12, 10)), 10);
  });
}
