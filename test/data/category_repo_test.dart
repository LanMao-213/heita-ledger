import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/category_repo.dart';
import 'package:heita_ledger/data/repo/repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 分类 repo：两级硬校验 + **I14 删除连带**。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  test('新增子分类：父级必须存在且是一级', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();

    final int child = await Repo.category.insert(
      Category(
        ledgerId: ledger,
        type: TxnType.expense,
        name: '夜宵',
        parentId: top,
      ),
    );

    final Category? c = (await Repo.category.tree(ledger)).byId(child);
    expect(c?.isChild, isTrue);
    expect(c?.parentId, top);
  });

  test('拒绝三级：父级本身是子分类 → ArgumentError', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();
    final int child = await childCategoryId(top);

    expect(
      () => Repo.category.insert(
        Category(
          ledgerId: ledger,
          type: TxnType.expense,
          name: '第三层',
          parentId: child,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('拒绝跨账本 / 跨类型的父子关系', () async {
    final int ledger = await currentLedger();
    final int other = (await Repo.ledger.insertLedger(name: '第二本')).id;
    final int top = await topCategoryId(); // 支出侧
    final int incomeTop = await topCategoryId(type: TxnType.income);

    expect(
      () => Repo.category.insert(
        Category(
          ledgerId: other,
          type: TxnType.expense,
          name: '串账本',
          parentId: top,
        ),
      ),
      throwsArgumentError,
    );

    expect(
      () => Repo.category.insert(
        Category(
          ledgerId: ledger,
          type: TxnType.income,
          name: '串类型',
          parentId: top,
        ),
      ),
      throwsArgumentError,
    );
    expect(incomeTop, isNot(top));
  });

  test('改名/停用：不允许改层级', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();
    final int child = await childCategoryId(top);
    final Category c = (await Repo.category.tree(ledger)).byId(child)!;

    await Repo.category.update(c.copyWith(name: '早午饭', archived: true));
    final Category after = (await Repo.category.tree(ledger)).byId(child)!;
    expect(after.name, '早午饭');
    expect(after.archived, isTrue);

    expect(
      () => Repo.category.update(c.copyWith(parentId: null)),
      throwsArgumentError,
      reason: '子分类不许升成一级',
    );
  });

  test('I14：删一级分类 → 流水 category_id 置 NULL 且条数不变、预算行被删、子分类一起走',
      () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final int top = await topCategoryId();
    final int child = await childCategoryId(top);
    final Period period = Period.cycleRange(const LocalDate(2026, 10, 16), 1);

    // 两笔挂在父级 + 子分类上
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, categoryId: top, accountId: acc),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 2000, categoryId: child, accountId: acc),
      cycleStartDay: 1,
    );
    // 一条与分类无关的流水（不能被牵连）
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 300, categoryId: null, accountId: acc),
      cycleStartDay: 1,
    );
    await Repo.budget.setTotalBudget(
      ledgerId: ledger,
      periodStart: period.from,
      amountCents: 500000,
    );
    await Repo.budget.setCategoryBudget(
      ledgerId: ledger,
      periodStart: period.from,
      categoryId: top,
      amountCents: 100000,
    );

    final int txnsBefore = (await Repo.txn.allOfLedger(ledger)).length;
    final int childCount = (await Repo.category.tree(ledger)).childrenOf(top).length;
    expect(childCount, greaterThan(0), reason: '这一级得有子分类，才能验证连带删除');

    final DeleteCategoryResult result = await Repo.category.delete(top);

    expect(result.detachedTxns, 2);
    expect(result.deletedBudgets, 1, reason: '只删指向它的那一行预算');
    expect(
      result.deletedCategories,
      1 + childCount,
      reason: '一级 + 它的全部子分类（种子里的餐饮有 6 个）',
    );

    final List<Txn> after = await Repo.txn.allOfLedger(ledger);
    expect(after.length, txnsBefore, reason: '绝不删交易（用户的历史账目）');
    expect(after.where((Txn t) => t.categoryId == null).length, 3);

    final List<Budget> budgets = await Repo.budget.categoryBudgets(ledger, period.from);
    expect(budgets, isEmpty);
    expect(
      await Repo.budget.totalBudget(ledger, period.from),
      500000,
      reason: '总预算不受影响',
    );
  });

  test('删子分类只影响它自己', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();
    final int child = await childCategoryId(top);
    final List<Category> before = await Repo.category.all(ledger);

    await Repo.category.delete(child);

    final List<Category> after = await Repo.category.all(ledger);
    expect(after.length, before.length - 1);
    expect(after.any((Category c) => c.id == child), isFalse);
    expect(after.any((Category c) => c.id == top), isTrue);
  });

  test('reorder：按数组下标重写 sort_order', () async {
    final int ledger = await currentLedger();
    final List<Category> tops = (await Repo.category.all(ledger))
        .where((Category c) => c.isTop && c.type == TxnType.expense)
        .toList();
    final List<int> reversed = tops.reversed
        .map((Category c) => c.id!)
        .toList();

    await Repo.category.reorder(reversed);

    final CategoryTree tree = await Repo.category.tree(ledger);
    expect(
      tree.topsOf(TxnType.expense).map((Category c) => c.id).toList(),
      reversed,
    );
  });

  test('ensureSeedCategories 幂等：已有分类的账本不再补种', () async {
    final int ledger = await currentLedger();
    final int before = await Repo.ledger.categoryCount(ledger);

    await Repo.category.ensureSeedCategories(ledger);
    expect(await Repo.ledger.categoryCount(ledger), before);

    // 全删之后再补 → 回到 88
    for (final Category c in await Repo.category.all(ledger)) {
      if (c.isTop) await Repo.category.delete(c.id!);
    }
    expect(await Repo.ledger.categoryCount(ledger), 0);
    await Repo.category.ensureSeedCategories(ledger);
    expect(await Repo.ledger.categoryCount(ledger), 88);
  });

  test('includeArchived: false 过滤停用分类', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();
    final Category c = (await Repo.category.tree(ledger)).byId(top)!;
    await Repo.category.update(c.copyWith(archived: true));

    final List<Category> visible = await Repo.category.all(
      ledger,
      includeArchived: false,
    );
    expect(visible.any((Category x) => x.id == top), isFalse);
    expect((await Repo.category.all(ledger)).any((Category x) => x.id == top), isTrue);
  });
}
