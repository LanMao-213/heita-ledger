// 概览卡底栏的自检（1.4.6）。
//
// 三件事，各有一条用例钉住：
// 1) 借入那行的**语序**：「额度 6,000.00（含借入 3,000.00）」。反过来写
//    用户得倒着读一遍才知道上面那个 9,000 是怎么来的 —— 这是语序问题，
//    不是文案风格问题，所以必须有断言。
// 2) 没有借支的期**不显示**这行小字（多一行没内容的字，卡片就多一分噪音）。
// 3) 没设预算的期，底栏**不能塌**，要换成「日均 / 最大一笔 / 环比」。
//    预算按「期」存，翻到上个月通常没有记录；以前整块消失，卡片矮一半。
//
// 第 3 条同时钉住环比的口径：上一期压根没记账时要说「上一期没有记账」，
// 不能算出一个「多 100%」这种假百分比。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/detail_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_detail_summary.db';

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
  });

  /// 造库：可选设预算、可选借入、可指定几笔支出（日期 + 金额）。
  Future<void> seed(
    WidgetTester tester, {
    int? budgetCents,
    int borrowedCents = 0,
    List<(DateTime, int)> txns = const [],
  }) async {
    await tester.runAsync(() async {
      await Db.close();
      final f = File(await _dbPath());
      if (f.existsSync()) f.deleteSync();

      await Store.i.boot();
      final s = Store.i;
      final acc = s.accounts.first.id;
      final cat = s.expenseCats.first.id;

      if (budgetCents != null) {
        await Repo.setBudget(
          ledgerId: s.ledgerId,
          periodStart: s.cycleFrom,
          amountCents: budgetCents,
        );
      }
      for (final (date, cents) in txns) {
        await Repo.insertTxn(
          Txn(
            id: 0,
            ledgerId: s.ledgerId,
            type: TxnType.expense,
            amountCents: cents,
            date: Fmt.date(date),
            categoryId: cat,
            accountId: acc,
          ),
        );
      }
      if (borrowedCents > 0) {
        // 借入且勾「计入预算」：可花额度 = 预算 + 本金
        await Repo.createDebt(
          Debt(
            id: 0,
            ledgerId: s.ledgerId,
            direction: DebtDirection.borrowed,
            counterparty: '张三',
            amountCents: borrowedCents,
            date: s.cycleFrom,
            accountId: acc,
            countInBudget: true,
          ),
          Txn(
            id: 0,
            ledgerId: s.ledgerId,
            type: TxnType.expense,
            amountCents: borrowedCents,
            date: s.cycleFrom,
            accountId: acc,
          ),
        );
      }
      // 借贷列表在 store 里是 loadAll 才刷新的，只调 loadCycle 的话
      // `borrowedInBudgetCents` 还是 0（踩过：断言 9,000 却只看到 6,000）
      await s.loadAll();
      await s.clearFilter();
      s.switchTab(0);
    });
  }

  Future<void> pumpDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DetailPage())),
    );
    await tester.pump();
  }

  testWidgets('有借入：额度在前、借入在括号里，与上一行的大数字对得上', (tester) async {
    await seed(
      tester,
      budgetCents: 600000,
      borrowedCents: 300000,
      txns: [(DateTime.now(), 100000)],
    );
    await pumpDetail(tester);

    // 大数字是「可花额度」= 6,000 + 3,000 = 9,000
    expect(find.textContaining('/ 9,000.00'), findsOneWidget);
    // 小字解释这 9,000 的构成：基准在前，加成在括号里
    expect(find.text('额度 6,000.00（含借入 3,000.00）'), findsOneWidget);
  });

  testWidgets('没借支：这一行小字整行都不出现', (tester) async {
    await seed(tester, budgetCents: 600000, txns: [(DateTime.now(), 100000)]);
    await pumpDetail(tester);

    expect(find.textContaining('/ 6,000.00'), findsOneWidget);
    expect(find.textContaining('含借入'), findsNothing);
    expect(find.textContaining('额度'), findsNothing);
  });

  testWidgets('没设预算的期：底栏不塌，换成日均 + 最大一笔', (tester) async {
    await seed(tester, txns: [(DateTime.now(), 100000)]);
    await pumpDetail(tester);
    final s = Store.i;
    expect(s.totalBudgetCents, isNull, reason: '前提：这一期没预算');

    expect(find.textContaining('本期预算'), findsNothing);
    expect(find.textContaining('日均'), findsOneWidget);
    expect(
      find.textContaining('最大一笔 1,000.00'),
      findsOneWidget,
      reason: '最大一笔要带分类名，只有数字的话想不起是哪笔',
    );
    // 笔数只在上面那行出现一次，底栏不再重复
    expect(find.text('1 笔'), findsOneWidget);
    expect(find.textContaining('已过'), findsOneWidget);
  });

  testWidgets('环比：上一期没有记账时说人话，不算假百分比', (tester) async {
    await seed(tester, txns: [(DateTime.now(), 300000)]);
    await pumpDetail(tester);

    // 上一期（上个月）一笔都没有 → 不能算出「多 100%」
    expect(find.text('上一期没有记账'), findsOneWidget);
  });

  testWidgets('环比：上一期有支出时给出百分比', (tester) async {
    final s0 = DateTime.now();
    // 上一期的最后一笔：放在本期开始的前一天，无条件落在上一期里
    await seed(tester, txns: [(s0, 300000)]);
    final cycleFrom = Store.i.cycleFrom;
    final prevDay = DateTime.parse(cycleFrom).subtract(const Duration(days: 1));
    await tester.runAsync(() async {
      await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: Store.i.ledgerId,
          type: TxnType.expense,
          amountCents: 100000,
          date: Fmt.date(prevDay),
          accountId: Store.i.accounts.first.id,
        ),
      );
      await Store.i.loadCycle();
    });
    await pumpDetail(tester);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    expect(
      texts.any((t) => RegExp(r'^比上一期多 \d+%$').hasMatch(t)),
      isTrue,
      reason: '本期日均远高于上一期，文案应该是「比上一期多 N%」：$texts',
    );
  });
}
