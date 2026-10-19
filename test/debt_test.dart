// 借贷往来的数据层自检。
//
// 四件容易做错的事：
// 1) 本金流水的方向 —— 借出必须是支出（钱出去），借入必须是收入；
//    写反了账户余额就反向，而且没人看得出来；
// 2) 剩余金额靠流水算 —— 存冗余字段迟早和流水对不上；
// 3) 还款不能超额，且还满要自动结清；
// 4) 删掉一笔借贷，账户余额要回到借出之前。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/calc_keypad.dart';
import 'package:ledger/widgets/detail/txn_row.dart';
import 'package:ledger/widgets/record_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_debt.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 每个用例都从一个刚播种的空库开始，互不干扰
Future<void> _freshDb() async {
  await Db.close();
  Db.fileName = _dbName;
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();
  await Db.open();
}

Future<({int ledgerId, Account account})> _ctx() async {
  final ledgerId = await Repo.currentLedgerId();
  final accounts = await Repo.listAccounts();
  return (ledgerId: ledgerId, account: accounts.first);
}

Debt _debt({
  required int ledgerId,
  required int accountId,
  DebtDirection direction = DebtDirection.lent,
  int amount = 500000,
  String counterparty = '张三',
  String? dueDate = '2026-11-30',
}) => Debt(
  id: 0,
  ledgerId: ledgerId,
  direction: direction,
  counterparty: counterparty,
  amountCents: amount,
  date: Fmt.today(),
  accountId: accountId,
  dueDate: dueDate,
  countInBudget: direction == DebtDirection.borrowed,
);

Txn _principal({
  required int ledgerId,
  required int accountId,
  int amount = 500000,
}) => Txn(
  id: 0,
  ledgerId: ledgerId,
  // 故意传反方向：Repo 必须按借贷方向覆盖，而不是信任调用方
  type: TxnType.income,
  amountCents: amount,
  date: Fmt.today(),
  accountId: accountId,
);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  test('新库有 debt 表，txn 有 debt_id 列', () async {
    await _freshDb();
    final db = await Db.open();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'debt'",
    );
    expect(tables, isNotEmpty);
    final cols = await db.rawQuery('PRAGMA table_info(txn)');
    expect(cols.any((c) => c['name'] == 'debt_id'), isTrue);
  });

  test('借出：本金记成支出，账户减少，流水挂上 debt_id', () async {
    await _freshDb();
    final c = await _ctx();
    final before = c.account.balanceCents;

    final debtId = await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );

    final d = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == debtId);
    expect(d.counterparty, '张三');
    expect(d.direction, DebtDirection.lent);
    expect(d.remainingCents, 500000);
    expect(d.isClosed, isFalse);

    final after = (await Repo.listAccounts()).firstWhere(
      (a) => a.id == c.account.id,
    );
    expect(after.balanceCents, before - 500000);

    final txns = await Repo.listTxns(
      ledgerId: c.ledgerId,
      month: Fmt.month(DateTime.now()),
    );
    final principal = txns.firstWhere((t) => t.debtId == debtId);
    expect(principal.type, TxnType.expense, reason: '借出必须是钱出去');
    expect(principal.amountCents, 500000);
  });

  test('借入：本金记成收入，账户增加', () async {
    await _freshDb();
    final c = await _ctx();
    final before = c.account.balanceCents;

    final debtId = await Repo.createDebt(
      _debt(
        ledgerId: c.ledgerId,
        accountId: c.account.id,
        direction: DebtDirection.borrowed,
        counterparty: '李四',
        amount: 300000,
      ),
      _principal(
        ledgerId: c.ledgerId,
        accountId: c.account.id,
        amount: 300000,
      ),
    );

    final d = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == debtId);
    expect(d.direction, DebtDirection.borrowed);
    expect(d.countInBudget, isTrue);

    final after = (await Repo.listAccounts()).firstWhere(
      (a) => a.id == c.account.id,
    );
    expect(after.balanceCents, before + 300000);

    final txns = await Repo.listTxns(
      ledgerId: c.ledgerId,
      month: Fmt.month(DateTime.now()),
    );
    expect(txns.firstWhere((t) => t.debtId == debtId).type, TxnType.income);
  });

  test('部分还款：剩余按流水算；还满自动结清', () async {
    await _freshDb();
    final c = await _ctx();
    final debtId = await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );
    var d = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == debtId);

    await Repo.repayDebt(
      debt: d,
      amountCents: 200000,
      accountId: c.account.id,
      date: Fmt.today(),
    );
    d = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == debtId);
    expect(d.repaidCents, 200000);
    expect(d.remainingCents, 300000);
    expect(d.isClosed, isFalse, reason: '没还完不能算结清');

    await Repo.repayDebt(
      debt: d,
      amountCents: 300000,
      accountId: c.account.id,
      date: Fmt.today(),
    );
    d = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == debtId);
    expect(d.remainingCents, 0);
    expect(d.isClosed, isTrue);
  });

  test('还款超额或非正数被拒', () async {
    await _freshDb();
    final c = await _ctx();
    final debtId = await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );
    final d = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == debtId);

    expect(
      () => Repo.repayDebt(
        debt: d,
        amountCents: 500001,
        accountId: c.account.id,
        date: Fmt.today(),
      ),
      throwsArgumentError,
    );
    expect(
      () => Repo.repayDebt(
        debt: d,
        amountCents: 0,
        accountId: c.account.id,
        date: Fmt.today(),
      ),
      throwsArgumentError,
    );
  });

  test('摘要：应收按剩余汇总，到期笔数只数未结清', () async {
    await _freshDb();
    final c = await _ctx();
    // 借出 5000（还 1000）→ 应收 4000；借入 3000 → 应付 3000
    final outId = await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );
    await Repo.createDebt(
      _debt(
        ledgerId: c.ledgerId,
        accountId: c.account.id,
        direction: DebtDirection.borrowed,
        counterparty: '李四',
        amount: 300000,
        dueDate: '2026-10-25',
      ),
      _principal(
        ledgerId: c.ledgerId,
        accountId: c.account.id,
        amount: 300000,
      ),
    );
    var out = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == outId);
    await Repo.repayDebt(
      debt: out,
      amountCents: 100000,
      accountId: c.account.id,
      date: Fmt.today(),
    );

    final s = await Repo.debtSummary(
      ledgerId: c.ledgerId,
      from: '2026-10-01',
      to: '2026-10-31',
    );
    expect(s.receivable, 400000);
    expect(s.payable, 300000);
    expect(s.dueSoon, 1, reason: '只有李四那笔应还日在 10 月');
  });

  test('删除借贷：流水一并清掉，账户余额回到借出之前', () async {
    await _freshDb();
    final c = await _ctx();
    final before = c.account.balanceCents;
    final debtId = await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );

    await Repo.deleteDebt(debtId);

    final after = (await Repo.listAccounts()).firstWhere(
      (a) => a.id == c.account.id,
    );
    expect(after.balanceCents, before);
    final txns = await Repo.listTxns(
      ledgerId: c.ledgerId,
      month: Fmt.month(DateTime.now()),
    );
    expect(txns.where((t) => t.debtId == debtId), isEmpty);
  });

  test('借出不算支出：月度合计与分类统计都不变', () async {
    await _freshDb();
    final c = await _ctx();
    final month = Fmt.month(DateTime.now());
    final before = await Repo.monthTotals(c.ledgerId, month);

    await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );

    final after = await Repo.monthTotals(c.ledgerId, month);
    expect(after.$1, before.$1, reason: '借出不是消费，支出合计不该变');
    expect(after.$2, before.$2, reason: '借出更不是收入');

    final cats = await Repo.categoryStats(
      ledgerId: c.ledgerId,
      month: month,
      type: TxnType.expense,
    );
    expect(cats, isEmpty, reason: '借贷流水不该出现在分类饼图里');
  });

  test('回收借款不算收入', () async {
    await _freshDb();
    final c = await _ctx();
    final month = Fmt.month(DateTime.now());
    final debtId = await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );
    final before = await Repo.monthTotals(c.ledgerId, month);
    final d = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == debtId);

    await Repo.repayDebt(
      debt: d,
      amountCents: 200000,
      accountId: c.account.id,
      date: Fmt.today(),
    );

    final after = await Repo.monthTotals(c.ledgerId, month);
    expect(after.$1, before.$1);
    expect(after.$2, before.$2, reason: '收回来的钱不是这个月的收入');
  });

  testWidgets('记一笔：切到借出，填对方与金额后落成一条往来', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // 开库/建种子是真实 I/O，必须包在 runAsync 里 —— 假时钟里直接 await
    // 会永久挂住，连超时都不触发（交接说明第 4 节第 2 条）
    await tester.runAsync(() => _freshDb());
    await tester.runAsync(() => Store.i.boot());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showRecordSheet(ctx),
                child: const Text('记一笔'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    // 切到「借出」：出现对方输入框，分类行不再出现
    await tester.tap(find.text('借出'));
    await tester.pumpAndSettle();
    expect(find.text('借给谁（必填）'), findsOneWidget);

    // 没填对方时确认键不可用：先填对方
    await tester.enterText(find.byType(TextField).first, '张三');
    await tester.pump();

    for (final k in ['5', '0', '0', '0']) {
      await tester.tap(
        find.descendant(
          of: find.byType(CalcKeypad),
          matching: find.text(k),
        ),
      );
      await tester.pump();
    }
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );

    final debts = await tester.runAsync(
      () => Repo.listDebts(ledgerId: Store.i.ledgerId),
    );
    expect(debts, isNotNull);
    expect(debts!.length, 1);
    expect(debts.first.counterparty, '张三');
    expect(debts.first.direction, DebtDirection.lent);
    expect(debts.first.amountCents, 500000);
    expect(debts.first.remainingCents, 500000);
  });

  testWidgets('明细行把借贷显示成「借出 · 张三」，并带应还日', (tester) async {
    await tester.runAsync(() => _freshDb());
    await tester.runAsync(() => Store.i.boot());

    final c = (await tester.runAsync(() => _ctx()))!;
    final debtId = (await tester.runAsync(
      () => Repo.createDebt(
        _debt(ledgerId: c.ledgerId, accountId: c.account.id),
        _principal(ledgerId: c.ledgerId, accountId: c.account.id),
      ),
    ))!;
    await tester.runAsync(() => Store.i.afterTxnChange());

    final txns = (await tester.runAsync(
      () => Repo.listTxns(
        ledgerId: c.ledgerId,
        month: Fmt.month(DateTime.now()),
      ),
    ))!;
    final t = txns.firstWhere((e) => e.debtId == debtId);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TxnRow(txn: t))),
    );
    await tester.pumpAndSettle();

    expect(find.text('借出 · 张三'), findsOneWidget);
    expect(find.textContaining('应还'), findsOneWidget);
  });
}
