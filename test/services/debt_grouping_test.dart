import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/services/debt_grouping.dart';

/// 按人分组：净额相抵 + isMixed 副行 + 空名不丢弃 + 4 级排序稳定。
void main() {
  final DateTime now = DateTime(2026, 10, 16);
  final LocalDate today = const LocalDate(2026, 10, 16);

  Debt mk({
    required int id,
    required String who,
    required DebtDirection dir,
    required int amount,
    String date = '2026-10-01',
    String? due,
    DateTime? closedAt,
  }) => Debt(
    id: id,
    direction: dir,
    counterparty: who,
    amountCents: amount,
    date: LocalDate.parse(date),
    dueDate: due == null ? null : LocalDate.parse(due),
    closedAt: closedAt,
    createdAt: now,
  );

  test('① 同一个人既借出又借入 → 净额相抵', () {
    final List<Debt> debts = <Debt>[
      mk(id: 1, who: '张三', dir: DebtDirection.out, amount: 500000),
      mk(id: 2, who: '张三', dir: DebtDirection.in_, amount: 200000),
    ];
    final List<PersonDebts> groups = groupDebtsByCounterparty(debts);

    expect(groups.length, 1);
    final PersonDebts g = groups.single;
    expect(g.receivableCents(RepaidIndex.empty), 500000);
    expect(g.payableCents(RepaidIndex.empty), 200000);
    expect(g.netCents(RepaidIndex.empty), 300000, reason: '净额 = 5000 − 2000');
    expect(g.count, 2);
  });

  test('② isMixed 只在两边都有余额时为真（副行要提示净额怎么来的）', () {
    final PersonDebts mixed = PersonDebts('张三', <Debt>[
      mk(id: 1, who: '张三', dir: DebtDirection.out, amount: 500000),
      mk(id: 2, who: '张三', dir: DebtDirection.in_, amount: 200000),
    ]);
    expect(mixed.isMixed(RepaidIndex.empty), isTrue);

    final PersonDebts onlyOut = PersonDebts('李四', <Debt>[
      mk(id: 3, who: '李四', dir: DebtDirection.out, amount: 100),
    ]);
    expect(onlyOut.isMixed(RepaidIndex.empty), isFalse);
  });

  test('③ 空名字归到「未填对方」，不丢弃', () {
    final List<Debt> debts = <Debt>[
      mk(id: 1, who: '   ', dir: DebtDirection.out, amount: 100),
      mk(id: 2, who: '', dir: DebtDirection.in_, amount: 50),
      mk(id: 3, who: ' 王五 ', dir: DebtDirection.out, amount: 10),
    ];
    final List<PersonDebts> groups = groupDebtsByCounterparty(debts);

    expect(groups.length, 2);
    final PersonDebts blank = groups.firstWhere(
      (PersonDebts g) => g.name == '未填对方',
    );
    expect(blank.count, 2, reason: '两个空名字合并成一组，且一条都不少');
    expect(
      groups.any((PersonDebts g) => g.name == '王五'),
      isTrue,
      reason: '名字要 trim',
    );
  });

  test('④ 排序：逾期优先 → 应还日近的在前 → 净额大的 → 名字（两次结果一致）', () {
    final List<Debt> debts = <Debt>[
      // 无逾期、无应还日、净额 10 元
      mk(id: 1, who: '小钱', dir: DebtDirection.out, amount: 1000),
      // 逾期 15 天
      mk(id: 2, who: '逾期王', dir: DebtDirection.out, amount: 100, due: '2026-10-01'),
      // 未逾期，应还日 10-20
      mk(id: 3, who: '近期', dir: DebtDirection.out, amount: 100, due: '2026-10-20'),
      // 无逾期、无应还日、净额 900 元
      mk(id: 4, who: '大额', dir: DebtDirection.out, amount: 90000),
    ];

    final List<String> first = groupDebtsByCounterparty(
      debts,
      today: today,
    ).map((PersonDebts g) => g.name).toList();
    final List<String> second = groupDebtsByCounterparty(
      debts.reversed,
      today: today,
    ).map((PersonDebts g) => g.name).toList();

    expect(first, <String>['逾期王', '近期', '大额', '小钱']);
    expect(second, first, reason: '同数据不同入参顺序，结果必须一致');
  });

  test('⑤ 已结清的债不进分组（已结清的钱不构成「欠」）', () {
    final List<Debt> debts = <Debt>[
      mk(id: 1, who: '张三', dir: DebtDirection.out, amount: 100),
      mk(
        id: 2,
        who: '李四',
        dir: DebtDirection.out,
        amount: 100,
        closedAt: now,
      ),
    ];
    final List<PersonDebts> groups = groupDebtsByCounterparty(debts);
    expect(groups.map((PersonDebts g) => g.name), <String>['张三']);
  });

  test('⑥ nearestDue / overdueDays / single', () {
    final PersonDebts g = PersonDebts('张三', <Debt>[
      mk(id: 1, who: '张三', dir: DebtDirection.out, amount: 100, due: '2026-11-30'),
      mk(id: 2, who: '张三', dir: DebtDirection.out, amount: 100, due: '2026-10-05'),
      mk(id: 3, who: '张三', dir: DebtDirection.out, amount: 100),
    ]);

    expect(g.nearestDue, const LocalDate(2026, 10, 5));
    expect(g.overdueDays(today: today), 11, reason: '取最严重的那笔');
    expect(g.isOverdue(today: today), isTrue);
    expect(g.single, isNull, reason: '三笔时没有 single');

    final PersonDebts one = PersonDebts('李四', <Debt>[
      mk(id: 9, who: '李四', dir: DebtDirection.out, amount: 100),
    ]);
    expect(one.single?.id, 9);
    expect(one.nearestDue, isNull);
    expect(one.overdueDays(today: today), isNull);
  });

  test('⑦ 已还部分计入净额（按债务方向取对应一侧的流水）', () {
    final List<Debt> debts = <Debt>[
      mk(id: 1, who: '张三', dir: DebtDirection.out, amount: 500000),
    ];
    final RepaidIndex index = RepaidIndex.fromTxns(<Txn>[
      Txn(
        type: TxnType.income,
        amountCents: 100000,
        date: const LocalDate(2026, 10, 10),
        debtId: 1,
        createdAt: now,
      ),
    ]);

    final PersonDebts g = groupDebtsByCounterparty(debts, repaid: index).single;
    expect(g.receivableCents(index), 400000);
    expect(g.netCents(index), 400000);
  });
}
