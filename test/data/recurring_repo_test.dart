import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 周期账单：逐期补记、幂等、截止日、日期用「本应触发日」。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<int> rule({
    int interval = 1,
    RecurFreq freq = RecurFreq.monthly,
    LocalDate? next,
    LocalDate? end,
    String note = '',
    int amount = 30000,
    TxnType type = TxnType.expense,
  }) async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    return Repo.recurring.insert(
      Recurring(
        ledgerId: ledger,
        type: type,
        amountCents: amount,
        accountId: acc,
        note: note,
        freq: freq,
        interval: interval,
        nextRunDate: next ?? const LocalDate(2026, 10, 1),
        endDate: end,
      ),
    );
  }

  test('连续欠多期：逐期各插一条，日期用本应触发的日期', () async {
    final int ledger = await currentLedger();
    await rule(next: const LocalDate(2026, 10, 1));

    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 12, 15),
    );

    expect(added, 3, reason: '10-01 / 11-01 / 12-01');
    final List<Txn> txns = await Repo.txn.allOfLedger(ledger);
    expect(
      txns.map((Txn t) => t.date).toList(),
      <LocalDate>[
        const LocalDate(2026, 10, 1),
        const LocalDate(2026, 11, 1),
        const LocalDate(2026, 12, 1),
      ],
      reason: '不许用「补记当天」当交易日期',
    );
    expect(txns.every((Txn t) => t.isFromRecurring), isTrue);
  });

  test('幂等：同一天再跑一次不新增（物理唯一索引 + INSERT OR IGNORE）', () async {
    final int ledger = await currentLedger();
    await rule(next: const LocalDate(2026, 10, 1));

    final int first = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 15),
    );
    final int second = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 15),
    );

    expect(first, 1);
    expect(second, 0);
    expect((await Repo.txn.allOfLedger(ledger)).length, 1);
  });

  test('绕过闸一闸二：手工插过同 (recurring_id, date) 的行 → 不再重复插，且日期仍然推进',
      () async {
    final int ledger = await currentLedger();
    final int id = await rule(next: const LocalDate(2026, 10, 1));

    // 模拟「异常重启后 next_run_date 被拨回」：库里已经有 10-01 这笔补记
    await Repo.txn.insert(
      mkTxn(
        ledgerId: ledger,
        amountCents: 30000,
        date: const LocalDate(2026, 10, 1),
        periodStart: const LocalDate(2026, 10, 1),
        recurringId: id,
      ),
    );

    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 1),
    );

    expect(added, 0, reason: '被 ux_txn_recurring_date 挡住，不算新增');
    expect(
      (await Repo.txn.allOfLedger(ledger)).where((Txn t) => t.recurringId == id),
      hasLength(1),
    );
    final Recurring after = (await Repo.recurring.all(ledger)).single;
    expect(
      after.nextRunDate > const LocalDate(2026, 10, 1),
      isTrue,
      reason: '撞索引也要推进日期，否则永远卡在这一期',
    );
  });

  test('截止日之后不再补', () async {
    final int ledger = await currentLedger();
    await rule(
      next: const LocalDate(2026, 10, 1),
      end: const LocalDate(2026, 10, 31),
    );

    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 12, 31),
    );

    expect(added, 1, reason: '只有 10-01 在截止日之前');
  });

  test('备注为空时写「周期账单」', () async {
    final int ledger = await currentLedger();
    await rule(note: '   ');
    await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 1),
    );
    expect((await Repo.txn.allOfLedger(ledger)).single.note, '周期账单');
  });

  test('补记也维护余额（明细多一笔，余额必须同时动）', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    await rule(amount: 30000);

    await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 1),
    );

    expect(await balanceOf(acc), -30000);
    expect(await Repo.stats.balanceMatches(acc), isTrue);
  });

  test('weekly / daily 的推进不走月份', () async {
    final int ledger = await currentLedger();
    await rule(freq: RecurFreq.daily, interval: 1, next: const LocalDate(2026, 10, 29));

    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 11, 1),
    );
    expect(added, 4, reason: '10-29 / 10-30 / 10-31 / 11-01');
  });

  test('停用的规则不补；skipToToday 能跳过欠期', () async {
    final int ledger = await currentLedger();
    final int id = await rule(next: const LocalDate(2026, 1, 1));
    await Repo.recurring.setEnabled(id, false);
    expect(
      await Repo.recurring.runDueRecurring(
        ledgerId: ledger,
        cycleStartDay: 1,
        today: const LocalDate(2026, 12, 1),
      ),
      0,
    );

    await Repo.recurring.setEnabled(id, true);
    await Repo.recurring.skipToToday(id, const LocalDate(2026, 12, 1));
    final Recurring r = (await Repo.recurring.all(ledger)).single;
    expect(r.nextRunDate > const LocalDate(2026, 12, 1), isTrue);
  });

  test('补记沿用规则的类型与分类', () async {
    final int ledger = await currentLedger();
    final int top = await topCategoryId();
    await Repo.recurring.insert(
      Recurring(
        ledgerId: ledger,
        type: TxnType.income,
        amountCents: 800000,
        categoryId: top,
        nextRunDate: const LocalDate(2026, 10, 1),
        note: '工资',
      ),
    );

    await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 1),
    );

    final Txn t = (await Repo.txn.allOfLedger(ledger)).single;
    expect(t.type, TxnType.income);
    expect(t.categoryId, top);
    expect(t.amountCents, 800000);
  });
}
