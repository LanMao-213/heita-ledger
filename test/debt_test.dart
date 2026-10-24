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
import 'package:ledger/data/debt_grouping.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/debts_page.dart';
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


/// 账户流水合计。用来验 `余额 == 期初 + 流水合计` 这条恒等式：
/// 借贷只产生 income / expense 两种流水，方向就是余额的增减方向。
Future<int> _flowSum(int accountId) async {
  final db = await Db.open();
  final rows = await db.query(
    'txn',
    where: 'account_id = ?',
    whereArgs: [accountId],
  );
  var sum = 0;
  for (final r in rows) {
    final t = Txn.fromMap(r);
    sum += t.type == TxnType.income ? t.amountCents : -t.amountCents;
  }
  return sum;
}

/// 等 UI 里触发的那次写入真正落库。
///
/// 1.4.5 起写入走 `WriteGateway`，测试环境里它会在事务内跑一次不变量校验
/// （多两次查询）。假时钟下这多出来的异步回合会让「固定 `Future.delayed`
/// 然后断言」的写法变得不稳定 —— 不是功能回归，是等待方式太脆。
/// 这里改成有界轮询：条件成立就立刻返回，最多等 40×50ms 真实时间。
Future<void> _waitUntil(
  WidgetTester tester,
  Future<bool> Function() done, {
  int rounds = 40,
}) async {
  for (var i = 0; i < rounds; i++) {
    if ((await tester.runAsync(done)) ?? false) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

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

  // 界面上的「删除这笔往来」只走 `Repo.deleteDebt`，所以这里钉的是它的**真实语义**：
  // 不是只删 debt 一行，而是把 `debt_id` 命中的流水（本金 + 每次还款）全部删掉、
  // 逐条反向回滚账户余额。确认弹窗里写的笔数就是按这个口径 `COUNT(*)` 出来的。
  test('删除往来：debt 查不到、连带流水清空、余额回到 opening + Σ流水', () async {
    await _freshDb();
    final c = await _ctx();
    final baseline = c.account.balanceCents; // 这笔往来存在之前的余额
    final debtId = await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );
    // 再记一笔部分还款：这样这笔往来上挂着 2 笔流水（本金 + 还款）
    final d0 = (await Repo.listDebts(
      ledgerId: c.ledgerId,
    )).firstWhere((e) => e.id == debtId);
    await Repo.repayDebt(
      debt: d0,
      amountCents: 200000,
      accountId: c.account.id,
      date: Fmt.today(),
    );

    expect(
      await Repo.debtTxnCount(debtId),
      2,
      reason: '弹窗要报的笔数：本金 1 笔 + 还款 1 笔',
    );

    // 删除前的恒等式先成立，否则后面的「回到删除前」没有意义
    final before = (await Repo.listAccounts()).firstWhere(
      (a) => a.id == c.account.id,
    );
    expect(
      before.balanceCents,
      before.openingCents + await _flowSum(c.account.id),
      reason: '删除前余额就该等于 期初 + 流水',
    );

    await Repo.deleteDebt(debtId);

    final debts = await Repo.listDebts(ledgerId: c.ledgerId);
    expect(debts.where((e) => e.id == debtId), isEmpty, reason: 'debt 行要没');
    expect(await Repo.debtTxnCount(debtId), 0, reason: '连带流水要一起没');

    final after = (await Repo.listAccounts()).firstWhere(
      (a) => a.id == c.account.id,
    );
    expect(
      after.balanceCents,
      baseline,
      reason: '借出 5000、还回 2000 两笔流水都回滚掉，余额回到这笔往来出现之前',
    );
    expect(
      after.balanceCents,
      after.openingCents + await _flowSum(c.account.id),
      reason: '删除后仍要满足 余额 = 期初 + 流水（不许留下孤零零的余额修正）',
    );
  });

  testWidgets('往来详情：删除入口在还款下方，弹窗报清连带笔数，删完闭面板并提示', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => _freshDb());
    await tester.runAsync(() => Store.i.boot());
    final c = (await tester.runAsync(() => _ctx()))!;
    final debtId = (await tester.runAsync(
      () => Repo.createDebt(
        _debt(ledgerId: c.ledgerId, accountId: c.account.id),
        _principal(ledgerId: c.ledgerId, accountId: c.account.id),
      ),
    ))!;
    final d0 = (await tester.runAsync(
      () => Repo.listDebts(ledgerId: c.ledgerId),
    ))!.firstWhere((e) => e.id == debtId);
    await tester.runAsync(
      () => Repo.repayDebt(
        debt: d0,
        amountCents: 200000,
        accountId: c.account.id,
        date: Fmt.today(),
      ),
    );
    await tester.runAsync(() => Store.i.afterTxnChange());

    await tester.pumpWidget(const MaterialApp(home: DebtsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();

    // 主按钮仍是「记一笔还款」，删除是它下面的次要动作
    expect(find.text('记一笔还款'), findsOneWidget);
    expect(find.text('删除这笔往来'), findsOneWidget);

    await tester.tap(find.text('删除这笔往来'));
    // 弹窗要等一次真实的 `COUNT(*)`（假时钟下不会自己走完），
    // 先让真实 I/O 跑完再 settle，否则断言时弹窗还没建出来。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    // 弹窗必须写清对方/方向/金额，以及**实际**会连带删掉几笔流水。
    // 对话框统一走 widgets/menu.dart 的 showAppDialog（骨架是 Dialog），
    // 不再按 AlertDialog 找。
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('张三')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('5,000.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('2 笔流水')),
      findsOneWidget,
      reason: '本金 + 还款 = 2 笔，数字要与库里的 COUNT(*) 一致',
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 删 → 刷新 store → 关面板是一串真实 I/O，假时钟下不会自己走完：
    // 先交替跑真实时间和带时长的 pump（让退场动画也推进），再 settle。
    await _waitUntil(tester, () async => await Repo.debtTxnCount(debtId) == 0);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    final debts = (await tester.runAsync(
      () => Repo.listDebts(ledgerId: c.ledgerId),
    ))!;
    expect(debts.where((e) => e.id == debtId), isEmpty);

    // 面板关掉（还款按钮不再在屏上），并给了提示
    expect(find.text('记一笔还款'), findsNothing);
    expect(find.text('已删除'), findsOneWidget);
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

  test('净资产把应收算进去：借出前后总额不变', () async {
    await _freshDb();
    await Store.i.boot();
    final c = await _ctx();
    final before = Store.i.netWorthWithDebtCents;

    await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );
    await Store.i.afterTxnChange();

    expect(Store.i.netWorthCents, before - 500000, reason: '现金账户确实少了');
    expect(Store.i.receivableCents, 500000);
    expect(
      Store.i.netWorthWithDebtCents,
      before,
      reason: '借出只是把钱换成别人欠我，总资产不该变',
    );
  });

  test('备份包含 debt：导出一圈再恢复，往来与流水都还在', () async {
    await _freshDb();
    final c = await _ctx();
    final debtId = await Repo.createDebt(
      _debt(ledgerId: c.ledgerId, accountId: c.account.id),
      _principal(ledgerId: c.ledgerId, accountId: c.account.id),
    );

    final dump = await Repo.dumpTables();
    expect(dump['debt'], isNotNull, reason: '备份必须带上往来表');
    expect(dump['debt']!.length, 1);
    expect(dump['txn']!.length, 1);

    // 覆盖式恢复：整库清掉再灌回去
    await Repo.replaceTables(dump);

    final debts = await Repo.listDebts(ledgerId: c.ledgerId);
    expect(debts.length, 1);
    expect(debts.first.id, debtId);
    expect(debts.first.counterparty, '张三');
    expect(debts.first.remainingCents, 500000);

    final txns = await Repo.listTxns(
      ledgerId: c.ledgerId,
      month: Fmt.month(DateTime.now()),
    );
    expect(txns.where((t) => t.debtId == debtId).length, 1, reason: '流水上的 debt_id 要保住');
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
    await _waitUntil(tester, () async {
      final ds = await Repo.listDebts(ledgerId: Store.i.ledgerId);
      return ds.isNotEmpty;
    });

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

  testWidgets('往来页：列表显示应收，点进去能记一笔还款', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => _freshDb());
    await tester.runAsync(() => Store.i.boot());
    final c = (await tester.runAsync(() => _ctx()))!;
    await tester.runAsync(
      () => Repo.createDebt(
        _debt(ledgerId: c.ledgerId, accountId: c.account.id),
        _principal(ledgerId: c.ledgerId, accountId: c.account.id),
      ),
    );
    await tester.runAsync(() => Store.i.afterTxnChange());

    await tester.pumpWidget(const MaterialApp(home: DebtsPage()));
    await tester.pumpAndSettle();

    expect(find.text('应收（别人欠我）'), findsOneWidget);
    // 未结清按人列：标题是姓名，方向在副行
    expect(find.text('张三'), findsOneWidget);
    expect(find.textContaining('借出'), findsWidgets);

    // 进详情：能记还款（只有一笔时点人名直接进那笔的详情）
    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();
    expect(find.text('记一笔还款'), findsOneWidget);

    await tester.tap(find.text('记一笔还款'));
    await tester.pumpAndSettle();

    // 金额默认是剩余（5000），改成 2000 再确认
    await tester.enterText(find.byType(TextField).last, '2000');
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await _waitUntil(tester, () async {
      final ds = await Repo.listDebts(ledgerId: c.ledgerId);
      return ds.isNotEmpty && ds.first.repaidCents > 0;
    });

    final d = (await tester.runAsync(
      () => Repo.listDebts(ledgerId: c.ledgerId),
    ))!.first;
    expect(d.repaidCents, 200000);
    expect(d.remainingCents, 300000);
  });

  // ---------------------------------------------------------------- 按人汇总
  //
  // 往来页的主语是「人」不是「笔」。这几条钉住合并规则：同一个人的几笔要加成
  // 一个净额，已结清的不能算进来，该催的（逾期）要排最上面。
  group('按人汇总', () {
    Debt d({
      String name = '张三',
      DebtDirection direction = DebtDirection.lent,
      int amount = 100000,
      String? due = '2026-11-30',
      int repaid = 0,
      String? closedAt,
    }) => Debt(
      id: 0,
      ledgerId: 1,
      direction: direction,
      counterparty: name,
      amountCents: amount,
      date: '2026-10-01',
      dueDate: due,
      closedAt: closedAt,
      repaidCents: repaid,
    );

    test('同一个人的几笔合并成一行，金额相加', () {
      final g = groupDebtsByCounterparty([
        d(amount: 300000),
        d(amount: 200000, due: '2026-12-31'),
      ]);
      expect(g.length, 1);
      expect(g.first.name, '张三');
      expect(g.first.count, 2);
      expect(g.first.receivableCents, 500000);
      expect(g.first.nearestDue, '2026-11-30', reason: '取最近的那个应还日');
      expect(g.first.single, isNull, reason: '多笔时不能直接进某一笔的详情');
    });

    test('既借出又借入时按净额算，但两边金额都保留', () {
      final g = groupDebtsByCounterparty([
        d(amount: 500000),
        d(direction: DebtDirection.borrowed, amount: 200000),
      ]).single;
      expect(g.isMixed, isTrue);
      expect(g.receivableCents, 500000);
      expect(g.payableCents, 200000);
      expect(g.netCents, 300000, reason: '净额是对方还欠我 3000');
    });

    test('已结清的不进汇总，也不影响净额', () {
      final g = groupDebtsByCounterparty([
        d(amount: 300000),
        d(amount: 900000, closedAt: '2026-10-10'),
      ]).single;
      expect(g.count, 1);
      expect(g.netCents, 300000);
    });

    test('逾期的排在前面，没约定日期的垫底', () {
      final g = groupDebtsByCounterparty([
        d(name: '无期限', due: null),
        d(name: '年底', due: '2026-12-31'),
        d(name: '逾期', due: '2026-09-01'),
      ]);
      expect(g.map((e) => e.name).toList(), ['逾期', '年底', '无期限']);
      expect(g.first.isOverdue, isTrue);
    });

    test('名字为空归到「未填对方」，不丢数据', () {
      final g = groupDebtsByCounterparty([d(name: '  ')]).single;
      expect(g.name, '未填对方');
      expect(g.count, 1);
    });
  });

  testWidgets('往来页：同一个人的两笔合并成一行，点开看明细', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => _freshDb());
    await tester.runAsync(() => Store.i.boot());
    final c = (await tester.runAsync(() => _ctx()))!;
    for (final amount in [300000, 200000]) {
      await tester.runAsync(
        () => Repo.createDebt(
          _debt(ledgerId: c.ledgerId, accountId: c.account.id, amount: amount),
          _principal(ledgerId: c.ledgerId, accountId: c.account.id),
        ),
      );
    }
    await tester.runAsync(() => Store.i.afterTxnChange());

    await tester.pumpWidget(const MaterialApp(home: DebtsPage()));
    await tester.pumpAndSettle();

    expect(find.text('张三'), findsOneWidget, reason: '两笔要合成一行');
    expect(find.textContaining('2 笔'), findsOneWidget);
    expect(find.text('5,000.00'), findsWidgets, reason: '净额是两笔之和');

    // 点开这个人的明细：两笔都在，各自能进详情
    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();
    expect(find.text('张三 · 借出'), findsNWidgets(2));
  });
}
