import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/db/schema.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/data/repo/txn_query.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/ui/pages/detail/detail_page.dart';
import 'package:heita_ledger/ui/pages/detail/txn_row.dart';
import 'package:heita_ledger/ui/widgets/swipe_flip.dart';
import 'package:sqflite/sqflite.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 明细页：聚合口径、日卡、翻期边界、删除、路由、分页、空态、条件条。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<UiHarness> boot(WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await h.pump(tester, host(const DetailPage()));
    return h;
  }

  /// 直接批量插（不走余额增量，纯为了铺数据快）。
  Future<void> seed(int count, {LocalDate? date}) async {
    final int ledger = await currentLedger();
    final Database db = await Db.open();
    final LocalDate base = date ?? LocalDate.today().firstOfMonth.addDays(1);
    await db.transaction((Transaction txn) async {
      for (int i = 0; i < count; i++) {
        await txn.insert(Tables.txn, <String, Object?>{
          TxnCols.ledgerId: ledger,
          TxnCols.type: 'expense',
          TxnCols.amountCents: 100 + i,
          TxnCols.date: base.addDays(i % 5).iso,
          TxnCols.periodStart: LocalDate.today().firstOfMonth.iso,
          TxnCols.note: 'n$i',
          TxnCols.createdAt: DateTime(2026, 10, 16).toIso8601String(),
        });
      }
    });
  }

  testWidgets('① 概览卡笔数取聚合值（不是列表长度）', (WidgetTester tester) async {
    await seed(60);
    final UiHarness h = await boot(tester);

    expect(h.book.items.length, 50, reason: '列表一次只取 50');
    expect(find.text('60'), findsOneWidget, reason: '笔数来自 totals.count');
  });

  testWidgets('① 三格与 SQL 合计一致', (WidgetTester tester) async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 3000, date: LocalDate.today()),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 8000,
        type: TxnType.income,
        date: LocalDate.today(),
      ),
      cycleStartDay: 1,
    );
    final UiHarness h = await boot(tester);

    expect(h.book.totals.expenseCents, 3000);
    expect(find.text('50.00'), findsOneWidget, reason: '结余 80 − 30 = 50');
  });

  testWidgets('③ 日卡头：收入与支出都有才同时显示', (WidgetTester tester) async {
    final int ledger = await currentLedger();
    final LocalDate today = LocalDate.today();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 3000, date: today),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 500,
        type: TxnType.income,
        date: today,
      ),
      cycleStartDay: 1,
    );
    await boot(tester);

    final Finder subtotal = find.byKey(
      ValueKey<String>('day-subtotal-${today.iso}'),
    );
    expect(subtotal, findsOneWidget);
    expect(tester.widget<Text>(subtotal).data, '收入 ¥5.00 / 支出 ¥30.00');
  });

  testWidgets('③ 只有支出的日子不写「收入 0.00」', (WidgetTester tester) async {
    final int ledger = await currentLedger();
    final LocalDate today = LocalDate.today();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 3000, date: today),
      cycleStartDay: 1,
    );
    await boot(tester);

    final Finder subtotal = find.byKey(
      ValueKey<String>('day-subtotal-${today.iso}'),
    );
    expect(tester.widget<Text>(subtotal).data, '支出 ¥30.00');
  });

  testWidgets('⑥ 左滑翻到下一期被挡（不许翻未来），右滑可以回上一期', (
    WidgetTester tester,
  ) async {
    final UiHarness h = await boot(tester);
    final from = h.book.cycle.from;

    await tester.drag(find.byType(SwipeFlip), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(h.book.cycle.from, from, reason: '当前期已经是最后一个可看的期');

    await tester.drag(find.byType(SwipeFlip), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(h.book.cycle.from < from, isTrue);
  });

  testWidgets('⑨ 空态两套文案', (WidgetTester tester) async {
    await boot(tester);
    expect(find.text('这一期还没有账目'), findsOneWidget);

    final UiHarness h = UiHarness();
    await h.load();
    await h.book.applyFilter(const TxnQuery(keyword: '不存在的关键词'));
    await h.pump(tester, host(const DetailPage()));
    expect(find.text('没有符合条件的记录'), findsOneWidget);
  });

  testWidgets('⑩ 长按删除：确认后 toast「已删除」且库里没了', (
    WidgetTester tester,
  ) async {
    final int ledger = await currentLedger();
    final Txn saved = await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 3850, date: LocalDate.today(), note: '和同事'),
      cycleStartDay: 1,
    );
    await boot(tester);

    await tester.longPress(find.byType(TxnRow));
    await tester.pumpAndSettle();

    expect(find.text('删除这笔？'), findsOneWidget);
    expect(find.textContaining('-¥38.50'), findsOneWidget);
    // 列表里那行也带备注，所以要限定在确认框里找
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('和同事'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('confirm-ok')));
    await tester.pumpAndSettle();

    expect(find.text('已删除'), findsOneWidget);
    expect(await Repo.txn.byDebt(saved.id!), isEmpty);
    expect((await Repo.txn.allOfLedger(ledger)).length, 0);
  });

  testWidgets('④ 点借贷行 → 进往来详情（不是编辑面板）', (WidgetTester tester) async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    final int debtId = await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: 50000,
        accountId: acc,
        date: LocalDate.today(),
        dueDate: LocalDate.today().addDays(30),
        createdAt: DateTime.now(),
      ),
      cycleStartDay: 1,
    );
    expect(debtId, greaterThan(0));
    await boot(tester);

    await tester.tap(find.byType(TxnRow).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('debt-detail-title')), findsOneWidget);
    expect(find.text('往来详情'), findsOneWidget);
    expect(find.text('改一笔'), findsNothing);
  });

  testWidgets('⑤ 点普通行 → 打开编辑面板', (WidgetTester tester) async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(ledgerId: ledger, amountCents: 1000, date: LocalDate.today()),
      cycleStartDay: 1,
    );
    await boot(tester);

    await tester.tap(find.byType(TxnRow).first);
    await tester.pumpAndSettle();

    expect(find.text('改一笔'), findsOneWidget);
  });

  testWidgets('⑧ keyset 分页：滚到底自动取下一页，末尾状态行更新', (
    WidgetTester tester,
  ) async {
    await seed(60);
    final UiHarness h = await boot(tester);

    // 首页只取 50（状态行在列表末尾，此刻还没被构建出来，所以先验 Store）
    expect(find.byType(TxnRow), findsWidgets);
    expect(h.book.items.length, 50);
    expect(h.book.hasMore, isTrue);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(h.book.items.length, 60, reason: '滚到底自动补取下一页');
    expect(h.book.hasMore, isFalse, reason: '不足一页 = 没有下一页');
    // 补进来的 10 行把状态行又顶下去了，再滚一次才轮到它
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(
      find.text('已显示全部 60 笔'),
      findsOneWidget,
      reason: '末尾状态行跟着更新（50 / 共 60 → 全部 60）',
    );
  });

  testWidgets('⑦ 5,000 笔时只建可视区的行（< 80 个 TxnRow）', (
    WidgetTester tester,
  ) async {
    await seed(5000);
    await boot(tester);

    expect(
      find.byType(TxnRow).evaluate().length,
      lessThan(80),
      reason: 'SliverList.builder 只建可视区',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑦ 首屏没填满 → 下一帧自己补下一页（不用等用户滑）', (
    WidgetTester tester,
  ) async {
    // 屏幕拉高到一屏放得下 50 行：此时列表压根不溢出，滚动事件永远不会来
    tester.view.physicalSize = const Size(400, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await seed(60);
    final UiHarness h = await boot(tester);

    expect(
      h.book.items.length,
      60,
      reason: '还剩 10 条却看不到、也滑不动 —— 这一步没做就是「数据丢了」的观感',
    );
    expect(h.book.hasMore, isFalse);
  });

  testWidgets('② 筛选态：条件条首枚明写「全部历史」，且概览卡换口径', (
    WidgetTester tester,
  ) async {
    final int ledger = await currentLedger();
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 3850,
        date: LocalDate.today().addDays(-120),
        note: '去年的账',
      ),
      cycleStartDay: 1,
    );

    final UiHarness h = UiHarness();
    await h.load();
    await h.book.applyFilter(const TxnQuery(keyword: '去年'));
    await h.pump(tester, host(const DetailPage()));

    expect(find.byKey(const ValueKey<String>('filter-chips')), findsOneWidget);
    expect(find.textContaining('全部历史'), findsWidgets);
    expect(find.text('筛选结果'), findsOneWidget);
    expect(find.text('全部时间'), findsOneWidget);
  });

  testWidgets('⑪ SwipeFlip 在明细概览卡上有真实调用点', (WidgetTester tester) async {
    await boot(tester);
    expect(find.byType(SwipeFlip), findsOneWidget);
    expect(SwipeFlip.callSites, greaterThanOrEqualTo(1));
  });

  test('⑨ 空态文案函数返回两套', () {
    expect(emptyTitle(filtering: false), '这一期还没有账目');
    expect(emptyTitle(filtering: true), '没有符合条件的记录');
  });

  testWidgets('④ 借贷行标题「借出 · 张三」与中性灰金额', (WidgetTester tester) async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    await Repo.createDebt(
      Debt(
        ledgerId: ledger,
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: 50000,
        accountId: acc,
        date: LocalDate.today(),
        createdAt: DateTime.now(),
      ),
      cycleStartDay: 1,
    );
    await boot(tester);

    expect(find.text('借出 · 张三'), findsOneWidget);
    final Text amount = tester.widget<Text>(find.text('-500.00'));
    expect(amount.style?.color, paletteInk().ink3);
  });
}
