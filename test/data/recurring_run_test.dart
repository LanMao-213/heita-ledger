import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 补记算法：交易日期 = 应触发日、period_start 现算、60 期上限、end_date 停止、
/// 物理唯一（OR IGNORE）不重复。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<int> rule({
    required LocalDate next,
    RecurFreq freq = RecurFreq.daily,
    int interval = 1,
    LocalDate? end,
    int amount = 1000,
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
      ),
    );
  }

  Future<List<Txn>> recurringTxns() async => <Txn>[
    for (final Txn t in await Repo.txn.allOfLedger(await currentLedger()))
      if (t.recurringId != null) t,
  ];

  test('④ 5 天没开 → 补 5 条，交易日期 = 应触发日', () async {
    await rule(next: const LocalDate(2026, 10, 11));
    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: await currentLedger(),
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 16),
    );

    expect(added, 6, reason: '11..16 六天（含今天）');
    final List<String> dates = <String>[
      for (final Txn t in await recurringTxns()) t.date.iso,
    ]..sort();
    expect(dates.first, '2026-10-11');
    expect(dates.last, '2026-10-16');
  });

  test('④ period_start 按账单日**现算**（15 号账单日）', () async {
    await rule(next: const LocalDate(2026, 10, 14));
    await Repo.recurring.runDueRecurring(
      ledgerId: await currentLedger(),
      cycleStartDay: 15,
      today: const LocalDate(2026, 10, 16),
    );

    final List<Txn> txns = await recurringTxns();
    final Txn before = txns.firstWhere((Txn t) => t.date.iso == '2026-10-14');
    final Txn after = txns.firstWhere((Txn t) => t.date.iso == '2026-10-16');
    expect(before.periodStart!.iso, '2026-09-15', reason: '14 号还落在上一期');
    expect(after.periodStart!.iso, '2026-10-15');
  });

  test('④ 再调一次补 0 条（I11：next_run_date 已推进）', () async {
    await rule(next: const LocalDate(2026, 10, 15));
    final int first = await Repo.recurring.runDueRecurring(
      ledgerId: await currentLedger(),
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 16),
    );
    final int second = await Repo.recurring.runDueRecurring(
      ledgerId: await currentLedger(),
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 16),
    );

    expect(first, 2);
    expect(second, 0);
    expect((await recurringTxns()).length, 2);
  });

  test('④ 单条规则最多补 60 期（脏数据不写出十万行）', () async {
    await rule(next: const LocalDate(2026, 1, 1));
    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: await currentLedger(),
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 16),
    );
    expect(added, 60);
    expect((await recurringTxns()).length, 60);
  });

  test('④ end_date 到了就停止（不再往后补）', () async {
    await rule(
      next: const LocalDate(2026, 10, 13),
      end: const LocalDate(2026, 10, 15),
    );
    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: await currentLedger(),
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 20),
    );

    expect(added, 3, reason: '13/14/15 三天，16 号之后不再补');
    final List<String> dates = <String>[
      for (final Txn t in await recurringTxns()) t.date.iso,
    ]..sort();
    expect(dates.last, '2026-10-15');
  });

  test('⑤ 物理唯一：同 (recurring_id, date) 插不进去（OR IGNORE + 检查 rowid）', () async {
    final int ruleId = await rule(next: const LocalDate(2026, 10, 15));
    final int ledger = await currentLedger();
    await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 16),
    );
    final int afterFirst = (await recurringTxns()).length;
    expect(afterFirst, 2);

    // 把 next_run_date 倒回同一天，再跑一遍 → 一条都不该多
    final Recurring r = (await Repo.recurring.all(ledger)).single;
    expect(r.id, ruleId);
    await Repo.recurring.update(
      r.copyWith(nextRunDate: const LocalDate(2026, 10, 15)),
    );
    final int again = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 16),
    );

    expect(again, 0);
    expect((await recurringTxns()).length, afterFirst);
  });

  test('② 停用（enabled = 0）的规则不再补，但已生成的流水还在', () async {
    final int ruleId = await rule(next: const LocalDate(2026, 10, 15));
    final int ledger = await currentLedger();
    await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 15),
    );
    final int before = (await recurringTxns()).length;

    await Repo.recurring.setEnabled(ruleId, false);
    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 20),
    );

    expect(added, 0);
    expect((await recurringTxns()).length, before, reason: '停用不删历史流水');
  });
}
