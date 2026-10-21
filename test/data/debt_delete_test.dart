import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 删除往来 / 记还款 / 标记结清：余额恒等式（I1）与「不动流水」的边界。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<int> makeDebt({int amount = 50000, LocalDate? due}) async {
    final int ledger = await currentLedger();
    return Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: amount,
        accountId: await defaultAccountId(),
        date: const LocalDate(2026, 10, 5),
        dueDate: due,
        createdAt: DateTime(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );
  }

  test('⑧ 删往来：debt 没了、挂它的流水全删、余额逐条反向回滚', () async {
    final int acc = await defaultAccountId();
    final int opening = await balanceOf(acc);
    final int debtId = await makeDebt();
    final Debt debt = (await Repo.debt.byId(debtId))!;

    // 借出 500 → 余额 -500；再收回 200 → 余额 +200
    await Repo.repayDebt(
      target: debt,
      amountCents: 20000,
      cycleStartDay: 1,
      date: const LocalDate(2026, 10, 8),
    );
    expect(await balanceOf(acc), opening - 50000 + 20000);
    expect((await Repo.txn.byDebt(debtId)).length, 2);

    await Repo.deleteDebt(debtId);

    expect(await Repo.debt.byId(debtId), isNull);
    expect(await Repo.txn.byDebt(debtId), isEmpty);
    expect(
      await balanceOf(acc),
      opening,
      reason: '本金与还款都要反向回滚，余额回到借钱之前',
    );
  });

  test('⑧ 删往来之后 I1（balance == opening + Σ流水）仍成立', () async {
    final int acc = await defaultAccountId();
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 3850,
        date: const LocalDate(2026, 10, 6),
        periodStart: const LocalDate(2026, 10, 1),
        accountId: acc,
      ),
      cycleStartDay: 1,
    );
    final int debtId = await makeDebt();
    await Repo.deleteDebt(debtId);

    expect(
      await Repo.stats.balanceMatches(acc),
      isTrue,
      reason: '余额恒等式是硬不变量：删完也得对得上',
    );
  });

  test('⑥ 标记结清只改 closed_at，不动流水与余额', () async {
    final int acc = await defaultAccountId();
    final int debtId = await makeDebt();
    final int txnsBefore = (await Repo.txn.byDebt(debtId)).length;
    final int balanceBefore = await balanceOf(acc);

    await Repo.debt.setClosed(debtId, true);

    final Debt closed = (await Repo.debt.byId(debtId))!;
    expect(closed.closedAt, isNotNull);
    expect((await Repo.txn.byDebt(debtId)).length, txnsBefore);
    expect(await balanceOf(acc), balanceBefore);

    // 撤销结清也一样
    await Repo.debt.setClosed(debtId, false);
    expect((await Repo.debt.byId(debtId))!.closedAt, isNull);
    expect((await Repo.txn.byDebt(debtId)).length, txnsBefore);
  });

  test('⑦ 还款金额 > 剩余 → ArgumentError（数据层第二道拦截）', () async {
    final int debtId = await makeDebt(amount: 10000);
    final Debt debt = (await Repo.debt.byId(debtId))!;

    await expectLater(
      Repo.repayDebt(
        target: debt,
        amountCents: 10001,
        cycleStartDay: 1,
      ),
      throwsA(isA<ArgumentError>()),
    );
    // 金额 <= 0 也拦
    await expectLater(
      Repo.repayDebt(target: debt, amountCents: 0, cycleStartDay: 1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('⑦ 还满 → 同事务写 closed_at，且已还 == 本金', () async {
    final int debtId = await makeDebt(amount: 30000);
    final Debt debt = (await Repo.debt.byId(debtId))!;

    final Debt after = await Repo.repayDebt(
      target: debt,
      amountCents: 30000,
      cycleStartDay: 1,
      date: const LocalDate(2026, 10, 20),
    );

    expect(after.closedAt, isNotNull);
    final RepaidIndex index = RepaidIndex.fromTxns(
      await Repo.txn.byDebt(debtId),
    );
    expect(index.repaidForId(debtId, receivable: true), 30000);
    expect(after.remainingCents(index), 0);

    // 已结清再还 → 拒绝
    await expectLater(
      Repo.repayDebt(target: after, amountCents: 100, cycleStartDay: 1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('删往来时「已结清」的那笔也一起删干净（不因为结清就留下孤儿流水）', () async {
    final int acc = await defaultAccountId();
    final int opening = await balanceOf(acc);
    final int debtId = await makeDebt(amount: 20000);
    await Repo.debt.setClosed(debtId, true);

    await Repo.deleteDebt(debtId);

    expect(await Repo.debt.byId(debtId), isNull);
    expect(await Repo.txn.byDebt(debtId), isEmpty);
    expect(await balanceOf(acc), opening);
  });
}
