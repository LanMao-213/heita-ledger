// 「默认支出账户」的自检。
//
// 这条链路坏起来**不报错**：记账面板只是预选错一个账户，用户照样能记账，
// 只是每一笔都落在别的账户上 —— 直到某天对账发现「微信余额对不上」。
// 两个坑必须钉住：
//   1) 设了默认 → 新建一笔预选它，而不是「列表第一个」（否则这个功能等于没做）；
//   2) 默认账户被删 → 回落到第一个账户，且不崩（设置里那条 id 是历史快照，
//      账户删掉之后它就是一个指不到任何东西的死引用）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/record_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_default_account.db';

/// 账户那一颗 chip。面板上还有日期 chip，按 key 定位才不会读错。
const _accountChip = ValueKey('record_account_chip');

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void _screen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 面板上「账户」那颗 chip 的文案 —— 也就是这一笔会记到哪个账户。
String _accountLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(_accountChip), matching: find.byType(Text)),
    )
    .data!;

/// 点外面的按钮打开「记一笔」，和真实入口同一条路径（`showRecordSheet`）。
Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) => Center(
          child: TextButton(
            onPressed: () => showRecordSheet(c),
            child: const Text('记一笔'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('记一笔'));
  await tester.pumpAndSettle();
}

/// 保证至少有 [n] 个账户：默认库的种子账户数量不是这条测试的被测对象，
/// 但它必须能在任何种子组合上都成立。
Future<void> _ensureAccounts(WidgetTester tester, int n) async {
  while (Store.i.accounts.length < n) {
    await tester.runAsync(
      () => Repo.insertAccount(
        Account(id: 0, name: '测试账户${Store.i.accounts.length + 1}'),
      ),
    );
    await tester.runAsync(() => Store.i.afterAccountChange());
  }
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

  testWidgets('设了默认支出账户：新建一笔预选它', (tester) async {
    _screen(tester);
    await tester.runAsync(() => Store.i.boot());
    await _ensureAccounts(tester, 2);

    final s = Store.i;
    final first = s.accounts.first;
    final second = s.accounts[1];
    await tester.runAsync(() => s.setDefaultExpenseAccount(second.id));
    expect(s.defaultExpenseAccountId, second.id, reason: '设置要立刻生效（内存）');
    expect(
      await tester.runAsync(() => Repo.getSetting('default_expense_account')),
      '${second.id}',
      reason: '设置要落库，下次启动还记得',
    );

    await _openSheet(tester);

    expect(
      _accountLabel(tester),
      second.name,
      reason: '设了默认就必须预选它 —— 否则和「永远选第一个」没有区别',
    );
    expect(_accountLabel(tester), isNot(first.name));
  });

  testWidgets('默认账户被删：回落第一个账户，不崩', (tester) async {
    _screen(tester);
    await tester.runAsync(() => Store.i.boot());
    await _ensureAccounts(tester, 3);

    final s = Store.i;
    final victim = s.accounts[1];
    await tester.runAsync(() => s.setDefaultExpenseAccount(victim.id));
    // 没有流水、余额为 0 → 走 deleteAccount（有数据时必须先合并，是另一条用例）
    await tester.runAsync(() => s.deleteAccount(victim.id));
    expect(s.accounts.any((a) => a.id == victim.id), isFalse);
    expect(
      s.defaultExpenseAccountId,
      victim.id,
      reason: '删除不清理设置 —— 正是要被读取处兜住的那种「死引用」',
    );

    await _openSheet(tester);

    expect(tester.takeException(), isNull, reason: '死引用不能让面板崩');
    expect(
      _accountLabel(tester),
      s.accounts.first.name,
      reason: '默认账户没了就回落第一个（原行为）',
    );
  });
}
