import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/ui/pages/debt/repay_sheet.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 记还款面板：三个默认值、双层拦截、还满自动结清。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  const LocalDate today = LocalDate(2026, 10, 16);

  Future<Debt> makeDebt({int amount = 50000}) async {
    final int id = await Repo.createDebt(
      Debt(
        ledgerId: await currentLedger(),
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: amount,
        accountId: await defaultAccountId(),
        date: const LocalDate(2026, 10, 5),
        createdAt: DateTime(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );
    return (await Repo.debt.byId(id))!;
  }

  Future<RepayInput? Function()> open(
    WidgetTester tester,
    Debt debt, {
    int? remaining,
  }) async {
    final _Holder holder = _Holder();
    final UiHarness h = UiHarness();
    await h.load();
    await h.pump(
      tester,
      host(
        Builder(
          builder: (BuildContext ctx) => TextButton(
            onPressed: () async => holder.input = await showRepaySheet(
              ctx,
              debt: debt,
              remainingCents: remaining ?? debt.amountCents,
              today: today,
            ),
            child: const Text('open-repay'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-repay'));
    await tester.pumpAndSettle();
    return () => holder.input;
  }

  testWidgets('⑦ 默认金额 = 剩余、默认账户 = 这笔当时的账户、默认今天', (
    WidgetTester tester,
  ) async {
    final Debt debt = await makeDebt(amount: 50000);
    await open(tester, debt);

    final TextField amount = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('repay-amount')),
    );
    expect(amount.controller!.text, '500', reason: '剩余 500.00 预填');
    expect(
      find.text('张三 · 剩余 500.00'),
      findsOneWidget,
    );
    // 默认账户是现金（这笔当初从现金借出）
    expect(find.text('现金'), findsOneWidget);
    // 默认日期是传入的「今天」
    expect(find.text('10-16'), findsOneWidget);
  });

  testWidgets('⑦ 金额超过剩余 → 错误提示 + 确认键不可点', (
    WidgetTester tester,
  ) async {
    final Debt debt = await makeDebt(amount: 50000);
    await open(tester, debt);

    await tester.enterText(
      find.byKey(const ValueKey<String>('repay-amount')),
      '600',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('不能超过剩余'), findsOneWidget);
    final FilledButton submit = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('repay-submit')),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('⑦ 金额填 0 → 「金额要大于 0」', (WidgetTester tester) async {
    final Debt debt = await makeDebt(amount: 50000);
    await open(tester, debt);

    await tester.enterText(
      find.byKey(const ValueKey<String>('repay-amount')),
      '0',
    );
    await tester.pumpAndSettle();

    expect(find.text('金额要大于 0'), findsOneWidget);
  });

  testWidgets('⑦ 合法金额 → 确认把 (金额, 账户, 日期) 交回外层', (
    WidgetTester tester,
  ) async {
    final Debt debt = await makeDebt(amount: 50000);
    final RepayInput? Function() result = await open(tester, debt);

    await tester.enterText(
      find.byKey(const ValueKey<String>('repay-amount')),
      '200',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('repay-submit')));
    await tester.pumpAndSettle();

    final RepayInput? input = result();
    expect(input, isNotNull);
    expect(input!.cents, 20000);
    expect(input.accountId, debt.accountId);
    expect(input.date, today);
  });

  testWidgets('⑦ 还满剩余 → 这笔自动标记结清', (WidgetTester tester) async {
    final Debt debt = await makeDebt(amount: 30000);
    final UiHarness h = UiHarness();
    await h.load();
    await h.pump(
      tester,
      host(
        Builder(
          builder: (BuildContext ctx) => TextButton(
            onPressed: () async {
              await submitRepay(
                ctx,
                debt: debt,
                input: (cents: 30000, accountId: debt.accountId, date: today),
                cycleStartDay: 1,
              );
            },
            child: const Text('do-repay'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('do-repay'));
    await tester.pumpAndSettle();

    final Debt after = (await Repo.debt.byId(debt.id!))!;
    expect(after.closedAt, isNotNull);
    final RepaidIndex index = RepaidIndex.fromTxns(
      await Repo.txn.byDebt(debt.id!),
    );
    expect(after.remainingCents(index), 0);
  });

  testWidgets('⑦ 数据层拦截时给出 toast 而不是崩（ArgumentError 被吃成提示）', (
    WidgetTester tester,
  ) async {
    final Debt debt = await makeDebt(amount: 10000);
    await UiHarness().pump(
      tester,
      host(
        Builder(
          builder: (BuildContext ctx) => TextButton(
            onPressed: () async {
              await submitRepay(
                ctx,
                debt: debt,
                // 故意超额：面板之外直接调，靠 Repo 抛 ArgumentError
                input: (cents: 99999, accountId: debt.accountId, date: today),
                cycleStartDay: 1,
              );
            },
            child: const Text('over-repay'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('over-repay'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final Debt after = (await Repo.debt.byId(debt.id!))!;
    expect(after.closedAt, isNull, reason: '拦住了就不该结清');
  });

  test('⑦ 删除往来的确认文案写明「N 笔流水 + 回滚余额」', () {
    final String body = deleteDebtConfirmBody(txnCount: 3);
    expect(body, contains('3 笔'));
    expect(body, contains('回滚余额'));
  });
}

class _Holder {
  RepayInput? input;
}
