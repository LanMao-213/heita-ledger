import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/db/schema.dart';
import 'package:heita_ledger/data/models/models.dart';

/// 模型 ↔ DDL 的双向断言。
///
/// 这一组挡的是原版那个活到 1.4.5 的死列（`txn.updated_at`）：DDL 建了、
/// `toMap` 从不写、没人读。只要「模型 toMap 的键集合」与「DDL 列集合」
/// 有任何一边多一边少，这里就红。
void main() {
  DateTime now() => DateTime(2026, 10, 16, 9, 30);

  group('toMap 覆盖 DDL 全部列（双向）', () {
    test('ledger', () {
      final Ledger m = Ledger(name: '我的账本', createdAt: now());
      expect(m.toMap().keys.toSet(), kTableColumns[Tables.ledger]!.keys.toSet());
    });

    test('account', () {
      const Account m = Account(name: '现金');
      expect(
        m.toMap().keys.toSet(),
        kTableColumns[Tables.account]!.keys.toSet(),
      );
      // 改属性时不许带余额两列（原版 1.4.5 真机事故）
      expect(m.attributesOnly().keys, isNot(contains(AccountCols.openingCents)));
      expect(m.attributesOnly().keys, isNot(contains(AccountCols.balanceCents)));
    });

    test('category', () {
      const Category m = Category(type: TxnType.expense, name: '餐饮');
      expect(
        m.toMap().keys.toSet(),
        kTableColumns[Tables.category]!.keys.toSet(),
      );
    });

    test('txn（18 列，含 id）', () {
      final Txn m = Txn(
        type: TxnType.expense,
        amountCents: 3850,
        date: const LocalDate(2026, 10, 16),
        periodStart: const LocalDate(2026, 10, 15),
        createdAt: now(),
      );
      expect(m.toMap().keys.toSet(), kTableColumns[Tables.txn]!.keys.toSet());
      expect(m.toMap().length, 18);
    });

    test('budget', () {
      const Budget m = Budget(periodStart: LocalDate(2026, 10, 15));
      expect(
        m.toMap().keys.toSet(),
        kTableColumns[Tables.budget]!.keys.toSet(),
      );
    });

    test('debt（不迁/不存 repaid_cents）', () {
      final Debt m = Debt(
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: 500000,
        date: const LocalDate(2026, 10, 10),
        createdAt: now(),
      );
      expect(m.toMap().keys.toSet(), kTableColumns[Tables.debt]!.keys.toSet());
      expect(m.toMap().keys, isNot(contains('repaid_cents')));
    });

    test('recurring', () {
      final Recurring m = const Recurring(
        type: TxnType.expense,
        amountCents: 300000,
        nextRunDate: LocalDate(2026, 11, 1),
      );
      expect(
        m.toMap().keys.toSet(),
        kTableColumns[Tables.recurring]!.keys.toSet(),
      );
    });

    test('txn_template', () {
      const TxnTemplate m = TxnTemplate(name: '早餐', type: TxnType.expense);
      expect(
        m.toMap().keys.toSet(),
        kTableColumns[Tables.txnTemplate]!.keys.toSet(),
      );
    });

    test('saving_goal', () {
      const SavingGoal m = SavingGoal(name: '旅行');
      expect(
        m.toMap().keys.toSet(),
        kTableColumns[Tables.savingGoal]!.keys.toSet(),
      );
    });
  });

  test('I8：所有 *_cents 键的值都是 int，且没有 double 混进来', () {
    final DateTime at = now();
    final List<Map<String, Object?>> maps = <Map<String, Object?>>[
      const Account(name: '现金', openingCents: 100, balanceCents: 350).toMap(),
      const Budget(periodStart: LocalDate(2026, 10, 15), amountCents: 6000).toMap(),
      const SavingGoal(name: '目标', targetCents: 100, savedCents: 50).toMap(),
      const TxnTemplate(name: 't', type: TxnType.expense, amountCents: 1200).toMap(),
      const Recurring(
        type: TxnType.expense,
        amountCents: 900,
        nextRunDate: LocalDate(2026, 11, 1),
      ).toMap(),
      Debt(
        direction: DebtDirection.in_,
        counterparty: '李四',
        amountCents: 2000,
        date: const LocalDate(2026, 10, 1),
        createdAt: at,
      ).toMap(),
      Txn(
        type: TxnType.expense,
        amountCents: 1,
        date: const LocalDate(2026, 10, 1),
        periodStart: const LocalDate(2026, 10, 1),
        createdAt: at,
      ).toMap(),
    ];

    int checked = 0;
    for (final Map<String, Object?> map in maps) {
      for (final MapEntry<String, Object?> e in map.entries) {
        if (!e.key.endsWith('_cents')) continue;
        expect(e.value, isA<int>(), reason: '${e.key} 必须是 int（单位分）');
        checked++;
      }
    }
    // account 2 + budget 1 + goal 2 + template 1 + recurring 1 + debt 1 + txn 1
    expect(checked, 9);
  });

  group('往返一致性', () {
    test('Txn: toMap → fromMap 保真（含 null 外键与负金额）', () {
      final Txn src = Txn(
        id: 7,
        ledgerId: 1,
        type: TxnType.expense,
        amountCents: -2000,
        date: const LocalDate(2026, 10, 16),
        periodStart: const LocalDate(2026, 10, 15),
        note: '退款',
        person: '张三',
        debtId: null,
        createdAt: now(),
      );
      final Txn back = Txn.fromMap(src.toMap());
      expect(back.id, 7);
      expect(back.amountCents, -2000);
      expect(back.date, const LocalDate(2026, 10, 16));
      expect(back.periodStart, const LocalDate(2026, 10, 15));
      expect(back.note, '退款');
      expect(back.person, '张三');
      expect(back.debtId, isNull);
    });

    test('Txn: 空串详情字段落库为 NULL（填过又删掉 ≠ 从没填过）', () {
      final Txn m = Txn(
        type: TxnType.expense,
        amountCents: 100,
        date: const LocalDate(2026, 10, 1),
        placeFrom: '   ',
        person: '',
        createdAt: now(),
      );
      expect(m.toMap()[TxnCols.placeFrom], isNull);
      expect(m.toMap()[TxnCols.person], isNull);
    });

    test('Account: bool 落 0/1，读回来还是 bool', () {
      const Account m = Account(name: '微信', includeInTotal: false);
      expect(m.toMap()[AccountCols.includeInTotal], 0);
      expect(Account.fromMap(m.toMap()).includeInTotal, isFalse);
    });

    test('Debt: due_date 可空、closed_at 可空', () {
      final Debt m = Debt(
        direction: DebtDirection.out,
        counterparty: ' 张三 ',
        amountCents: 100,
        date: const LocalDate(2026, 10, 1),
        createdAt: now(),
      );
      expect(m.toMap()[DebtCols.counterparty], '张三', reason: '对方名要 trim');
      expect(m.toMap()[DebtCols.dueDate], isNull);
      expect(m.toMap()[DebtCols.closedAt], isNull);
      expect(Debt.fromMap(m.toMap()).isClosed, isFalse);
    });

    test('SavingGoal / TxnTemplate / Recurring 往返后关键字段不变', () {
      const SavingGoal g = SavingGoal(name: '旅行', targetCents: 100000, savedCents: 20000);
      expect(SavingGoal.fromMap(g.toMap()).remainingCents, 80000);

      const TxnTemplate t = TxnTemplate(name: '早餐', type: TxnType.expense, amountCents: 800);
      final TxnTemplate tb = TxnTemplate.fromMap(t.toMap());
      expect(tb.name, '早餐');
      expect(tb.amountCents, 800);

      final Recurring r = const Recurring(
        type: TxnType.expense,
        amountCents: 100,
        nextRunDate: LocalDate(2026, 11, 1),
        freq: RecurFreq.weekly,
        interval: 2,
        endDate: LocalDate(2027, 1, 1),
      );
      final Recurring rb = Recurring.fromMap(r.toMap());
      expect(rb.freq, RecurFreq.weekly);
      expect(rb.interval, 2);
      expect(rb.endDate, const LocalDate(2027, 1, 1));
    });
  });

  group('copyWith 的空值语义（必须能显式清空可空外键）', () {
    Txn base() => Txn(
      id: 1,
      type: TxnType.expense,
      amountCents: 100,
      categoryId: 5,
      accountId: 2,
      date: const LocalDate(2026, 10, 16),
      periodStart: const LocalDate(2026, 10, 15),
      person: '张三',
      createdAt: now(),
    );

    test('不传 → 保持原值', () {
      final Txn m = base().copyWith(note: '备注');
      expect(m.categoryId, 5);
      expect(m.periodStart, const LocalDate(2026, 10, 15));
    });

    test('显式传 null → 真的清空', () {
      final Txn m = base().copyWith(categoryId: null, person: null);
      expect(m.categoryId, isNull);
      expect(m.person, isNull);
    });

    test('改日期 → periodStart 置 null（等 Repo 用新日期重算）', () {
      final Txn m = base().copyWith(date: const LocalDate(2026, 11, 2));
      expect(m.date, const LocalDate(2026, 11, 2));
      expect(m.periodStart, isNull);
    });

    test('改日期但显式给 periodStart → 用给的那个', () {
      final Txn m = base().copyWith(
        date: const LocalDate(2026, 11, 2),
        periodStart: const LocalDate(2026, 11, 1),
      );
      expect(m.periodStart, const LocalDate(2026, 11, 1));
    });
  });

  group('Txn.sumBySide（内存侧交叉归集，五条）', () {
    Txn t(int amount, TxnType type, {int? debtId}) => Txn(
      type: type,
      amountCents: amount,
      date: const LocalDate(2026, 10, 1),
      debtId: debtId,
      createdAt: now(),
    );

    test('① 支出里的正数计入支出侧', () {
      expect(TxnSum.bySide(<Txn>[t(3000, TxnType.expense)], TxnType.expense), 3000);
      expect(TxnSum.bySide(<Txn>[t(3000, TxnType.expense)], TxnType.income), 0);
    });

    test('② 支出里的负数计入收入侧（取绝对值）', () {
      final List<Txn> list = <Txn>[t(-2000, TxnType.expense)];
      expect(TxnSum.bySide(list, TxnType.income), 2000);
      expect(TxnSum.bySide(list, TxnType.expense), 0);
    });

    test('③ 收入里的负数计入支出侧', () {
      final List<Txn> list = <Txn>[t(-1500, TxnType.income)];
      expect(TxnSum.bySide(list, TxnType.expense), 1500);
      expect(TxnSum.bySide(list, TxnType.income), 0);
    });

    test('④ debtId 非空的一律跳过两侧', () {
      final List<Txn> list = <Txn>[
        t(500000, TxnType.expense, debtId: 1),
        t(-200, TxnType.income, debtId: 1),
      ];
      expect(TxnSum.bySide(list, TxnType.expense), 0);
      expect(TxnSum.bySide(list, TxnType.income), 0);
      // 但笔数要算（列表里看得见这笔）
      expect(TxnSum.totals(list).count, 2);
    });

    test('⑤ 转账两侧都不参与', () {
      final List<Txn> list = <Txn>[t(10000, TxnType.transfer)];
      expect(TxnSum.bySide(list, TxnType.expense), 0);
      expect(TxnSum.bySide(list, TxnType.income), 0);
      expect(TxnSum.bySide(list, TxnType.transfer), 0);
    });

    test('混合场景：两侧各自归集，合计 = 两侧之差', () {
      final List<Txn> list = <Txn>[
        t(3000, TxnType.expense),
        t(-2000, TxnType.expense), // → 收入 +2000
        t(8000, TxnType.income),
        t(-500, TxnType.income), // → 支出 +500
      ];
      final RangeTotals totals = TxnSum.totals(list);
      expect(totals.expenseCents, 3500);
      expect(totals.incomeCents, 10000);
      expect(totals.netCents, 6500);
      expect(totals.count, 4);
    });
  });

  group('Debt 派生值', () {
    Debt debt(int amount) => Debt(
      id: 1,
      direction: DebtDirection.out,
      counterparty: '张三',
      amountCents: amount,
      date: const LocalDate(2026, 10, 1),
      createdAt: now(),
    );

    test('多还 100 → remainingCents 是 0 不是 −100', () {
      final RepaidIndex index = RepaidIndex.fromTxns(<Txn>[
        Txn(
          type: TxnType.income,
          amountCents: 1100,
          date: const LocalDate(2026, 10, 5),
          debtId: 1,
          createdAt: now(),
        ),
      ]);
      expect(debt(1000).remainingCents(index), 0);
      expect(debt(1000).repaidCents(index), 1100);
    });

    test('借出看 income 侧、借入看 expense 侧', () {
      final RepaidIndex index = RepaidIndex.fromTxns(<Txn>[
        Txn(
          type: TxnType.income,
          amountCents: 300,
          date: const LocalDate(2026, 10, 5),
          debtId: 1,
          createdAt: now(),
        ),
        Txn(
          type: TxnType.expense,
          amountCents: 400,
          date: const LocalDate(2026, 10, 6),
          debtId: 2,
          createdAt: now(),
        ),
      ]);
      expect(index.repaidForId(1, receivable: true), 300);
      expect(index.repaidForId(2, receivable: false), 400);
      expect(index.repaidForId(99, receivable: true), 0);
    });

    test('逾期天数：未结清 + 有应还日 + 已过 → 天数；结清后为 null', () {
      final Debt d = Debt(
        direction: DebtDirection.out,
        counterparty: '张三',
        amountCents: 1000,
        date: const LocalDate(2026, 9, 1),
        dueDate: const LocalDate(2026, 10, 1),
        createdAt: now(),
      );
      expect(d.overdueDays(today: const LocalDate(2026, 10, 11)), 10);
      // 当天不算逾期
      expect(d.overdueDays(today: const LocalDate(2026, 10, 1)), isNull);
      // 结清后不算逾期
      expect(d.copyWith(closedAt: now()).overdueDays(today: const LocalDate(2026, 12, 1)), isNull);
      // 没约定应还日 → 不算逾期
      expect(
        d.copyWith(dueDate: null).overdueDays(today: const LocalDate(2026, 12, 1)),
        isNull,
      );
    });
  });

  test('CategoryTree：O(1) 取子级、名字带父级、selfAndChildIds', () {
    const List<Category> cats = <Category>[
      Category(id: 1, type: TxnType.expense, name: '餐饮', sortOrder: 0),
      Category(id: 2, ledgerId: 1, type: TxnType.expense, name: '正餐', parentId: 1, sortOrder: 0),
      Category(id: 3, ledgerId: 1, type: TxnType.expense, name: '饮品', parentId: 1, sortOrder: 1),
      Category(id: 4, type: TxnType.expense, name: '出行', sortOrder: 1),
    ];
    final CategoryTree tree = CategoryTree(cats);

    expect(tree.tops.map((Category c) => c.name), <String>['餐饮', '出行']);
    expect(tree.childrenOf(1).map((Category c) => c.name), <String>['正餐', '饮品']);
    expect(tree.displayName(2), '餐饮 · 正餐');
    expect(tree.displayName(1), '餐饮');
    expect(tree.displayName(99), '未分类');
    expect(tree.topNameOf(2), '餐饮');
    expect(tree.selfAndChildIds(1), <int>[1, 2, 3]);
    expect(tree.selfAndChildIds(2), <int>[2]);
    expect(CategoryTree.empty.isEmpty, isTrue);
  });
}
