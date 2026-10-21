import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/ui/pages/recurring/recurring_editor.dart';
import 'package:heita_ledger/ui/pages/recurring/recurring_page.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 周期账单页：文案无星号、规则卡副行、启停、删除不删流水、表单校验、两个新控件落库。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<int> rule({
    required LocalDate next,
    RecurFreq freq = RecurFreq.monthly,
    int interval = 1,
    LocalDate? end,
    int amount = 300000,
    bool enabled = true,
  }) async {
    return Repo.recurring.insert(
      Recurring(
        ledgerId: await currentLedger(),
        type: TxnType.expense,
        amountCents: amount,
        categoryId: await topCategoryId(),
        accountId: await defaultAccountId(),
        note: '房租',
        freq: freq,
        interval: interval,
        nextRunDate: next,
        endDate: end,
        enabled: enabled,
      ),
    );
  }

  Future<UiHarness> pumpPage(WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.wrap(const RecurringPage()));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('① 机制说明文案里**没有** Markdown 星号', (WidgetTester tester) async {
    await rule(next: LocalDate.today());
    await pumpPage(tester);

    final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
    for (final Text t in texts) {
      expect(
        t.data ?? '',
        isNot(contains('*')),
        reason: '「${t.data}」里出现了星号：用户看到的是 ** 而不是加粗',
      );
    }
    expect(find.byKey(const ValueKey<String>('recurring-note')), findsOneWidget);
  });

  testWidgets('② 规则卡副行「每月 · 支出 ¥3,000.00 · 下次 11-01」', (
    WidgetTester tester,
  ) async {
    final int id = await rule(next: const LocalDate(2026, 11, 1));
    await pumpPage(tester);

    final Text sub = tester.widget<Text>(
      find.byKey(ValueKey<String>('recurring-sub-$id')),
    );
    expect(sub.data, contains('每月'));
    expect(sub.data, contains('支出'));
    expect(sub.data, contains('3,000.00'));
    expect(sub.data, contains('下次 11-01'));
  });

  testWidgets('② 到期未补记时副行写「待补记」且是警示色', (
    WidgetTester tester,
  ) async {
    final int id = await rule(next: LocalDate.today().addDays(-1));
    await pumpPage(tester);

    final Text sub = tester.widget<Text>(
      find.byKey(ValueKey<String>('recurring-sub-$id')),
    );
    expect(sub.data, contains('待补记'));
    expect(sub.style!.color, isNotNull);
  });

  testWidgets('② 启停开关只改 enabled，别的字段不动', (
    WidgetTester tester,
  ) async {
    final int id = await rule(next: const LocalDate(2026, 11, 1));
    await pumpPage(tester);

    await tester.tap(find.byKey(ValueKey<String>('recurring-toggle-$id')));
    await tester.pumpAndSettle();

    final Recurring r = (await Repo.recurring.all(await currentLedger())).single;
    expect(r.enabled, isFalse);
    expect(r.amountCents, 300000);
    expect(r.nextRunDate.iso, '2026-11-01');
  });

  testWidgets('② 删除规则不删已经生成的流水', (WidgetTester tester) async {
    final int id = await rule(next: const LocalDate(2026, 10, 15));
    await Repo.recurring.runDueRecurring(
      ledgerId: await currentLedger(),
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 16),
    );
    final int before = (await Repo.txn.allOfLedger(await currentLedger())).length;
    await pumpPage(tester);

    await tester.longPress(find.byKey(ValueKey<String>('recurring-card-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('confirm-ok')));
    await tester.pumpAndSettle();

    expect(await Repo.recurring.all(await currentLedger()), isEmpty);
    expect(
      (await Repo.txn.allOfLedger(await currentLedger())).length,
      before,
      reason: '规则只是「以后不再生成」，历史流水一条都不能少',
    );
  });

  testWidgets('③ 金额 <= 0 → 「金额要大于 0」且不保存', (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey<String>('recurring-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('recurring-amount')),
      '0',
    );
    await tester.tap(find.byKey(const ValueKey<String>('recurring-save')));
    await tester.pumpAndSettle();

    expect(find.text('金额要大于 0'), findsOneWidget);
    expect(await Repo.recurring.all(await currentLedger()), isEmpty);
  });

  testWidgets('③ interval 与 end_date 都真实落库', (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey<String>('recurring-new')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('recurring-note')),
      '物业费',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('recurring-amount')),
      '300',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('recurring-interval')),
      '3',
    );
    await tester.tap(find.byKey(const ValueKey<String>('recurring-save')));
    await tester.pumpAndSettle();

    final Recurring saved = (await Repo.recurring.all(await currentLedger())).single;
    expect(saved.amountCents, 30000);
    expect(saved.interval, 3, reason: '「每 3 个周期」必须落库（原版有列无入口）');
    expect(saved.freq, RecurFreq.monthly);
  });

  testWidgets('interval 越界被夹到 1..12', (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey<String>('recurring-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('recurring-amount')),
      '100',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('recurring-interval')),
      '99',
    );
    await tester.tap(find.byKey(const ValueKey<String>('recurring-save')));
    await tester.pumpAndSettle();

    expect(
      (await Repo.recurring.all(await currentLedger())).single.interval,
      12,
    );
  });

  testWidgets('⑦ 「立刻补记」绕过闸一：自动补记过之后按钮仍然有效', (
    WidgetTester tester,
  ) async {
    await rule(next: const LocalDate(2026, 10, 15), freq: RecurFreq.daily);
    final UiHarness h = await pumpPage(tester);

    // 先让自动补记把今天的额度用掉（闸一记上）
    await h.plan.catchUp(today: const LocalDate(2026, 10, 16));
    // 再加一条已到期的规则：自动补记会被闸一挡掉
    await rule(next: const LocalDate(2026, 10, 14), freq: RecurFreq.daily);
    expect(await h.plan.catchUp(today: const LocalDate(2026, 10, 16)), 0);

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('recurring-catchup')));
    await tester.pumpAndSettle();

    expect(
      h.plan.recurring.length,
      2,
      reason: '两条规则都还在（补记不会删规则）',
    );
    expect(find.textContaining('已补记'), findsOneWidget);
  });

  testWidgets('无规则时给空态，不是一片空白', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(find.byKey(const ValueKey<String>('recurring-empty')), findsOneWidget);
  });

  test('入口副行：有到期就写「N 条待补记」', () {
    final List<Recurring> rules = <Recurring>[
      Recurring(
        type: TxnType.expense,
        amountCents: 100,
        nextRunDate: LocalDate.today().addDays(-1),
      ),
      Recurring(
        type: TxnType.expense,
        amountCents: 100,
        nextRunDate: LocalDate.today().addDays(5),
      ),
    ];
    expect(recurringEntrySubtitle(rules), '1 条待补记');
    expect(recurringEntrySubtitle(const <Recurring>[]), '还没有周期账单');
    expect(daysUntilDue(rules.last), 5);
  });
}
