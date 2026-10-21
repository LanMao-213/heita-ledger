import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/category_repo.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/ui/pages/category/category_editor.dart';
import 'package:heita_ledger/ui/pages/category/cats_page.dart';
import 'package:heita_ledger/ui/pages/category/sub_cats_page.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 分类管理：9/6 行、副行、进子页、只写当前层、停用消失+恢复回原位、
/// 历史仍显示原名、不级联、删分类三件事（条数不变）。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<UiHarness> pumpCats(WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.wrap(const CatsPage()));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('① 一级页：支出 9 行、收入 6 行', (WidgetTester tester) async {
    final UiHarness h = await pumpCats(tester);
    final int expense = h.catalog.tree.tops
        .where((Category c) => c.type == TxnType.expense && !c.archived)
        .length;
    final int income = h.catalog.tree.tops
        .where((Category c) => c.type == TxnType.income && !c.archived)
        .length;

    expect(expense, 9, reason: '种子：支出 9 个一级');
    expect(income, 6, reason: '种子：收入 6 个一级');
    expect(find.text('支出'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey<String>('chip-收入')));
    await tester.pumpAndSettle();
    expect(find.text('工资'), findsOneWidget);
  });

  testWidgets('① 副行写「N 个子分类」/「还没有子分类」', (WidgetTester tester) async {
    final UiHarness h = await pumpCats(tester);
    final Category withSubs = h.catalog.tree.tops.firstWhere(
      (Category c) => h.catalog.tree.childrenOf(c.id).isNotEmpty,
    );
    final int n = h.catalog.tree.childrenOf(withSubs.id).length;

    expect(
      tester
          .widget<Text>(
            find.byKey(ValueKey<String>('cat-subcount-${withSubs.id}')),
          )
          .data,
      '$n 个子分类',
    );
  });

  testWidgets('① 点整行进子页（不是编辑框）', (WidgetTester tester) async {
    final UiHarness h = await pumpCats(tester);
    final Category top = h.catalog.tree.tops.first;

    await tester.tap(find.byKey(ValueKey<String>('cat-row-${top.id}')));
    await tester.pumpAndSettle();

    expect(find.byType(SubCatsPage), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey<String>('sub-title'))).data,
      contains(top.name),
    );
    expect(find.text('新建子分类'), findsOneWidget);
  });

  testWidgets('② 子页没有「第三层」入口', (WidgetTester tester) async {
    final UiHarness h = await pumpCats(tester);
    final Category top = h.catalog.tree.tops.first;
    await tester.tap(find.byKey(ValueKey<String>('cat-row-${top.id}')));
    await tester.pumpAndSettle();

    // 子页里的行不再带「子分类」按钮（那才是第三层入口）
    final Category? child = h.catalog.tree.childrenOf(top.id).isEmpty
        ? null
        : h.catalog.tree.childrenOf(top.id).first;
    if (child != null) {
      expect(
        find.byKey(ValueKey<String>('cat-subs-${child.id}')),
        findsNothing,
      );
    }
    // 数据层也拦：父级必须是 parent_id IS NULL
    await expectLater(
      Repo.category.insert(
        Category(
          ledgerId: await currentLedger(),
          type: TxnType.expense,
          name: '第三层',
          parentId: child?.id ?? top.id,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('① 拖拽只写**当前层**的 sort_order（同级各自从 0 起）', () async {
    final int ledger = await currentLedger();
    final CategoryTree tree = await Repo.category.tree(ledger);
    final List<Category> expenseTops = <Category>[
      for (final Category c in tree.tops)
        if (c.type == TxnType.expense) c,
    ];
    final List<Category> incomeTops = <Category>[
      for (final Category c in tree.tops)
        if (c.type == TxnType.income) c,
    ];

    // 把支出一级倒过来排
    final List<int> reversed = <int>[
      for (final Category c in expenseTops.reversed) c.id!,
    ];
    await Repo.category.reorder(reversed);

    final CategoryTree after = await Repo.category.tree(ledger);
    final List<int> expenseOrder = <int>[
      for (final Category c in after.tops)
        if (c.type == TxnType.expense) c.id!,
    ];
    expect(expenseOrder, reversed);
    expect(after.byId(reversed.first)!.sortOrder, 0);
    // 收入层一动不动
    expect(
      <int>[
        for (final Category c in after.tops)
          if (c.type == TxnType.income) c.id!,
      ],
      <int>[for (final Category c in incomeTops) c.id!],
    );
  });

  testWidgets('④ 停用：从树里消失、落到末尾「已停用」段；历史流水仍显示原名', (
    WidgetTester tester,
  ) async {
    final UiHarness h = await pumpCats(tester);
    final Category top = h.catalog.tree.tops.first;
    final int order = top.sortOrder;

    // 先记一笔，停用后历史要还显示原名
    await Repo.saveTxn(
      mkTxn(
        ledgerId: await currentLedger(),
        amountCents: 1000,
        date: const LocalDate(2026, 10, 10),
        periodStart: const LocalDate(2026, 10, 1),
        categoryId: top.id,
        accountId: await defaultAccountId(),
      ),
      cycleStartDay: 1,
    );

    await Repo.category.setArchived(top.id!, true);
    await h.catalog.reloadCategories();
    await tester.pumpAndSettle();

    // 从「可选分类」里消失（录入 / 预算 / 筛选 / 统计都读 topsOf）
    expect(
      h.catalog.tree.topsOf(TxnType.expense).any((Category c) => c.id == top.id),
      isFalse,
      reason: '停用后不该再出现在任何选择器里',
    );
    // 落到「已停用」段
    expect(
      find.byKey(ValueKey<String>('cat-archived-${top.id}')),
      findsOneWidget,
    );
    // 历史流水仍显示原名
    expect(h.catalog.displayName(top.id), top.name);

    // 恢复：回到原位置（sort_order 没被动过）
    await Repo.category.setArchived(top.id!, false);
    await h.catalog.reloadCategories();
    expect(h.catalog.tree.byId(top.id)!.sortOrder, order);
  });

  test('④ 停用一级**不级联**停用子分类', () async {
    final int ledger = await currentLedger();
    final CategoryTree tree = await Repo.category.tree(ledger);
    final Category top = tree.tops.firstWhere(
      (Category c) => tree.childrenOf(c.id).isNotEmpty && c.type == TxnType.expense,
    );
    final Category child = tree.childrenOf(top.id).first;

    await Repo.category.setArchived(top.id!, true);

    final CategoryTree after = await Repo.category.tree(ledger);
    expect(after.byId(top.id)!.archived, isTrue);
    expect(
      after.byId(child.id)!.archived,
      isFalse,
      reason: '停用只影响自己那一行，子分类各自独立',
    );
  });

  test('⑤ 删除分类：一个事务做三件事（流水置 NULL + 删预算 + 删分类及子）', () async {
    final int ledger = await currentLedger();
    final CategoryTree tree = await Repo.category.tree(ledger);
    final Category top = tree.tops.firstWhere(
      (Category c) => c.type == TxnType.expense && tree.childrenOf(c.id).isNotEmpty,
    );
    final Category child = tree.childrenOf(top.id).first;
    final int acc = await defaultAccountId();

    for (final Category c in <Category>[top, child]) {
      await Repo.saveTxn(
        mkTxn(
          ledgerId: ledger,
          amountCents: 1000,
          date: const LocalDate(2026, 10, 10),
          periodStart: const LocalDate(2026, 10, 1),
          categoryId: c.id,
          accountId: acc,
        ),
        cycleStartDay: 1,
      );
    }
    await Repo.budget.setCategoryBudget(
      ledgerId: ledger,
      periodStart: const LocalDate(2026, 10, 1),
      categoryId: top.id!,
      amountCents: 100000,
    );
    final int before = (await Repo.txn.allOfLedger(ledger)).length;

    final DeleteCategoryResult result = await Repo.category.delete(top.id!);

    expect(result.detachedTxns, greaterThanOrEqualTo(2), reason: '一级 + 子分类的流水都置 NULL');
    expect(result.deletedBudgets, 1);
    expect(result.deletedCategories, 1 + tree.childrenOf(top.id).length,
        reason: '一级连带它全部子分类');
    final CategoryTree after = await Repo.category.tree(ledger);
    expect(after.byId(top.id), isNull);
    expect(after.byId(child.id), isNull);
    expect(
      await Repo.budget.categoryBudgets(ledger, const LocalDate(2026, 10, 1)),
      isEmpty,
    );
    final List<Txn> txns = await Repo.txn.allOfLedger(ledger);
    expect(txns.length, before, reason: '流水一条都不能少');
    expect(txns.every((Txn t) => t.categoryId == null), isTrue);
  });

  test('⑤ 删除确认文案区分「连同 N 个子分类」与「没有子分类」', () {
    final String withChildren = deleteCategoryBody(
      name: '餐饮',
      childCount: 3,
      txnCount: 12,
    );
    expect(withChildren, contains('连同 3 个子分类'));
    expect(withChildren, contains('12 笔账目'));
    expect(withChildren, contains('未分类'));

    final String without = deleteCategoryBody(
      name: '交通',
      childCount: 0,
      txnCount: 0,
    );
    expect(without, contains('没有子分类'));
    expect(without, isNot(contains('连同')));
  });

  test('⑥ 删除后明细里那些记录变「未分类」但条数不变（纯数据侧）', () async {
    final int ledger = await currentLedger();
    final int cat = await topCategoryId();
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 1000,
        date: const LocalDate(2026, 10, 10),
        periodStart: const LocalDate(2026, 10, 1),
        categoryId: cat,
        accountId: await defaultAccountId(),
      ),
      cycleStartDay: 1,
    );

    final int before = (await Repo.txn.allOfLedger(ledger)).length;
    final DeleteCategoryResult result = await Repo.category.delete(cat);

    expect(result.detachedTxns, before, reason: '所有挂在这个分类上的流水都要置 NULL');
    expect(result.deletedCategories, greaterThanOrEqualTo(1));
    final List<Txn> after = await Repo.txn.allOfLedger(ledger);
    expect(after.length, before, reason: '条数一条不少');
    expect(after.every((Txn t) => t.categoryId == null), isTrue);
  });

  testWidgets('停用段的分类点一下能回到编辑（里面可以恢复）', (
    WidgetTester tester,
  ) async {
    final UiHarness h = await pumpCats(tester);
    final Category top = h.catalog.tree.tops.first;
    await Repo.category.setArchived(top.id!, true);
    await h.catalog.reloadCategories();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey<String>('cat-archived-${top.id}')));
    await tester.pumpAndSettle();

    expect(find.text('恢复这个分类'), findsOneWidget);
  });
}
