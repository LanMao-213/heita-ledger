import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/data/repo/txn_repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 流水 repo：keyset 分页 + 合计口径 + **I18 搜索规则**。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  final Period october = Period.cycleRange(const LocalDate(2026, 10, 16), 1);

  test('keyset 分页：50 条一页，第二页从游标继续且不重复', () async {
    final int ledger = await currentLedger();
    for (int i = 0; i < 60; i++) {
      await Repo.saveTxn(
        mkTxn(
          ledgerId: ledger,
          amountCents: 100 + i,
          date: LocalDate(2026, 10, 1 + (i % 28)),
        ),
        cycleStartDay: 1,
      );
    }

    final List<Txn> first = await Repo.txn.pageByPeriod(
      ledgerId: ledger,
      period: october,
    );
    expect(first.length, 50);

    final List<Txn> second = await Repo.txn.pageByPeriod(
      ledgerId: ledger,
      period: october,
      after: TxnCursor(date: first.last.date, id: first.last.id!),
    );
    expect(second.length, 10);

    final Set<int> ids = <int>{
      ...first.map((Txn t) => t.id!),
      ...second.map((Txn t) => t.id!),
    };
    expect(ids.length, 60, reason: '两页不重叠');
    // 排序键单调：date DESC, id DESC
    for (int i = 1; i < first.length; i++) {
      final bool ok =
          first[i - 1].date > first[i].date ||
          (first[i - 1].date == first[i].date && first[i - 1].id! > first[i].id!);
      expect(ok, isTrue, reason: 'keyset 排序必须是 date DESC, id DESC');
    }
  });

  test('当期合计：交叉归集 + 排除借贷', () async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 3000),
      cycleStartDay: 1,
    );
    // 支出里的负数 → 计入收入侧
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: -2000),
      cycleStartDay: 1,
    );
    // 借贷流水 → 两侧都不算，但笔数要算
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 50000, debtId: 1),
      cycleStartDay: 1,
    );

    final RangeTotals totals = await Repo.txn.totalsInPeriod(
      ledgerId: ledger,
      period: october,
    );
    expect(totals.expenseCents, 3000);
    expect(totals.incomeCents, 2000);
    expect(totals.count, 3);
  });

  test('I18-① 一位数不当金额匹配（「5」几乎能匹配全部，噪音盖掉真命中）', () async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 500, note: '早饭'),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 12345, note: '晚饭'),
      cycleStartDay: 1,
    );

    final TxnSearchResult byNote = await Repo.txn.search(
      ledgerId: ledger,
      query: const TxnQuery(keyword: '早饭'),
    );
    expect(byNote.items.length, 1);

    // 「5」不能当金额：只应命中备注/分类里真含「5」的（这里没有）
    final TxnSearchResult five = await Repo.txn.search(
      ledgerId: ledger,
      query: const TxnQuery(keyword: '5'),
    );
    expect(five.items, isEmpty, reason: '一位数不参与金额匹配，也不该命中全部');
  });

  test('I18-② 「50%」不命中全部（LIKE 通配符必须转义）', () async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 100, note: '打折 50% 入手'),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 200, note: '午饭'),
      cycleStartDay: 1,
    );

    final TxnSearchResult result = await Repo.txn.search(
      ledgerId: ledger,
      query: const TxnQuery(keyword: '50%'),
    );
    expect(result.items.length, 1);
    expect(result.items.single.note, contains('50%'));
  });

  test('I18-③ 「38.5」命中 38.50 / 138.50 / 3.85（包含关系，不是精确匹配）', () async {
    final int ledger = await currentLedger();
    for (final int cents in <int>[3850, 13850, 385, 9999]) {
      await Repo.saveTxn(
        mkTxn(ledgerId: ledger, amountCents: cents, note: '无关键词$cents'),
        cycleStartDay: 1,
      );
    }

    final TxnSearchResult result = await Repo.txn.search(
      ledgerId: ledger,
      query: const TxnQuery(keyword: '38.5'),
    );
    final Set<int> hit = result.items.map((Txn t) => t.amountCents).toSet();
    expect(hit, <int>{3850, 13850, 385});
    expect(result.totals.count, 3, reason: '合计不受 500 条上限影响');
  });

  test('搜索覆盖详情字段、分类名（含父级）与账户名', () async {
    final int ledger = await currentLedger();
    final int acc = await Repo.account.insert(const Account(name: '招商银行'));
    final int top = await topCategoryId();

    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 100,
        person: '张三',
        accountId: acc,
        categoryId: top,
      ),
      cycleStartDay: 1,
    );

    expect(
      (await Repo.txn.search(ledgerId: ledger, query: const TxnQuery(keyword: '张三'))).items.length,
      1,
    );
    expect(
      (await Repo.txn.search(ledgerId: ledger, query: const TxnQuery(keyword: '招商'))).items.length,
      1,
      reason: '账户名参与搜索',
    );
    final CategoryTree tree = await Repo.category.tree(ledger);
    final String topName = tree.byId(top)!.name;
    expect(
      (await Repo.txn.search(ledgerId: ledger, query: TxnQuery(keyword: topName))).items.length,
      1,
      reason: '分类名（含父级）参与搜索',
    );
  });

  test('分类筛选连带子分类；账户筛选两端都算', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final int other = await Repo.account.insert(const Account(name: '支付宝'));
    final int top = await topCategoryId();
    final int child = await childCategoryId(top);

    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 100, categoryId: child, accountId: acc),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 200, categoryId: null, accountId: other),
      cycleStartDay: 1,
    );

    final TxnSearchResult byTop = await Repo.txn.search(
      ledgerId: ledger,
      query: TxnQuery(categoryId: top),
    );
    expect(byTop.items.length, 1, reason: '选一级时子分类的记录也要算进来');

    final TxnSearchResult byAccount = await Repo.txn.search(
      ledgerId: ledger,
      query: TxnQuery(accountId: acc),
    );
    expect(byAccount.items.length, 1);
  });

  test('截断标志：多查一条判定，合计仍为全量', () async {
    final int ledger = await currentLedger();
    for (int i = 0; i < 3; i++) {
      await Repo.saveTxn(
        mkTxn(ledgerId: ledger, amountCents: 100 + i, note: '测试'),
        cycleStartDay: 1,
      );
    }

    final TxnSearchResult result = await Repo.txn.search(
      ledgerId: ledger,
      query: const TxnQuery(keyword: '测试'),
      limit: 2,
    );
    expect(result.items.length, 2);
    expect(result.truncated, isTrue);
    expect(result.totals.count, 3, reason: '合计是独立聚合，不受列表上限影响');
  });

  test('空条件 == 未筛选（isEmpty 为真）', () {
    expect(const TxnQuery().isEmpty, isTrue);
    expect(const TxnQuery(keyword: '   ').isEmpty, isTrue);
    expect(const TxnQuery(type: TxnType.expense).isEmpty, isFalse);
  });

  test('byDebt 取回本金与还款，供 RepaidIndex 现算', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final int debtId = await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: 50000,
        accountId: acc,
        date: const LocalDate(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
      ),
      cycleStartDay: 1,
    );
    await Repo.repayDebt(
      target: (await Repo.debt.byId(debtId))!,
      amountCents: 10000,
      cycleStartDay: 1,
      date: const LocalDate(2026, 10, 5),
    );

    final List<Txn> rows = await Repo.txn.byDebt(debtId);
    expect(rows.length, 2);
    final RepaidIndex index = RepaidIndex.fromTxns(rows);
    expect(index.repaidForId(debtId, receivable: true), 10000);
  });
}
