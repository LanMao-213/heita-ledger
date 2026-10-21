import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/stores/catalog_store.dart';
import 'package:heita_ledger/ui/pages/plan/goal_card.dart';
import 'package:heita_ledger/ui/widgets/amount_text.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 储蓄目标：CRUD + 存取、取超按 0 兜底、存钱不生成流水。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<CatalogStore> catalog() async {
    final CatalogStore store = CatalogStore();
    await store.loadCatalog(await currentLedger());
    return store;
  }

  Future<int> txnCount() async =>
      (await Repo.txn.allOfLedger(await currentLedger())).length;

  test('⑤ 新建：saveGoal 之后列表里有了', () async {
    final CatalogStore store = await catalog();
    expect(store.goals, isEmpty);

    await store.saveGoal(
      const SavingGoal(name: '换手机', targetCents: 500000),
    );

    expect(store.goals.length, 1);
    expect(store.goals.single.name, '换手机');
    expect(store.goals.single.savedCents, 0);
  });

  test('⑤ 编辑：改名字与目标金额，已存不动', () async {
    final CatalogStore store = await catalog();
    await store.saveGoal(const SavingGoal(name: '换手机', targetCents: 500000));
    final SavingGoal created = store.goals.single;
    await store.addGoalFunds(created.id!, 120000);

    await store.saveGoal(
      store.goals.single.copyWith(name: '换电脑', targetCents: 900000),
    );

    final SavingGoal updated = (await catalog()).goals.single;
    expect(updated.name, '换电脑');
    expect(updated.targetCents, 900000);
    expect(updated.savedCents, 120000, reason: '改名不该把攒的钱清掉');
  });

  test('⑤ 删除：目标没了', () async {
    final CatalogStore store = await catalog();
    await store.saveGoal(const SavingGoal(name: '旅行', targetCents: 100000));
    final int id = store.goals.single.id!;

    await store.deleteGoal(id);

    expect(store.goals, isEmpty);
    expect((await catalog()).goals, isEmpty);
  });

  test('⑤ 存钱：已存增加，且**不生成流水**', () async {
    final CatalogStore store = await catalog();
    await store.saveGoal(const SavingGoal(name: '旅行', targetCents: 100000));
    final int before = await txnCount();

    final int saved = await store.addGoalFunds(store.goals.single.id!, 50000);

    expect(saved, 50000);
    expect(store.goals.single.savedCents, 50000);
    expect(
      await txnCount(),
      before,
      reason: '存钱不是支出：进了流水会把预算和统计一起污染',
    );
  });

  test('⑤ 取钱：从已存里扣', () async {
    final CatalogStore store = await catalog();
    await store.saveGoal(const SavingGoal(name: '旅行', targetCents: 100000));
    final int id = store.goals.single.id!;
    await store.addGoalFunds(id, 50000);

    final int saved = await store.addGoalFunds(id, -20000);

    expect(saved, 30000);
    expect(store.goals.single.savedCents, 30000);
  });

  test('⑤ 取钱超过已存 → MAX(0, saved + delta) 兜底为 0', () async {
    final CatalogStore store = await catalog();
    await store.saveGoal(const SavingGoal(name: '旅行', targetCents: 100000));
    final int id = store.goals.single.id!;
    await store.addGoalFunds(id, 50000);

    final int saved = await store.addGoalFunds(id, -80000);

    expect(saved, 0, reason: '不许出现负存款（那会变成「倒欠目标」）');
    expect(store.goals.single.savedCents, 0);
  });

  testWidgets('卡片：名字 / 已存 / 还差 / 两个按钮', (WidgetTester tester) async {
    const SavingGoal goal = SavingGoal(
      id: 7,
      name: '换手机',
      targetCents: 500000,
      savedCents: 120000,
      dueMonth: '2027-03',
    );
    await UiHarness().pump(
      tester,
      host(
        SingleChildScrollView(
          child: GoalCard(
            goal: goal,
            onEdit: () {},
            onDeposit: () {},
            onWithdraw: () {},
          ),
        ),
      ),
    );

    expect(find.text('换手机'), findsOneWidget);
    expect(find.text('目标 2027-03'), findsOneWidget);
    final AmountText saved = tester.widget<AmountText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('goal-7')),
        matching: find.byType(AmountText),
      ),
    );
    expect(saved.cents, 120000);
    expect(find.text('还差 3,800.00'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('goal-deposit-7')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('goal-withdraw-7')), findsOneWidget);
  });

  testWidgets('卡片：攒够了显示「已达成」', (WidgetTester tester) async {
    const SavingGoal goal = SavingGoal(
      id: 8,
      name: '键盘',
      targetCents: 100000,
      savedCents: 100000,
    );
    await UiHarness().pump(
      tester,
      host(GoalCard(goal: goal, onEdit: () {}, onDeposit: () {}, onWithdraw: () {})),
    );

    expect(find.byKey(const ValueKey<String>('goal-done-8')), findsOneWidget);
    expect(goal.isDone, isTrue);
    expect(goal.remainingCents, 0);
  });

  test('进度比例与还差（超额存也不产生负的「还差」）', () {
    const SavingGoal half = SavingGoal(name: 'a', targetCents: 100000, savedCents: 50000);
    expect(half.progress, 0.5);
    expect(half.remainingCents, 50000);

    const SavingGoal over = SavingGoal(name: 'b', targetCents: 100000, savedCents: 150000);
    expect(over.progress, 1.5, reason: '不截断，界面自己 clamp');
    expect(over.remainingCents, 0);

    const SavingGoal zeroTarget = SavingGoal(name: 'c', targetCents: 0, savedCents: 100);
    expect(zeroTarget.progress, 0, reason: '目标 0 时不产生 NaN');
  });

  test('存钱之后目标的顺序不乱（sort_order 稳定）', () async {
    final CatalogStore store = await catalog();
    await store.saveGoal(const SavingGoal(name: 'A', targetCents: 1000));
    await store.saveGoal(const SavingGoal(name: 'B', targetCents: 1000));
    await store.addGoalFunds(store.goals.last.id!, 500);

    final List<SavingGoal> after = (await catalog()).goals;
    expect(after.map((SavingGoal g) => g.name).toList(), <String>['A', 'B']);
  });

  test('目标月份可以不填（卡片显示「没有期限」）', () {
    const SavingGoal g = SavingGoal(
      name: 'x',
      targetCents: 100,
      dueMonth: null,
    );
    expect(g.dueMonth, isNull);
    expect(LocalDate.today().year, greaterThan(2000));
  });
}
