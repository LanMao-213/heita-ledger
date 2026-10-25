// 全量备份 / 恢复的自检。
//
// 这是「换手机 / 重装」的唯一救命路径，所以测的不是「能不能跑」，
// 而是三件要命的事：
// 1) 导出 → 清空 → 恢复之后，每一类数据都要**逐项对得上**（不只是笔数）；
// 2) 文件不对时必须**拒绝且一行都不动** —— 覆盖式写入没有第二次机会；
// 3) 恢复只带回用户数据，机器状态类的设置（应用名、实验开关）不能被旧备份改写。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/backup_service.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/data/repo_stats.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_backup.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 一份能逐项比对的指纹：数量 + 金额 + 余额，光对笔数不够
typedef Fingerprint = ({
  int txns,
  int expenses,
  int income,
  int netWorth,
  int budgets,
  int goals,
  int templates,
  int recurring,
  int categories,
  int accounts,
  int ledgers,
});

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

    await Store.i.boot();
    final s = Store.i;
    final now = Fmt.today();

    final cat = s.expenseCats.first.id;
    final income = s.incomeCats.first.id;
    final acc = s.accounts.first.id;

    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.expense,
        amountCents: 12800,
        date: now,
        categoryId: cat,
        accountId: acc,
        note: '午饭',
      ),
    );
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.income,
        amountCents: 500000,
        date: now,
        categoryId: income,
        accountId: acc,
        note: '工资',
      ),
    );
    await Repo.setBudget(
      ledgerId: s.ledgerId,
      periodStart: s.cycleFrom,
      categoryId: null,
      amountCents: 300000,
    );
    await Repo.insertGoal(
      const SavingGoal(
        id: 0,
        name: '相机',
        targetCents: 800000,
        savedCents: 200000,
        dueMonth: '2027-03',
      ),
    );
    await Repo.insertTemplate(
      TxnTemplate(
        id: 0,
        ledgerId: s.ledgerId,
        name: '咖啡',
        type: TxnType.expense,
        amountCents: 1500,
        categoryId: cat,
        accountId: acc,
        note: '咖啡',
      ),
    );
    await Repo.insertRecurring(
      RecurringRule(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.expense,
        amountCents: 8800,
        categoryId: cat,
        accountId: acc,
        note: '会员',
        freq: 'monthly',
        nextRunDate: now,
      ),
    );
    await s.loadAll();
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  Future<Fingerprint> fp() async {
    final s = Store.i;
    final db = await Db.open();
    Future<int> count(String t) async {
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
      return (r.first['c'] as int?) ?? 0;
    }

    final totals = await RepoStats.monthTotals(s.ledgerId, s.month);
    final budgets = await Repo.totalBudgetCents(s.ledgerId, s.month);
    return (
      txns: totals.$3,
      expenses: totals.$1,
      income: totals.$2,
      netWorth: await Repo.totalBalanceCents(),
      budgets: budgets ?? 0,
      goals: await count('saving_goal'),
      templates: await count('txn_template'),
      recurring: await count('recurring'),
      categories: await count('category'),
      accounts: await count('account'),
      ledgers: await count('ledger'),
    );
  }

  test('导出 → 清空 → 恢复：数据逐项对得上', () async {
    final before = await fp();
    final payload = await BackupService.dump();

    // 清空（等价于用户手动清空所有数据）
    await Repo.replaceTables({});
    final emptied = await fp();
    expect(emptied.txns, 0);
    expect(emptied.netWorth, 0);

    final counts = await BackupService.restore(payload);
    final after = await fp();

    expect(after, before, reason: '恢复后每一类数据都要和导出前一致');
    expect(counts['txn'], before.txns);
    expect(counts['account'], before.accounts);
  });

  test('文件不对：拒绝恢复，且一行都不动', () async {
    final before = await fp();

    // 1) 不是本应用的备份
    await expectLater(
      BackupService.restore({'format': 'something-else', 'tables': {}}),
      throwsA(isA<BackupException>()),
    );

    // 2) schema 比当前新
    final future = await BackupService.dump();
    await expectLater(
      BackupService.restore({...future, 'schemaVersion': Db.schemaVersion + 1}),
      throwsA(isA<BackupException>()),
    );

    // 3) 表结构坏掉
    await expectLater(
      BackupService.restore({
        'format': BackupService.format,
        'formatVersion': 1,
        'schemaVersion': Db.schemaVersion,
        'tables': {'txn': 'oops'},
      }),
      throwsA(isA<BackupException>()),
    );

    // 4) 空备份不该清空现有数据
    await expectLater(
      BackupService.restore({
        'format': BackupService.format,
        'formatVersion': 1,
        'schemaVersion': Db.schemaVersion,
        'tables': {'txn': [], 'account': []},
      }),
      throwsA(isA<BackupException>()),
    );

    expect(await fp(), before, reason: '任何一次拒绝都不该改动现有数据');
  });

  test('只恢复用户数据，机器状态类的设置不被旧备份改写', () async {
    // 导出时的应用名 / 实验开关
    final payload = await BackupService.dump();

    // 导出后机器状态变了：应用改名、关掉类型 chips
    await Repo.setSetting('app_name', '改过的名字');
    await Repo.setSetting('ui.type_chips', '0');

    await BackupService.restore(payload);

    expect(
      await Repo.getSetting('app_name'),
      '改过的名字',
      reason: '应用名属于这台机器的状态，不该被备份覆盖',
    );
    expect(
      await Repo.getSetting('ui.type_chips'),
      '0',
      reason: '实验开关属于这台机器的状态',
    );
    // 「当前用哪个账本」是用户数据，跟着走
    expect(await Repo.getSetting('current_ledger_id'), '${Store.i.ledgerId}');
  });

  test('恢复后 Store 能重新读到账本与余额', () async {
    final payload = await BackupService.dump();
    final before = await fp();

    await Repo.replaceTables({});
    await BackupService.restore(payload);
    await Store.i.reloadAfterRestore();

    expect(Store.i.txnCount, before.txns);
    expect(Store.i.netWorthCents, before.netWorth);
    expect(Store.i.accounts, isNotEmpty);
    expect(Store.i.filtering, isFalse, reason: '恢复后要清掉可能失效的筛选条件');
  });
}
