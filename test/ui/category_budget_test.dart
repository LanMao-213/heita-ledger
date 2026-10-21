import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/stores/plan_store.dart';
import 'package:heita_ledger/ui/pages/plan/category_budget_list.dart';
import 'package:heita_ledger/ui/widgets/amount_text.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 分类预算：只列「设了预算的 ∪ 本期有支出的一级」、停用不出现、
/// 支出含子分类、有预算的按额度降序在前。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  const Period october = Period(
    from: LocalDate(2026, 10, 1),
    to: LocalDate(2026, 10, 31),
  );

  Category cat(int id, String name, {int? parentId, bool archived = false}) =>
      Category(
        id: id,
        type: TxnType.expense,
        name: name,
        parentId: parentId,
        archived: archived,
      );

  CategoryTree tree(List<Category> all) => CategoryTree(all);

  test('④ 只列「设了预算的 ∪ 本期有支出的一级」', () {
    final List<CategoryBudgetRow> rows = buildCategoryBudgetRows(
      tree: tree(<Category>[
        cat(1, '餐饮'),
        cat(2, '交通'),
        cat(3, '购物'),
      ]),
      budgets: const <Budget>[
        Budget(periodStart: LocalDate(2026, 10, 1), categoryId: 2, amountCents: 50000),
      ],
      spentByCategory: <int, int>{1: 30000, 3: 0},
    );

    expect(rows.map((CategoryBudgetRow r) => r.category.name), <String>['交通', '餐饮']);
    expect(
      rows.map((CategoryBudgetRow r) => r.category.name),
      isNot(contains('购物')),
      reason: '没预算也没支出 → 不占一行',
    );
  });

  test('④ 已停用的分类不出现（历史支出还在，但不再给它设限额）', () {
    final List<CategoryBudgetRow> rows = buildCategoryBudgetRows(
      tree: tree(<Category>[
        cat(1, '餐饮'),
        cat(2, '旧分类', archived: true),
      ]),
      budgets: const <Budget>[
        Budget(periodStart: LocalDate(2026, 10, 1), categoryId: 2, amountCents: 50000),
      ],
      spentByCategory: <int, int>{1: 1000, 2: 9999},
    );

    expect(rows.length, 1);
    expect(rows.single.category.name, '餐饮');
  });

  test('④ 子分类的支出算到一级上（记到「正餐」→ 餐饮的进度条要动）', () {
    final List<CategoryBudgetRow> rows = buildCategoryBudgetRows(
      tree: tree(<Category>[
        cat(1, '餐饮'),
        cat(11, '正餐', parentId: 1),
      ]),
      budgets: const <Budget>[
        Budget(periodStart: LocalDate(2026, 10, 1), categoryId: 1, amountCents: 100000),
      ],
      // spentByCategory 的键是**一级**（SQL 里 COALESCE(parent_id, id)）
      spentByCategory: <int, int>{1: 3850},
    );
    expect(rows.single.spentCents, 3850);
    expect(rows.single.ratio, closeTo(0.0385, 1e-9));
  });

  test('④ 有预算的按额度降序在前，没预算的按已花降序在后', () {
    final List<CategoryBudgetRow> rows = buildCategoryBudgetRows(
      tree: tree(<Category>[
        cat(1, '餐饮'),
        cat(2, '交通'),
        cat(3, '购物'),
        cat(4, '娱乐'),
      ]),
      budgets: const <Budget>[
        Budget(periodStart: LocalDate(2026, 10, 1), categoryId: 1, amountCents: 30000),
        Budget(periodStart: LocalDate(2026, 10, 1), categoryId: 2, amountCents: 90000),
      ],
      spentByCategory: <int, int>{1: 100, 2: 200, 3: 5000, 4: 7000},
    );
    expect(
      rows.map((CategoryBudgetRow r) => r.category.name).toList(),
      <String>['交通', '餐饮', '娱乐', '购物'],
    );
  });

  test('超支时 over 与 ratio 都要能看出来（进度条自己 clamp）', () {
    final List<CategoryBudgetRow> rows = buildCategoryBudgetRows(
      tree: tree(<Category>[cat(1, '餐饮')]),
      budgets: const <Budget>[
        Budget(periodStart: LocalDate(2026, 10, 1), categoryId: 1, amountCents: 10000),
      ],
      spentByCategory: <int, int>{1: 15000},
    );
    expect(rows.single.ratio, 1.5);
    expect(rows.single.overCents, 5000);
    expect(rows.single.leftCents, -5000);
  });

  testWidgets('渲染：有预算的显示已花/额度，没预算的显示「未设」', (
    WidgetTester tester,
  ) async {
    final List<CategoryBudgetRow> rows = buildCategoryBudgetRows(
      tree: tree(<Category>[cat(1, '餐饮'), cat(2, '交通')]),
      budgets: const <Budget>[
        Budget(periodStart: LocalDate(2026, 10, 1), categoryId: 1, amountCents: 100000),
      ],
      spentByCategory: <int, int>{1: 3850, 2: 1200},
    );

    await UiHarness().pump(
      tester,
      host(
        SingleChildScrollView(
          child: CategoryBudgetList(rows: rows, onEdit: (CategoryBudgetRow _) {}),
        ),
      ),
    );

    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('交通'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('cat-budget-unset-2')),
      findsOneWidget,
    );
    expect(find.text('未设'), findsOneWidget);
    final AmountText spent = tester.widget<AmountText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('cat-budget-1')),
        matching: find.byType(AmountText),
      ),
    );
    expect(spent.cents, 3850);
  });

  testWidgets('空列表给一句人话（不是空白）', (WidgetTester tester) async {
    await UiHarness().pump(
      tester,
      host(CategoryBudgetList(rows: const <CategoryBudgetRow>[], onEdit: (_) {})),
    );
    expect(
      find.byKey(const ValueKey<String>('category-budget-empty')),
      findsOneWidget,
    );
  });

  test('④ 接真库：记到「正餐」→ 餐饮这一行的已花跟着动', () async {
    final int ledger = await currentLedger();
    // 找一个有子分类的支出一级分类
    final List<Category> all = await Repo.category.all(ledger);
    final CategoryTree t = CategoryTree(all);
    final Category top = t.tops.firstWhere(
      (Category c) => c.type == TxnType.expense && t.childrenOf(c.id).isNotEmpty,
    );
    final Category child = t.childrenOf(top.id).first;

    await Repo.budget.setCategoryBudget(
      ledgerId: ledger,
      periodStart: october.from,
      categoryId: top.id!,
      amountCents: 100000,
    );
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 3850,
        date: const LocalDate(2026, 10, 10),
        periodStart: october.from,
        categoryId: child.id,
        accountId: await defaultAccountId(),
      ),
      cycleStartDay: 1,
    );

    final PlanStore plan = PlanStore();
    await plan.bind(ledgerId: ledger, period: october, cycleStartDay: 1);
    await plan.reload();

    final CategoryBudgetRow row = plan.categoryBudgetRows.firstWhere(
      (CategoryBudgetRow r) => r.category.id == top.id,
    );
    expect(
      row.spentCents,
      3850,
      reason: '记到「${child.name}」要算进「${top.name}」',
    );
    expect(row.budgetCents, 100000);
  });
}
