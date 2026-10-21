import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/services/summary_service.dart';

/// 派生口径的唯一来源：可用额度 / 净资产 / 应收应付。
///
/// 这一组挡的是「预算条说还剩 200，计划页说超了 50」那种自相矛盾。
void main() {
  final DateTime now = DateTime(2026, 10, 16);

  Account acc(String name, int balance, {int opening = 0, bool include = true}) =>
      Account(
        name: name,
        openingCents: opening,
        balanceCents: balance,
        includeInTotal: include,
      );

  Debt debt(DebtDirection dir, int amount, {int id = 1}) => Debt(
    id: id,
    direction: dir,
    counterparty: '张三',
    amountCents: amount,
    date: const LocalDate(2026, 10, 1),
    createdAt: now,
  );

  group('预算口径（口径 3.1 / 3.2）', () {
    test('budgetAvailable == total + borrowed，且 total 不因借入改变', () {
      const int total = 600000;
      const int borrowed = 150000;

      final int available = SummaryService.budgetAvailable(
        totalCents: total,
        borrowedInBudgetCents: borrowed,
      );

      expect(available, 750000);
      expect(total, 600000, reason: '额度本身不许被借入改掉');
      expect(available - borrowed, total);
    });

    test('没设预算：available 只等于借入，left 为 0（不是负数）', () {
      final BudgetStats stats = SummaryService.budgetStats(
        totalCents: null,
        usedCents: 5000,
      );
      expect(stats.hasBudget, isFalse);
      expect(stats.availableCents, 0);
      expect(stats.leftCents, 0);
      expect(stats.overBudget, isFalse);
      expect(SummaryService.budgetLeft(stats), 0);
    });

    test('借入抬可用额度 → 从超支变不超支', () {
      final BudgetStats without = SummaryService.budgetStats(
        totalCents: 600000,
        usedCents: 650000,
      );
      expect(without.overBudget, isTrue);
      expect(without.overCents, 50000);

      final BudgetStats withBorrow = SummaryService.budgetStats(
        totalCents: 600000,
        usedCents: 650000,
        borrowedInBudgetCents: 100000,
      );
      expect(withBorrow.overBudget, isFalse);
      expect(withBorrow.leftCents, 50000);
    });

    test('usedRatio 超支时 > 1（不截断）', () {
      final BudgetStats stats = SummaryService.budgetStats(
        totalCents: 100000,
        usedCents: 150000,
      );
      expect(SummaryService.usedRatio(stats), 1.5);
    });
  });

  group('净资产（口径 3.2 / 3.4）', () {
    test('netWorth == Σ账户余额 + 应收 − 应付', () {
      final List<Account> accounts = <Account>[
        acc('现金', 100000),
        acc('微信', 25000),
      ];
      final List<Debt> debts = <Debt>[
        debt(DebtDirection.out, 50000, id: 1), // 应收 500
        debt(DebtDirection.in_, 20000, id: 2), // 应付 200
      ];

      expect(SummaryService.accountAssets(accounts), 125000);
      expect(SummaryService.receivable(debts, RepaidIndex.empty), 50000);
      expect(SummaryService.payable(debts, RepaidIndex.empty), 20000);
      expect(
        SummaryService.netWorth(accounts: accounts, debts: debts),
        125000 + 50000 - 20000,
      );
    });

    test('不计入净资产的账户被排除', () {
      final List<Account> accounts = <Account>[
        acc('现金', 100000),
        acc('信用卡', 30000, include: false),
      ];
      expect(SummaryService.accountAssets(accounts), 100000);
    });

    test('已还款部分从应收里扣掉（按流水现算）', () {
      final Debt d = debt(DebtDirection.out, 50000, id: 1);
      final RepaidIndex index = RepaidIndex.fromTxns(<Txn>[
        Txn(
          type: TxnType.income,
          amountCents: 20000,
          date: const LocalDate(2026, 10, 10),
          debtId: 1,
          createdAt: now,
        ),
      ]);
      expect(SummaryService.receivable(<Debt>[d], index), 30000);
      expect(
        SummaryService.netWorth(accounts: const <Account>[], debts: <Debt>[d], index: index),
        30000,
      );
    });

    test('结清的债不进入应收应付', () {
      final Debt d = debt(DebtDirection.out, 50000, id: 1).copyWith(closedAt: now);
      expect(SummaryService.receivable(<Debt>[d], RepaidIndex.empty), 0);
      expect(
        SummaryService.netWorth(accounts: const <Account>[], debts: <Debt>[d]),
        0,
      );
    });
  });

  group('借入对预算的影响（只有 count_in_budget 的借入算）', () {
    test('借出恒不计入、停用的借入不计入、不在本期的借入不计入', () {
      final List<Debt> debts = <Debt>[
        debt(DebtDirection.in_, 100000, id: 1).copyWith(countInBudget: true),
        debt(DebtDirection.in_, 200000, id: 2).copyWith(countInBudget: false),
        debt(DebtDirection.out, 300000, id: 3).copyWith(countInBudget: true),
        debt(DebtDirection.in_, 400000, id: 4)
            .copyWith(countInBudget: true)
            .copyWith(date: const LocalDate(2026, 8, 1)),
      ];

      final int borrowed = SummaryService.borrowedInBudget(
        debts: debts,
        inCurrentPeriod: (Debt d) =>
            d.date >= const LocalDate(2026, 10, 1) &&
            d.date <= const LocalDate(2026, 10, 31),
      );

      expect(borrowed, 100000, reason: '只有第 1 笔既借入、又计入预算、又在本期');
    });
  });
}
