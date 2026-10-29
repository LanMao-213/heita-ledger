// 删除账本的自检。
//
// 这条链路原来只有一句 `DELETE FROM ledger`：`txn` / `category` / `debt` 有
// 外键会级联，但 `budget` / `recurring` / `txn_template` 的 DDL 里**没有**
// 指向 ledger 的外键 —— 删完账本，这三张表里留下的是永远查不到归属、也永远
// 清不掉的孤儿行。它们不会让任何界面报错，只会在「换机恢复」和「体检」里
// 慢慢变成解释不了的数字。
//
// 同时钉住一条反面规则：`saving_goal` 的 schema 里**没有 ledger_id**，
// 储蓄目标是全局的 —— 删账本不能顺手把目标删了。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_ledger_delete.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 在 [ledgerId] 名下造齐「五张子表各一行」。
Future<void> _seedLedgerData(int ledgerId) async {
  final cats = await Repo.listCategories(ledgerId, type: TxnType.expense);
  await Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.expense,
      amountCents: 12345,
      date: '2026-10-01',
      categoryId: cats.isEmpty ? null : cats.first.id,
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
    final doomed = await Repo.insertLedger(Ledger(id: 0, name: '装修账本'));
    await _seedLedgerData(doomed);

    // 另一本账的数据必须原样活着
    final keep = Store.i.ledgerId;
    await _seedLedgerData(keep);
    final keepTxnsBefore = await Repo.rangeListTxns(
      ledgerId: keep,
      from: '2026-10-01',
      to: '2026-10-31',
    );

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
    final extra = await Repo.insertLedger(Ledger(id: 0, name: '第二本'));
    await s.switchLedger(extra);
    await _seedLedgerData(extra);
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
