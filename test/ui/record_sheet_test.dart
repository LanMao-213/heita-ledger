import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/ui/pages/record/category_row.dart';
import 'package:heita_ledger/ui/pages/record/detail_block.dart';
import 'package:heita_ledger/ui/pages/record/record_keypad.dart';
import 'package:heita_ledger/ui/pages/record/record_sheet.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 记一笔面板：模式、借贷、详情字段、抬期、保存与失败、防连点。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<_Holder> openRecord(
    WidgetTester tester,
    UiHarness h, {
    Txn? editing,
  }) async {
    final _Holder holder = _Holder();
    await h.pump(
      tester,
      host(
        Builder(
          builder: (BuildContext ctx) => TextButton(
            onPressed: () async =>
                holder.outcome = await showRecordSheet(ctx, editing: editing),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return holder;
  }

  Future<void> typeAmount(WidgetTester tester, String keys) async {
    for (final String k in keys.split('')) {
      await tester.tap(find.byKey(ValueKey<String>('key-$k')));
      await tester.pump();
    }
  }

  test('④ 借贷不进 TxnType 枚举：只有 expense / income / transfer', () {
    expect(TxnType.values.length, 3);
    expect(
      TxnType.values.map((TxnType t) => t.code),
      <String>['expense', 'income', 'transfer'],
    );
    // 借贷模式有 5 个，但落库类型仍然只有 3 个
    expect(RecordMode.values.length, 5);
    expect(RecordMode.lend.txnType, TxnType.expense);
    expect(RecordMode.borrow.txnType, TxnType.income);
  });

  testWidgets('① 五种模式都在，没有被做成新类型的「借贷」', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await openRecord(tester, h);

    for (final RecordMode m in RecordMode.values) {
      expect(
        find.byKey(ValueKey<String>('chip-${m.label}')),
        findsOneWidget,
        reason: '缺模式 ${m.label}',
      );
    }
    expect(find.text('借贷'), findsNothing);
  });

  testWidgets('③ 借贷模式隐藏分类行、显示对方字段、借出不给「计入预算」', (
    WidgetTester tester,
  ) async {
    final UiHarness h = UiHarness();
    await h.load();
    await openRecord(tester, h);

    expect(find.byKey(const ValueKey<String>('record-category')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('chip-借出')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('record-category')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('record-counterparty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('record-count-in-budget')),
      findsNothing,
    );

    // 借入才有「计入预算」
    await tester.tap(find.byKey(const ValueKey<String>('chip-借入')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('record-count-in-budget')),
      findsOneWidget,
    );
  });

  testWidgets('③ 借贷：金额 <= 0 或对方为空 → 不可保存', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await openRecord(tester, h);
    await tester.tap(find.byKey(const ValueKey<String>('chip-借入')));
    await tester.pumpAndSettle();

    // 没输金额
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pump();
    expect(find.byType(RecordSheet), findsOneWidget);

    // 金额 0
    await typeAmount(tester, '0');
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pump();
    expect(find.byType(RecordSheet), findsOneWidget);

    // 正数但对方为空
    await tester.tap(find.byKey(const ValueKey<String>('key-C')));
    await tester.pump();
    await typeAmount(tester, '100');
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pump();
    expect(find.byType(RecordSheet), findsOneWidget);
    expect(await Repo.debt.all(await currentLedger()), isEmpty);
  });

  testWidgets('⑥ 详情字段只保留 fieldsOfSub 认的', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();

    await h.pump(
      tester,
      host(
        DetailBlock(
          subName: '正餐',
          values: const <TxnField, String>{},
          onChanged: (Map<TxnField, String> _) {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>('record-detail-person')), findsNothing);
    expect(find.byKey(const ValueKey<String>('record-detail-from')), findsNothing);

    await h.pump(
      tester,
      host(
        DetailBlock(
          subName: '红包份子',
          values: const <TxnField, String>{},
          onChanged: (Map<TxnField, String> _) {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>('record-detail-person')), findsOneWidget);
  });

  test('⑥ 换同组字段不丢、换到不需详情的分类全清、备注在前', () {
    final Map<TxnField, String> filled = <TxnField, String>{
      TxnField.from: '家',
      TxnField.to: '公司',
      TxnField.person: '张三',
      TxnField.subject: '会计',
    };

    final Map<TxnField, String> toTaxi = detailsAfterCategoryChange('打车', filled);
    expect(toTaxi[TxnField.from], '家', reason: '公共交通 ⇄ 打车 同组字段不丢');
    expect(toTaxi[TxnField.person], '');

    final Map<TxnField, String> toMeal = detailsAfterCategoryChange('正餐', filled);
    expect(toMeal.values.every((String v) => v.isEmpty), isTrue);

    expect(noteBeforeDetails('打车'), isTrue, reason: '有详情字段时备注在前');
    expect(noteBeforeDetails('正餐'), isFalse);
    expect(activeFieldsOf('课程培训'), <TxnField>[TxnField.subject]);
  });

  testWidgets('⑪ 备注框聚焦立刻收键盘', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await openRecord(tester, h);

    expect(find.byType(RecordKeypad), findsOneWidget);

    // 备注在滚动区底部，先滚到可见再点（不然点在了键盘上）
    await tester.ensureVisible(find.byKey(const ValueKey<String>('record-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('record-note')));
    await tester.pumpAndSettle();

    expect(find.byType(RecordKeypad), findsNothing);
  });

  testWidgets('⑦ 账单日 1 时「这笔算下一期」不出现', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await openRecord(tester, h);

    expect(find.byKey(const ValueKey<String>('record-lift')), findsNothing);
  });

  testWidgets('⑦ 编辑抬过期的旧记录 → 开关自动为真', (WidgetTester tester) async {
    await Db.writeSetting('cycle_start_day', '15');
    final int ledger = await currentLedger();
    final Txn lifted = Txn(
      id: 1,
      ledgerId: ledger,
      type: TxnType.income,
      amountCents: 800000,
      date: const LocalDate(2026, 10, 10),
      periodStart: const LocalDate(2026, 10, 15),
      createdAt: DateTime(2026, 10, 10),
    );
    await Repo.txn.insert(lifted);

    final UiHarness h = UiHarness();
    await h.load();
    await openRecord(tester, h, editing: lifted);

    final SwitchListTile sw = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('record-lift')),
    );
    expect(sw.value, isTrue, reason: 'periodStart ≠ 不抬期算出的期 → 当初抬过');
    expect(find.text('改一笔'), findsOneWidget);
  });

  testWidgets('⑧ 保存普通流水：回执带期文案，库里落一笔 45.50', (
    WidgetTester tester,
  ) async {
    final UiHarness h = UiHarness();
    await h.load();
    final _Holder holder = await openRecord(tester, h);

    await typeAmount(tester, '12.5*3+8');
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pumpAndSettle();

    expect(holder.outcome, isNotNull);
    expect(holder.outcome!.label, contains('至'));

    final List<Txn> rows = await Repo.txn.allOfLedger(await currentLedger());
    expect(rows.length, 1);
    expect(rows.single.amountCents, 4550);
    expect(rows.single.type, TxnType.expense);
  });

  testWidgets('⑨ 落库失败：toast「保存失败」且面板不关', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    // 账本指针指到一个不存在的 ledger → 外键失败
    await h.book.bind(ledgerId: 999999, cycleStartDay: 1);
    await openRecord(tester, h);

    await typeAmount(tester, '10');
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(RecordSheet), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
  });

  testWidgets('⑩ 防连点：连按两次确认只落一笔', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await openRecord(tester, h);

    await typeAmount(tester, '20');
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pumpAndSettle();

    expect(
      (await Repo.txn.allOfLedger(await currentLedger())).length,
      1,
    );
  });

  testWidgets('③ 借出落库：debt_id 非空、type 仍是 expense、对方进 person', (
    WidgetTester tester,
  ) async {
    final UiHarness h = UiHarness();
    await h.load();
    final _Holder holder = await openRecord(tester, h);

    await tester.tap(find.byKey(const ValueKey<String>('chip-借出')));
    await tester.pumpAndSettle();
    await typeAmount(tester, '500');
    await tester.enterText(
      find.byKey(const ValueKey<String>('record-counterparty')),
      '张三',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pumpAndSettle();

    final List<Txn> rows = await Repo.txn.allOfLedger(await currentLedger());
    expect(rows.single.debtId, isNotNull);
    expect(rows.single.type, TxnType.expense);
    expect(rows.single.amountCents, 50000);
    expect(rows.single.person, '张三');
    expect(holder.outcome, isNotNull);

    final List<Debt> debts = await Repo.debt.all(await currentLedger());
    expect(debts.single.countInBudget, isFalse, reason: '借出恒不计入预算');
  });

  testWidgets('转账：需要两个账户才能保存', (WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    await openRecord(tester, h);

    await tester.tap(find.byKey(const ValueKey<String>('chip-转账')));
    await tester.pumpAndSettle();
    await typeAmount(tester, '100');
    expect(
      find.byKey(const ValueKey<String>('record-to-account')),
      findsOneWidget,
    );
    // 没选转入账户 → 确认点不动
    await tester.tap(find.byKey(const ValueKey<String>('key-confirm')));
    await tester.pump();
    expect(await Repo.txn.allOfLedger(await currentLedger()), isEmpty);
  });
}

class _Holder {
  RecordOutcome? outcome;
}
