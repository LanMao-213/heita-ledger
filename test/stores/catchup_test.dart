import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/db/seeds.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/stores/plan_store.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 补记的三道闸：闸一按账本、闸二在飞复用、闸三物理唯一；外加「手动补记绕过闸一」。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  const LocalDate today = LocalDate(2026, 10, 16);

  Future<PlanStore> bound({int? ledgerId}) async {
    final int id = ledgerId ?? await currentLedger();
    final PlanStore plan = PlanStore();
    await plan.bind(
      ledgerId: id,
      period: Period.cycleRange(today, 1),
      cycleStartDay: 1,
    );
    await plan.reload();
    return plan;
  }

  /// 建一条「每天」的规则，下次触发日 = [next]，方便一次补好几期。
  Future<int> rule({
    required LocalDate next,
    int amount = 1000,
    LocalDate? end,
    bool enabled = true,
    int? ledgerId,
  }) async {
    return Repo.recurring.insert(
      Recurring(
        ledgerId: ledgerId ?? await currentLedger(),
        type: TxnType.expense,
        amountCents: amount,
        categoryId: await topCategoryId(),
        accountId: await defaultAccountId(),
        note: '房租',
        freq: RecurFreq.daily,
        interval: 1,
        nextRunDate: next,
        endDate: end,
        enabled: enabled,
      ),
    );
  }

  Future<int> txnCount() async =>
      (await Repo.txn.allOfLedger(await currentLedger())).length;

  test('⑤ 闸一：同一天第二次 catchUp 直接 0（不再扫库）', () async {
    await rule(next: const LocalDate(2026, 10, 14));
    final PlanStore plan = await bound();

    expect(await plan.catchUp(today: today), 3, reason: '14/15/16 三天');
    expect(
      await plan.catchUp(today: today),
      0,
      reason: '闸一：这本账今天扫过了',
    );
  });

  test('⑤ 闸一按**账本**记：换一本账各自扫一次', () async {
    final int ledgerA = await currentLedger();
    await rule(next: const LocalDate(2026, 10, 15));

    final PlanStore plan = await bound();
    expect(await plan.catchUp(today: today), 2);

    // 第二本账（直接插一条记录模拟另一本账的规则）
    final ({int id, SeedResult seed}) created =
        await Repo.ledger.insertLedger(name: '第二本');
    final int ledgerB = created.id;
    await rule(next: const LocalDate(2026, 10, 15), ledgerId: ledgerB);

    await plan.bind(
      ledgerId: ledgerB,
      period: Period.cycleRange(today, 1),
      cycleStartDay: 1,
    );
    expect(
      await plan.catchUp(today: today),
      2,
      reason: '闸一的键是账本，不是全局时间戳（否则第二本账永远补不上）',
    );
    expect(ledgerA, isNot(ledgerB));
  });

  test('⑤ 闸二：同时调两次只跑一趟（在飞 Future 复用）', () async {
    await rule(next: const LocalDate(2026, 10, 14));
    final PlanStore plan = await bound();
    final int before = await txnCount();

    final List<int> results = await Future.wait(<Future<int>>[
      plan.catchUp(today: today),
      plan.catchUp(today: today),
    ]);

    // 两次拿到的其实是**同一个 Future**，所以两个结果都是 3（不是 3+3=6）
    expect(results, <int>[3, 3], reason: '闸二：同一次补记结果被复用');
    expect(await txnCount(), before + 3, reason: '库里只多了 3 笔');
  });

  test('⑤ 闸三：人为放开闸一后重跑，物理唯一索引仍然挡住', () async {
    await rule(next: const LocalDate(2026, 10, 14));
    final PlanStore plan = await bound();
    final int before = await txnCount();
    expect(await plan.catchUp(today: today), 3);

    // 把规则的下次日期倒回去，并清掉闸一 —— 模拟「两闸都失效」
    final List<Recurring> rules = await Repo.recurring.all(
      await currentLedger(),
    );
    await Repo.recurring.update(
      rules.single.copyWith(nextRunDate: const LocalDate(2026, 10, 14)),
    );
    plan.resetScanCursor();

    final int again = await plan.catchUp(today: today);
    expect(again, 0, reason: '闸三：同 (recurring_id, date) 插不进去');
    expect(await txnCount(), before + 3, reason: '一条都没多');
  });

  test('⑤ **手动补记绕过闸一**：自动补记挡掉之后手动还能补上新到期的', () async {
    await rule(next: const LocalDate(2026, 10, 16));
    final PlanStore plan = await bound();
    expect(await plan.catchUp(today: today), 1);

    // 补完之后再加一条已到期的规则：闸一会把自动补记挡掉
    await rule(next: const LocalDate(2026, 10, 15), amount: 2000);
    expect(
      await plan.catchUp(today: today),
      0,
      reason: '闸一挡掉（这本账今天扫过了）',
    );

    expect(
      await plan.manualCatchUp(today: today),
      2,
      reason: '手动补记是明确指令，必须绕开闸一，否则按钮「按了没反应」',
    );
  });

  test('⑤ 并发调用 manualCatchUp 也只跑一趟（闸二没被绕过）', () async {
    await rule(next: const LocalDate(2026, 10, 14));
    final PlanStore plan = await bound();
    final int before = await txnCount();

    final List<int> results = await Future.wait(<Future<int>>[
      plan.manualCatchUp(today: today),
      plan.manualCatchUp(today: today),
    ]);

    expect(results, <int>[3, 3]);
    expect(await txnCount(), before + 3);
  });

  test('⑥ resetScanCursor 之后闸一被清空（wipe / 恢复路径要它）', () async {
    await rule(next: const LocalDate(2026, 10, 16));
    final PlanStore plan = await bound();
    expect(await plan.catchUp(today: today), 1);
    expect(await plan.catchUp(today: today), 0, reason: '闸一在挡');

    plan.resetScanCursor();

    // 闸一没了 → 会真的再扫一遍（但闸三保证不加笔数）
    expect(await plan.catchUp(today: today), 0);
    expect(await txnCount(), isPositive);
  });

  test('⑦ 回前台：日期与账本都没变 → 0 次补记（闸一直接返回）', () async {
    await rule(next: const LocalDate(2026, 10, 16));
    final PlanStore plan = await bound();
    expect(await plan.catchUp(today: today), 1);

    expect(
      await plan.catchUpOnResume(today: today),
      0,
      reason: '同一进程同一天：闸一在内存里就挡住了，一次查询都不发',
    );
  });

  test('④ 补记的交易日期是**应触发日**，不是补记当天', () async {
    await rule(next: const LocalDate(2026, 10, 13));
    final PlanStore plan = await bound();
    expect(await plan.catchUp(today: today), 4, reason: '13/14/15/16');

    final List<Txn> txns = await Repo.txn.allOfLedger(await currentLedger());
    final List<String> dates = <String>[
      for (final Txn t in txns)
        if (t.recurringId != null) t.date.iso,
    ]..sort();
    expect(dates, <String>[
      '2026-10-13',
      '2026-10-14',
      '2026-10-15',
      '2026-10-16',
    ]);
  });
}
