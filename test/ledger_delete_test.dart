// 删除账本的自检。
//
// 这条链路原来只有一句 `DELETE FROM ledger`：`txn` / `category` / `debt` 有
// 外键会级联，但 `budget` / `recurring` / `txn_template` 的 DDL 里**没有**
// 指向 ledger 的外键 —— 删完账本，这三张表里留下的是永远查不到归属、也永远
// 清不掉的孤儿行。它们不会让任何界面报错，只会在「换机恢复」和「体检」里
// 慢慢变成解释不了的数字。
//
// 第二条链更隐蔽：`account` 是**全局表**（没有 `ledger_id`），被删账本的流水
// 花的是共用账户上的钱。只删流水不冲余额，账户就永久少一笔，而「数据体检」
// 只会说「余额与流水不一致」—— 没人能从这句话看出起因是删了一本账。
// 所以这里每条用例都**带 accountId** 造流水，并直接断言 `Integrity.check()`
// 干净（第一版的夹具没传 accountId，把整条余额链路绕开了，QA 正是从这里漏过去的）。
//
// 同时钉住一条反面规则：`saving_goal` 的 schema 里**没有 ledger_id**，
// 储蓄目标是全局的 —— 删账本不能顺手把目标删了。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/integrity.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_ledger_delete.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<int> _balanceOf(int accountId) async {
  final accounts = await Repo.listAccounts();
  return accounts.firstWhere((a) => a.id == accountId).balanceCents;
}

/// 在 [ledgerId] 名下造齐「五张子表各一行」，流水挂在 [accountId] 上。
///
/// `accountId` 是必填的：不挂账户的流水**碰不到余额链路**，
/// 用它写的用例看起来在测删账本，其实把最危险的那一半绕开了。
Future<void> _seedLedgerData(int ledgerId, int accountId) async {
  final cats = await Repo.listCategories(ledgerId, type: TxnType.expense);
  await Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.expense,
      amountCents: 12345,
      date: '2026-10-01',
      categoryId: cats.isEmpty ? null : cats.first.id,
      accountId: accountId,
    ),
  );
  await Repo.setBudget(
    ledgerId: ledgerId,
    periodStart: '2026-10-01',
    amountCents: 100000,
  );
  await Repo.insertRecurring(
    RecurringRule(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.expense,
      amountCents: 3000,
      // 远未来：保证 `runDueRecurring` 不会在切账本时把它补记进来
      nextRunDate: '2099-01-01',
      categoryId: cats.isEmpty ? null : cats.first.id,
    ),
  );
  await Repo.insertTemplate(
    TxnTemplate(
      id: 0,
      ledgerId: ledgerId,
      name: '测试模板',
      type: TxnType.expense,
      amountCents: 1000,
    ),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  test('删账本：流水 / 预算 / 周期账单 / 模板 / 分类一起删，不留孤儿', () async {
    await Store.i.boot();
    // 共用账户：期初 = 余额 = ¥1,000.00（`Repo.insertAccount` 强制两者一致）
    final shared = await Repo.insertAccount(
      const Account(id: 0, name: '共用钱包', balanceCents: 100000),
    );
    final other = await Repo.insertAccount(
      const Account(id: 0, name: '另一本用的', balanceCents: 50000),
    );

    final doomed = await Repo.insertLedger(Ledger(id: 0, name: '装修账本'));
    await _seedLedgerData(doomed, shared);
    // 另一本账的数据必须原样活着
    final keep = Store.i.ledgerId;
    await _seedLedgerData(keep, other);
    final keepTxnsBefore = await Repo.rangeListTxns(
      ledgerId: keep,
      from: '2026-10-01',
      to: '2026-10-31',
    );

    // 两笔各 ¥123.45 已经进了余额
    expect(await _balanceOf(shared), 100000 - 12345);
    expect(await _balanceOf(other), 50000 - 12345);

    await Repo.deleteLedger(doomed);

    expect(
      await Repo.rangeListTxns(
        ledgerId: doomed,
        from: '2000-01-01',
        to: '2099-12-31',
        basis: DateBasis.date,
      ),
      isEmpty,
      reason: '账本没了，它的流水不能留在库里',
    );
    expect(
      await Repo.listBudgets(doomed, '2026-10-01'),
      isEmpty,
      reason: 'budget 没有外键，只有显式删才不会留下孤儿行',
    );
    expect(
      await Repo.listRecurring(doomed),
      isEmpty,
      reason: 'recurring 没有外键；留下的孤儿会被下一次补记扫到',
    );
    expect(
      await Repo.listTemplates(doomed),
      isEmpty,
      reason: 'txn_template 没有外键',
    );
    expect(await Repo.listCategories(doomed), isEmpty);
    expect(
      await Repo.listLedgers(),
      hasLength(1),
      reason: '只剩原来那一本',
    );

    // ---- 余额回滚：删掉的流水等于没发生过 ----
    expect(
      await _balanceOf(shared),
      100000,
      reason: 'account 是全局表：不冲回余额，账户就永久少一笔',
    );
    expect(
      await _balanceOf(other),
      50000 - 12345,
      reason: '没被删的那本账，余额一分不动',
    );
    final report = await Integrity.check();
    expect(
      report.ok,
      isTrue,
      reason:
          '删完账本必须立刻通过数据体检：'
          '${report.issues.map((i) => i.detail).join(' / ')}',
    );

    // 另一本账不受影响
    final keepTxnsAfter = await Repo.rangeListTxns(
      ledgerId: keep,
      from: '2026-10-01',
      to: '2026-10-31',
    );
    expect(keepTxnsAfter.length, keepTxnsBefore.length);
    expect(await Repo.listTemplates(keep), hasLength(1));
    expect(await Repo.listRecurring(keep), hasLength(1));
  });

  test('删账本：转账两端都回滚（转入端只出现在 to_account_id 上）', () async {
    await Store.i.boot();
    final from = await Repo.insertAccount(
      const Account(id: 0, name: '转出', balanceCents: 100000),
    );
    final to = await Repo.insertAccount(
      const Account(id: 0, name: '转入', balanceCents: 0),
    );
    final doomed = await Repo.insertLedger(Ledger(id: 0, name: '过路账本'));
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: doomed,
        type: TxnType.transfer,
        amountCents: 40000,
        date: '2026-10-01',
        accountId: from,
        toAccountId: to,
      ),
    );
    expect(await _balanceOf(from), 60000);
    expect(await _balanceOf(to), 40000);

    await Repo.deleteLedger(doomed);

    expect(
      await _balanceOf(from),
      100000,
      reason: '转出端回到期初 —— 少回这一头，用户会以为钱转丢了',
    );
    expect(
      await _balanceOf(to),
      0,
      reason: '转入端也要回滚：漏收这一头就是「凭空多钱」',
    );
    expect((await Integrity.check()).ok, isTrue);
  });

  test('储蓄目标不属于任何账本：删账本不碰它', () async {
    await Store.i.boot();
    await Repo.insertGoal(
      const SavingGoal(id: 0, name: '旅行基金', targetCents: 2000000),
    );
    final doomed = await Repo.insertLedger(Ledger(id: 0, name: '临时账本'));

    await Repo.deleteLedger(doomed);

    expect(
      await Repo.listGoals(),
      hasLength(1),
      reason: 'saving_goal 没有 ledger_id，删账本不该动它',
    );
  });

  test('删的是当前账本：自动切到剩余的第一本并重载', () async {
    await Store.i.boot();
    final s = Store.i;
    final acc = s.accounts.first.id;
    final extra = await Repo.insertLedger(Ledger(id: 0, name: '第二本'));
    await s.switchLedger(extra);
    await _seedLedgerData(extra, acc);
    expect(s.ledgerId, extra);

    await s.deleteLedger(extra);

    expect(s.ledgers, hasLength(1));
    expect(
      s.ledgerId,
      isNot(extra),
      reason: '停在一个已删的 ledger_id 上，明细与分类会全部查空',
    );
    expect(
      s.ledgerId,
      await Repo.currentLedgerId(),
      reason: '设置里的 current_ledger_id 要跟着改，否则下次启动又会指向死账本',
    );
    expect(s.txns, isEmpty, reason: '切过去之后投影必须重载');
  });
}
