import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/db/schema.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/account_repo.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:sqflite/sqflite.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 账户 repo：**I1 余额恒等**（六种写路径各一条）+ 改属性不碰余额。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  /// 恒等式：`balance == opening + Σ流水影响`（转账两端各自算）。
  Future<void> expectIdentity(int accountId) async {
    expect(
      await Repo.stats.balanceMatches(accountId),
      isTrue,
      reason: '账户 $accountId 的余额与恒等式不一致',
    );
  }

  Future<void> expectAllIdentities() async {
    for (final Account a in await Repo.account.list()) {
      await expectIdentity(a.id!);
    }
  }

  test('I1-① 插入流水：支出 −金额、收入 +金额', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();

    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, accountId: acc),
      cycleStartDay: 1,
    );
    expect(await balanceOf(acc), -1000);

    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 800,
        type: TxnType.income,
        accountId: acc,
      ),
      cycleStartDay: 1,
    );
    expect(await balanceOf(acc), -200);
    await expectIdentity(acc);
  });

  test('I1-② 删除流水：余额回到原值', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final Txn saved = await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 3850, accountId: acc),
      cycleStartDay: 1,
    );
    expect(await balanceOf(acc), -3850);

    await Repo.deleteTxn(saved);

    expect(await balanceOf(acc), 0);
    await expectIdentity(acc);
  });

  test('I1-③ 修改流水：先回滚旧值再应用新值（含换账户）', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final int second = await Repo.account.insert(const Account(name: '微信'));

    final Txn saved = await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, accountId: acc),
      cycleStartDay: 1,
    );
    await Repo.updateTxn(
      saved,
      saved.copyWith(amountCents: 3000, accountId: second),
      cycleStartDay: 1,
    );

    expect(await balanceOf(acc), 0, reason: '旧账户要回滚干净');
    expect(await balanceOf(second), -3000);
    await expectAllIdentities();
  });

  test('I1-④ 还款：借出扣款、收回加回', () async {
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
    expect(await balanceOf(acc), -50000, reason: '借出：钱真出去了');

    final Debt after = await Repo.repayDebt(
      target: (await Repo.debt.byId(debtId))!,
      amountCents: 20000,
      cycleStartDay: 1,
      date: const LocalDate(2026, 10, 10),
    );

    expect(await balanceOf(acc), -30000);
    expect(after.isClosed, isFalse);
    await expectAllIdentities();
  });

  test('I1-⑤ 补记周期账单：流水与余额一起变', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();

    await Repo.recurring.insert(
      Recurring(
        ledgerId: ledger,
        type: TxnType.expense,
        amountCents: 30000,
        accountId: acc,
        nextRunDate: const LocalDate(2026, 10, 1),
        note: '房租',
      ),
    );

    final int added = await Repo.recurring.runDueRecurring(
      ledgerId: ledger,
      cycleStartDay: 1,
      today: const LocalDate(2026, 10, 1),
    );

    expect(added, 1);
    expect(await balanceOf(acc), -30000, reason: '明细多了一笔，余额必须同时动');
    await expectAllIdentities();
  });

  test('I1-⑥ 导入：replaceAll 后同一事务内重算余额', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 5000, accountId: acc),
      cycleStartDay: 1,
    );

    // 伪造一份「余额列是旧快照」的备份
    final Map<String, List<Map<String, Object?>>> payload =
        <String, List<Map<String, Object?>>>{
          Tables.setting: <Map<String, Object?>>[
            <String, Object?>{SettingCols.k: 'current_ledger_id', SettingCols.v: '$ledger'},
          ],
          Tables.ledger: <Map<String, Object?>>[
            <String, Object?>{
              LedgerCols.id: ledger,
              LedgerCols.name: '我的账本',
              LedgerCols.icon: 'book',
              LedgerCols.sortOrder: 0,
              LedgerCols.createdAt: '2026-10-01T00:00:00.000',
            },
          ],
          Tables.account: <Map<String, Object?>>[
            <String, Object?>{
              AccountCols.id: acc,
              AccountCols.name: '现金',
              AccountCols.kind: 'cash',
              AccountCols.openingCents: 0,
              AccountCols.balanceCents: 999999, // 旧快照，故意不对
              AccountCols.includeInTotal: 1,
              AccountCols.sortOrder: 0,
            },
          ],
          Tables.txn: <Map<String, Object?>>[
            <String, Object?>{
              TxnCols.ledgerId: ledger,
              TxnCols.type: 'expense',
              TxnCols.amountCents: 5000,
              TxnCols.accountId: acc,
              TxnCols.date: '2026-10-16',
              TxnCols.periodStart: '2026-10-01',
              TxnCols.note: '',
              TxnCols.createdAt: '2026-10-16T09:00:00.000',
            },
          ],
        };

    await Repo.importPayload(payload);

    expect(await balanceOf(acc), -5000, reason: '按流水重算，不信任备份里的余额');
    await expectIdentity(acc);
  });

  test('改账户属性（名称/类型/计入净资产）→ 两列余额完全不变', () async {
    final int acc = await defaultAccountId();
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 174400, accountId: acc),
      cycleStartDay: 1,
    );

    final Account before = (await Repo.account.byId(acc))!;

    await Repo.account.updateAttributes(
      before.copyWith(name: '微信钱包', kind: AccountKind.wechat, includeInTotal: false),
    );

    final Account after = (await Repo.account.byId(acc))!;
    expect(after.name, '微信钱包');
    expect(after.kind, AccountKind.wechat);
    expect(after.includeInTotal, isFalse);
    expect(after.openingCents, before.openingCents, reason: '改属性不许碰期初');
    expect(after.balanceCents, before.balanceCents, reason: '改属性不许碰余额');
  });

  test('新建账户：没有流水时 balance 强制对齐 opening', () async {
    final int id = await Repo.account.insert(
      const Account(name: '招商', openingCents: 500000, balanceCents: 1),
    );
    final Account a = (await Repo.account.byId(id))!;
    expect(a.balanceCents, 500000);
    expect(a.openingCents, 500000);
  });

  test('手填当前余额：反算 opening，balance 对齐，恒等式仍成立', () async {
    final int acc = await defaultAccountId();
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 174400, accountId: acc),
      cycleStartDay: 1,
    );

    await Repo.account.setActualBalance(acc, 100000);

    final Account a = (await Repo.account.byId(acc))!;
    expect(a.balanceCents, 100000);
    expect(a.openingCents, 274400, reason: 'opening = 手填 − 流水(−1744)');
    await expectIdentity(acc);
  });

  test('删账户只删行，流水变悬空引用（不置 NULL）', () async {
    final int acc = await Repo.account.insert(const Account(name: '临时'));
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 100, accountId: acc),
      cycleStartDay: 1,
    );

    await Repo.account.delete(acc);

    expect(await Repo.account.byId(acc), isNull);
    final List<Txn> all = await Repo.txn.allOfLedger(ledger);
    expect(all.single.accountId, acc, reason: '软关联：account_id 保留');
  });

  test('重算余额只改 balance，不改 opening', () async {
    final int acc = await defaultAccountId();
    final int ledger = await currentLedger();
    final int openingBefore = (await Repo.account.byId(acc))!.openingCents;
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 500, accountId: acc),
      cycleStartDay: 1,
    );

    // 人为把余额改坏（模拟「漏了一次增量」的原版病）
    final Database db = await Db.open();
    await db.update(
      Tables.account,
      <String, Object?>{AccountCols.balanceCents: 999999},
      where: '${AccountCols.id} = ?',
      whereArgs: <Object?>[acc],
    );

    final int changed = await Repo.account.recalcBalances();
    expect(changed, 1);

    final Account after = (await Repo.account.byId(acc))!;
    expect(after.balanceCents, -500, reason: '按流水重算回来了');
    expect(after.openingCents, openingBefore, reason: 'opening 是基准，重算不许动它');
  });

  test('转账：转出 −、转入 +，两端各自满足恒等式', () async {
    final int ledger = await currentLedger();
    final int from = await defaultAccountId();
    final int to = await Repo.account.insert(const Account(name: '支付宝'));

    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 20000,
        type: TxnType.transfer,
        accountId: from,
      ).copyWith(toAccountId: to),
      cycleStartDay: 1,
    );

    expect(await balanceOf(from), -20000);
    expect(await balanceOf(to), 20000);
    await expectAllIdentities();
  });

  test('转账的余额增量成对且反向可回滚', () async {
    const LocalDate d = LocalDate(2026, 10, 1);
    final Txn t = Txn(
      type: TxnType.transfer,
      amountCents: 5000,
      accountId: 1,
      toAccountId: 2,
      date: d,
      periodStart: d,
      createdAt: DateTime(2026, 10, 1),
    );
    final List<({int accountId, int delta})> forward = AccountRepo.deltasOf(t);
    final List<({int accountId, int delta})> back = AccountRepo.deltasOf(
      t,
      reverse: true,
    );
    expect(forward.map((e) => e.delta), <int>[-5000, 5000]);
    expect(back.map((e) => e.delta), <int>[5000, -5000]);
  });
}
