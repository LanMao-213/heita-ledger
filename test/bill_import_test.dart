// 账单导入的两条不变量。
//
// 这个功能最危险的不是解析错（那看得见），而是**余额被扣两次**：
// 用户导完一批历史账单，发现卡里的钱少了 3000，而且他没法判断是
// 「本来就这么少」还是「App 算错了」。
//
// 所以这里钉两件事：
//   1. 导入前后账户余额一字不变；
//   2. `余额 = 期初 + 流水合计` 这条恒等式仍然成立（体检不报漂移）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/integrity.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_bill_import.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

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

  test('导入不改余额，且恒等式仍然成立', () async {
    await Store.i.boot();
    final s = Store.i;
    final ledgerId = s.ledgerId;

    final accounts = await Repo.listAccounts();
    expect(accounts, isNotEmpty);
    final acc = accounts.first;
    final before = acc.balanceCents;

    final txns = <Txn>[
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 3200,
        date: '2026-09-03',
        accountId: acc.id,
        note: '星巴克 · 拿铁',
      ),
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 1850,
        date: '2026-09-05',
        accountId: acc.id,
        note: '滴滴出行',
      ),
    ];

    final n = await Repo.importBillRows(txns: txns);
    expect(n, 2);

    // 1. 余额不变
    final after = (await Repo.listAccounts()).firstWhere((a) => a.id == acc.id);
    expect(after.balanceCents, before, reason: '导入历史账单不该改变账户余额');

    // 2. 期初被反向补齐（支出让期初变大）
    expect(after.openingCents, acc.openingCents + 3200 + 1850);

    // 3. 流水确实进去了
    final dumped = await Repo.rangeListTxns(
      ledgerId: ledgerId,
      from: '2026-09-01',
      to: '2026-09-30',
      basis: DateBasis.date,
    );
    expect(dumped.length, 2);

    // 4. 体检不报余额漂移
    final report = await Integrity.check();
    final drift = report.issues.where(
      (i) => i.kind == IntegrityKind.balanceDrift,
    );
    expect(drift, isEmpty, reason: '导入后体检不该报余额漂移');
  });

  test('收入行会把期初调小（方向相反）', () async {
    await Store.i.boot();
    final s = Store.i;
    final acc = (await Repo.listAccounts()).first;

    await Repo.importBillRows(
      txns: [
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.income,
          amountCents: 10000,
          date: '2026-09-08',
          accountId: acc.id,
          note: '李四 · 还钱',
        ),
      ],
    );

    final after = (await Repo.listAccounts()).firstWhere((a) => a.id == acc.id);
    expect(after.balanceCents, acc.balanceCents);
    expect(after.openingCents, acc.openingCents - 10000);
  });

  test('跨账户时按账户分别补期初，不汇总调', () async {
    await Store.i.boot();
    final s = Store.i;
    final accounts = await Repo.listAccounts();
    expect(accounts.length, greaterThanOrEqualTo(2));
    final a = accounts[0];
    final b = accounts[1];

    await Repo.importBillRows(
      txns: [
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.expense,
          amountCents: 3000,
          date: '2026-09-03',
          accountId: a.id,
        ),
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.expense,
          amountCents: 5000,
          date: '2026-09-04',
          accountId: b.id,
        ),
      ],
    );

    final fresh = await Repo.listAccounts();
    final fa = fresh.firstWhere((x) => x.id == a.id);
    final fb = fresh.firstWhere((x) => x.id == b.id);

    // 若按总额 8000 汇总调，a 会多出 5000、b 少 3000 —— 体检立刻报漂移
    expect(fa.openingCents, a.openingCents + 3000);
    expect(fb.openingCents, b.openingCents + 5000);
    expect(fa.balanceCents, a.balanceCents);
    expect(fb.balanceCents, b.balanceCents);
  });

  test('空列表不写任何东西', () async {
    await Store.i.boot();
    final n = await Repo.importBillRows(txns: const []);
    expect(n, 0);
  });
}
