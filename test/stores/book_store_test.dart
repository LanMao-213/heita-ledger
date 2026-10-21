import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/data/repo/txn_repo.dart';
import 'package:heita_ledger/stores/book_store.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// BookStore：**通知合并（I12）** + 游标搬运 + 分页 + 筛选。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<BookStore> freshStore() async {
    final BookStore store = BookStore();
    await store.bind(
      ledgerId: await currentLedger(),
      cycleStartDay: 1,
    );
    return store;
  }

  test('afterTxnInserted：整段只发 1 次通知（I12）', () async {
    final BookStore store = await freshStore();
    final int ledger = await currentLedger();
    final Txn saved = await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000),
      cycleStartDay: 1,
    );

    int notified = 0;
    store.addListener(() => notified++);
    await store.afterTxnInserted(saved.periodStart!);

    expect(notified, 1, reason: '记一笔的正常路径必须是 1 次重建');
    expect(store.totals.expenseCents, 1000);
    expect(store.items, hasLength(1));
  });

  test('afterTxnInserted：跨期时把游标搬到那一期', () async {
    final BookStore store = await freshStore();
    final int ledger = await currentLedger();

    // 游标停在 2026-08（今天所在期是 2026-10）
    store.moveCycle(-2);
    final Period august = store.cycle;
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 500,
        date: const LocalDate(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );
    final Txn saved = await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 700, date: const LocalDate(2026, 10, 6)),
      cycleStartDay: 1,
    );

    await store.afterTxnInserted(saved.periodStart!);

    expect(store.cycle.from, const LocalDate(2026, 10, 1));
    expect(store.cycle.from == august.from, isFalse);
    expect(store.items, hasLength(2));
  });

  test('afterTxnInserted 会清掉筛选（不然笔在筛选结果里看不见）', () async {
    final BookStore store = await freshStore();
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 100, note: '早饭'),
      cycleStartDay: 1,
    );
    await store.applyFilter(const TxnQuery(keyword: '早饭'));
    expect(store.isFiltering, isTrue);

    final Txn saved = await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 200, note: '午饭'),
      cycleStartDay: 1,
    );
    await store.afterTxnInserted(saved.periodStart!);

    expect(store.isFiltering, isFalse);
    expect(store.searchResult, isNull);
  });

  test('afterTxnChange 不搬游标（用户正看着那一行）', () async {
    final BookStore store = await freshStore();
    final int ledger = await currentLedger();
    final Txn saved = await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 100,
        date: const LocalDate(2026, 10, 5),
      ),
      cycleStartDay: 1,
    );
    store.moveCycle(-1);
    final Period before = store.cycle;

    await store.afterTxnChange();

    expect(store.cycle, before, reason: '改账不跳期');
    expect(saved.id, isNotNull);
  });

  test('翻期：往前可以，往后不许翻到今天之后的期', () async {
    final BookStore store = await freshStore();
    final Period today = store.cycle;

    store.moveCycle(-1);
    expect(store.cycle.from < today.from, isTrue);

    store.moveCycle(1);
    expect(store.cycle.from, today.from);

    store.moveCycle(1); // 想翻到未来 → 被挡
    expect(store.cycle.from, today.from, reason: '未来期只会有 0.00');
  });

  test('loadMore：按 keyset 追加，不重复', () async {
    final BookStore store = await freshStore();
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
    await store.reloadCycle();
    expect(store.items.length, 50);
    expect(store.hasMore, isTrue);

    await store.loadMore();

    expect(store.items.length, 60);
    expect(store.items.map((Txn t) => t.id).toSet().length, 60);
    expect(store.hasMore, isFalse);
  });

  test('applyFilter：跨全部历史、合计为全量、清筛选后回到本期', () async {
    final BookStore store = await freshStore();
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 100,
        date: const LocalDate(2026, 3, 3),
        note: '去年',
      ),
      cycleStartDay: 1,
    );

    await store.applyFilter(const TxnQuery(keyword: '去年'));
    expect(store.isFiltering, isTrue);
    expect(store.items, hasLength(1), reason: '筛选要跨全部历史，不能被本期挡住');

    store.resetFilter();
    await store.reloadCycle();
    expect(store.items, isEmpty, reason: '回到本期后那条 3 月的账不在列表里');
  });

  test('reloadCycle 把两侧合计填好', () async {
    final BookStore store = await freshStore();
    final int ledger = await currentLedger();
    await Repo.saveTxn(mkTxn(ledgerId: ledger, amountCents: 3000), cycleStartDay: 1);
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 8000, type: TxnType.income),
      cycleStartDay: 1,
    );

    await store.reloadCycle();

    expect(store.totals.expenseCents, 3000);
    expect(store.totals.incomeCents, 8000);
    expect(store.totals.netCents, 5000);
  });

  test('首帧判定：isCold 只在「没加载过且空」时为真', () async {
    final BookStore store = await freshStore();
    expect(store.isCold, isTrue);
    await store.reloadCycle();
    expect(store.isCold, isFalse);
  });
}
