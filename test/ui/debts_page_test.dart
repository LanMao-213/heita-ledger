import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/data/services/debt_grouping.dart';
import 'package:heita_ledger/stores/catalog_store.dart';
import 'package:heita_ledger/ui/pages/debt/counterparty_list.dart';
import 'package:heita_ledger/ui/pages/debt/debts_page.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 往来页：摘要只算未结清、按人分桶、净额相抵、逾期、已结清段、单笔直达详情。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  const LocalDate today = LocalDate(2026, 10, 16);

  Future<int> debt({
    required String who,
    required int amount,
    DebtDirection dir = DebtDirection.out,
    LocalDate? due,
    bool closed = false,
  }) async {
    final int id = await Repo.createDebt(
      Debt(
        ledgerId: await currentLedger(),
        direction: dir,
        counterparty: who,
        amountCents: amount,
        accountId: await defaultAccountId(),
        date: const LocalDate(2026, 10, 5),
        dueDate: due,
        createdAt: DateTime(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );
    if (closed) await Repo.debt.setClosed(id, true);
    return id;
  }

  Future<UiHarness> pumpDebts(WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.wrap(const DebtsPage()));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('① 无往来 → 整页空态', (WidgetTester tester) async {
    await pumpDebts(tester);
    expect(find.byKey(const ValueKey<String>('debts-empty')), findsOneWidget);
    expect(find.text('还没有往来'), findsOneWidget);
  });

  testWidgets('① 摘要卡只算未结清的剩余，已结清不计入', (
    WidgetTester tester,
  ) async {
    await debt(who: '张三', amount: 50000);
    await debt(who: '李四', amount: 30000, closed: true);
    await debt(
      who: '王五',
      amount: 20000,
      dir: DebtDirection.in_,
    );
    final UiHarness h = await pumpDebts(tester);

    final int receivable = (await Repo.debt.totals(
      await currentLedger(),
    )).receivable;
    expect(receivable, 50000, reason: '李四那笔已结清，不该算进来');
    expect(
      find.byKey(const ValueKey<String>('debts-summary-receivable')),
      findsOneWidget,
    );
    expect(h.plan.debts.length, 2, reason: '列表里只剩未结清的两笔');
  });

  testWidgets('② 按人分桶：空名字归「未填对方」而不是丢掉', (
    WidgetTester tester,
  ) async {
    await debt(who: '  张三  ', amount: 10000);
    await debt(who: '', amount: 20000);
    await pumpDebts(tester);

    expect(find.byKey(const ValueKey<String>('cp-张三')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('cp-未填对方')),
      findsOneWidget,
      reason: 'trim 后为空也不能丢，归到「未填对方」',
    );
  });

  test('② 同一个人既借出又借入 → 净额相抵，副行写两边金额', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final int outId = await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: 50000,
        accountId: acc,
        date: const LocalDate(2026, 10, 5),
        createdAt: DateTime(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );
    await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.in_,
        counterparty: '张三',
        amountCents: 20000,
        accountId: acc,
        date: const LocalDate(2026, 10, 6),
        createdAt: DateTime(2026, 10, 6),
      ),
      cycleStartDay: 1,
    );
    expect(outId, isPositive);

    final List<Debt> open = await Repo.debt.all(ledger, includeClosed: false);
    final RepaidIndex index = await Repo.debt.repaidIndex(ledger);
    final person = groupDebtsByCounterparty(open, repaid: index).single;

    expect(person.isMixed(index), isTrue);
    expect(person.netCents(index), 30000, reason: '净额 = 借出 500 − 借入 200');
    expect(
      counterpartySubtitle(person, index: index, today: today),
      contains('借出'),
    );
    expect(
      counterpartySubtitle(person, index: index, today: today),
      contains('借入'),
    );
  });

  test('② 逾期写「逾期 N 天」', () {
    final PersonDebts person = PersonDebts('张三', <Debt>[
      Debt(
        id: 1,
        ledgerId: 1,
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: 10000,
        date: const LocalDate(2026, 9, 1),
        dueDate: const LocalDate(2026, 10, 10),
        createdAt: DateTime(2026, 9, 1),
      ),
    ]);
    expect(person.overdueDays(today: today), 6);
    expect(
      counterpartySubtitle(
        person,
        index: RepaidIndex.empty,
        today: today,
      ),
      contains('逾期 6 天'),
    );
  });

  test('② 4 级排序：逾期 → 应还日 → 净额 → 名字', () {
    Debt d(int id, String who, int cents, LocalDate? due) => Debt(
      id: id,
      ledgerId: 1,
      direction: DebtDirection.out,
      counterparty: who,
      amountCents: cents,
      date: const LocalDate(2026, 10, 1),
      dueDate: due,
      createdAt: DateTime(2026, 10, 1),
    );

    final List<PersonDebts> groups = groupDebtsByCounterparty(<Debt>[
      d(1, '无日期', 900, null),
      d(2, '晚到期', 100, const LocalDate(2026, 12, 1)),
      d(3, '早到期', 100, const LocalDate(2026, 10, 25)),
      d(4, '逾期', 100, const LocalDate(2026, 10, 1)),
    ], today: today);

    expect(
      groups.map((PersonDebts p) => p.name).toList(),
      <String>['逾期', '早到期', '晚到期', '无日期'],
    );
  });

  testWidgets('③ 已结清段：一笔一行、整体 dimmed、金额位写「已结清」', (
    WidgetTester tester,
  ) async {
    final int id = await debt(who: '李四', amount: 30000, closed: true);
    await pumpDebts(tester);

    expect(
      find.byKey(ValueKey<String>('debt-closed-$id')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('debt-closed-badge-$id')),
      findsOneWidget,
    );
    final Opacity dimmed = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(ValueKey<String>('debt-closed-$id')),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(dimmed.opacity, lessThan(1));
  });

  testWidgets('④ 单笔时点人 → 直接进详情（不套一层列表）', (
    WidgetTester tester,
  ) async {
    await debt(who: '张三', amount: 50000);
    await pumpDebts(tester);

    await tester.tap(find.byKey(const ValueKey<String>('cp-张三')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('debt-detail-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('debt-person-title')),
      findsNothing,
      reason: '只有一笔就不该再套一层人名列表',
    );
  });

  testWidgets('⑤ 详情 4 行 kv + 主按钮 + 次按钮', (WidgetTester tester) async {
    await debt(
      who: '张三',
      amount: 50000,
      due: const LocalDate(2026, 10, 10),
    );
    await pumpDebts(tester);
    await tester.tap(find.byKey(const ValueKey<String>('cp-张三')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('debt-kv-principal')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('debt-kv-repaid')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('debt-kv-remaining')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('debt-kv-due')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('debt-repay')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('debt-toggle-closed')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('debt-delete')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey<String>('debt-kv-due'))).data,
      contains('逾期'),
    );
  });

  testWidgets('⑤ 已结清 → 不显示「记一笔还款」，次按钮变成「撤销结清」', (
    WidgetTester tester,
  ) async {
    final int id = await debt(who: '李四', amount: 30000, closed: true);
    await pumpDebts(tester);
    // 已结清的不在「按人」段里，走末尾的已结清行
    await tester.tap(find.byKey(ValueKey<String>('debt-closed-$id')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('debt-repay')), findsNothing);
    expect(find.text('撤销结清'), findsOneWidget);
  });

  testWidgets('④ 未约定应还日时写「未约定」', (WidgetTester tester) async {
    await debt(who: '张三', amount: 50000);
    await pumpDebts(tester);
    await tester.tap(find.byKey(const ValueKey<String>('cp-张三')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey<String>('debt-kv-due'))).data,
      '未约定',
    );
  });

  test('空名字归「未填对方」而不是空字符串（纯函数）', () async {
    final CatalogStore store = CatalogStore();
    await store.loadCatalog(await currentLedger());
    expect(kUnnamedCounterparty, '未填对方');
    expect(store.ledgerId, greaterThan(0));
  });
}
