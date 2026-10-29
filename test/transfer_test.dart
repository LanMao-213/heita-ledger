// 账户转账的自检。
//
// 转账是唯一一种「动余额但不算收支」的流水。这条边界错起来很隐蔽：
// 少减一个账户看不出来（总额是对的），多算进支出也看不出来（金额是真的），
// 只有对账时才会发现「这个月怎么多花了 500」。
//
// 四条一起钉住：
//   1) 转出账户减、转入账户加（方向反了就是「钱越转越多」）；
//   2) 净资产合计不变（钱只是换了个口袋）；
//   3) 收支统计不计入（转账不是消费也不是收入）；
//   4) 面板本身拦住「同账户转账」和「金额为 0」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/transfer_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_transfer.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 保证至少两个账户；返回前两个（转出、转入）。
Future<(Account, Account)> _twoAccounts() async {
  final s = Store.i;
  while (s.accounts.length < 2) {
    await Repo.insertAccount(
      Account(id: 0, name: '测试账户${s.accounts.length + 1}'),
    );
    await s.afterAccountChange();
  }
  return (s.accounts[0], s.accounts[1]);
}

Future<int> _balanceOf(int id) async {
  final accounts = await Repo.listAccounts();
  return accounts.firstWhere((a) => a.id == id).balanceCents;
}

/// 打开转账面板。走的是真实入口 `showTransferSheet`，和「账户管理 → 转账」同一条路。
Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) => Center(
          child: TextButton(
            onPressed: () => showTransferSheet(c),
            child: const Text('转账'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('转账'));
  await tester.pumpAndSettle();
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

  test('转账：转出减、转入加、总资产不变、不计入收支', () async {
    await Store.i.boot();
    final s = Store.i;
    final (from, to) = await _twoAccounts();
    final totalBefore = await Repo.totalBalanceCents();
    final fromBefore = await _balanceOf(from.id);
    final toBefore = await _balanceOf(to.id);

    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.transfer,
        amountCents: 50000,
        date: Fmt.today(),
        accountId: from.id,
        toAccountId: to.id,
        note: '挪到余额宝',
      ),
    );
    await s.afterTxnChange();

    expect(await _balanceOf(from.id), fromBefore - 50000, reason: '转出账户要减');
    expect(await _balanceOf(to.id), toBefore + 50000, reason: '转入账户要加');
    expect(
      await Repo.totalBalanceCents(),
      totalBefore,
      reason: '钱只是换了口袋，净资产合计不能变',
    );

    expect(s.expenseCents, 0, reason: '转账不是支出');
    expect(s.incomeCents, 0, reason: '转账也不是收入');
    expect(
      s.stats.expenseStats,
      isEmpty,
      reason: '分类统计里不该出现转账 —— 它没有分类',
    );
    // 明细里仍然要看得到（它是真实发生过的一笔钱）
    expect(s.txns.where((t) => t.type == TxnType.transfer), hasLength(1));
  });

  testWidgets('面板：同账户转账被拦住，不写库', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());
    late Account from;
    await tester.runAsync(() async {
      final (a, _) = await _twoAccounts();
      from = a;
    });
    final before = await tester.runAsync(() => _balanceOf(from.id));

    await _openSheet(tester);

    // 金额先填上，排除「金额为空」这条更早的校验
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pump();

    // 把「转入」改成与「转出」同一个账户
    await tester.tap(find.byKey(const ValueKey('transfer_to')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(from.name).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('确认转账'));
    await tester.pumpAndSettle();

    expect(find.text('转出和转入不能是同一个账户'), findsOneWidget);
    expect(
      await tester.runAsync(() => _balanceOf(from.id)),
      before,
      reason: '校验没过就不能写库',
    );
    expect(
      Store.i.txns.where((t) => t.type == TxnType.transfer),
      isEmpty,
      reason: '同账户转账不该落库',
    );
  });

  testWidgets('面板：金额为 0 不提交', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());
    await tester.runAsync(_twoAccounts);

    await _openSheet(tester);
    await tester.tap(find.text('确认转账'));
    await tester.pumpAndSettle();

    expect(find.text('请输入大于 0 的金额'), findsOneWidget);
    expect(
      Store.i.txns.where((t) => t.type == TxnType.transfer),
      isEmpty,
      reason: '金额为 0 不该落库',
    );
  });
}
