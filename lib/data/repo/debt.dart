part of '../repo.dart';

// ---------------------------------------------------------------------------
// 借贷：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  // ------------------------------------------------------------------- 借贷

  /// 记一笔借贷：建 `debt` 记录 + 本金流水，同一事务，要么都成要么都不成。
  ///
  /// 本金流水的方向**由方向决定**（借出=支出、借入=收入），不接受调用方传，
  /// 否则「借出却记成收入」会让账户余额反向。两条都带 `debt_id`，统计一律排除。
Future<int> _repoCreateDebt(
  Debt debt,
  Txn principal, {
  bool? liftToNext,
}) async {
  final startDay = await _repoCycleStartDay();
  final liftable = await _liftableCategoryIds(
    await Db.open(),
    debt.ledgerId,
  );
  return WriteGateway.run(
    _CreateDebt(debt, principal, startDay, liftable, liftToNext),
  );
}

  /// 某账本的全部借贷：未结清优先 → 有应还日的在前 → 应还日升序。
  ///
  /// `repaid_cents` 在这里按流水汇总，不落库：本金方向是「借出支出 / 借入收入」，
  /// 还款方向正好相反，所以借出数 income、借入数 expense。
Future<List<Debt>> _repoListDebts({required int ledgerId}) async {
  final db = await Db.open();
  final rows = await db.rawQuery('''
    SELECT d.*,
      COALESCE((
        SELECT SUM(t.amount_cents) FROM txn t
        WHERE t.debt_id = d.id
          AND t.type = CASE WHEN d.direction = 'out' THEN 'income' ELSE 'expense' END
      ), 0) AS repaid_cents
    FROM debt d
    WHERE d.ledger_id = ?
    ORDER BY (d.closed_at IS NULL) DESC,
             CASE WHEN d.due_date IS NULL THEN 1 ELSE 0 END,
             d.due_date ASC,
             d.id DESC
  ''', [ledgerId]);
  return rows.map(Debt.fromMap).toList();
}

  /// 记一笔还款：生成反向流水 + 必要时标记结清。
  ///
  /// 金额约束放在这里而不是界面上：任何入口（详情页、以后可能的批量核销）
  /// 都受同一条规则，不会出现某个入口漏校验、把剩余冲成负数。
Future<void> _repoRepayDebt({
  required Debt debt,
  required int amountCents,
  required int accountId,
  required String date,
}) async {
  if (amountCents <= 0) {
    throw ArgumentError('还款金额必须大于 0');
  }
  final remain = debt.remainingCents;
  if (amountCents > remain) {
    throw ArgumentError('还款金额不能超过剩余 ${Fmt.money(remain)}');
  }
  final startDay = await _repoCycleStartDay();
  final liftable = await _liftableCategoryIds(await Db.open(), debt.ledgerId);
  final t = Txn(
    id: 0,
    ledgerId: debt.ledgerId,
    type: debt.direction.isMoneyOut ? TxnType.income : TxnType.expense,
    amountCents: amountCents,
    date: date,
    accountId: accountId,
    debtId: debt.id,
    note: '${debt.counterparty} 还款',
  );
  await WriteGateway.run(
    _RepayDebt(
      txnRow: _txnRow(t, _repoPeriodFor(t, startDay, liftable)),
      t: t,
      debtId: debt.id,
      closeIt: amountCents >= remain,
    ),
  );
}

  /// 手动结清 / 撤销结清。结清只改状态，不动流水与余额 ——
  /// 「钱已经还完了但流水没记」这种账，用户自己承担，App 不去编造一笔。
Future<void> _repoSetDebtClosed(int debtId, {required bool closed}) async {
  final db = await Db.open();
  await db.update(
    'debt',
    {'closed_at': closed ? DateTime.now().toIso8601String() : null},
    where: 'id = ?',
    whereArgs: [debtId],
  );
}

Future<void> _repoDeleteDebt(int debtId) =>
    WriteGateway.run(_DeleteDebt(debtId));

  /// 删掉这笔往来时会被连带删掉的流水笔数（本金 + 每次还款）。
  ///
  /// 确认弹窗里的「还会删掉 N 笔流水」只能来自这里。写死一个数字、或者
  /// 按「本金 + 已还笔数」自己算，用户点下去删掉的东西就和提示对不上 ——
  /// 而这一步是不可撤销的，提示必须和 `_DeleteDebt` 的实际行为一致。
Future<int> _repoDebtTxnCount(int debtId) async {
  final db = await Db.open();
  final r = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM txn WHERE debt_id = ?',
    [debtId],
  );
  return (r.first['n'] as int?) ?? 0;
}

  /// 往来摘要：应收合计、应付合计、这段日期内到期且未结清的笔数。
  ///
  /// 金额取**剩余**而不是本金 —— 已经还掉的部分不该再算进「还欠多少」。
Future<({int receivable, int payable, int dueSoon})> _repoDebtSummary({
  required int ledgerId,
  required String from,
  required String to,
}) async {
  final debts = await _repoListDebts(ledgerId: ledgerId);
  var receivable = 0;
  var payable = 0;
  var dueSoon = 0;
  for (final d in debts) {
    if (d.isClosed) continue;
    if (d.direction.isReceivable) {
      receivable += d.remainingCents;
    } else {
      payable += d.remainingCents;
    }
    final due = d.dueDate;
    if (due != null && due.compareTo(from) >= 0 && due.compareTo(to) <= 0) {
      dueSoon++;
    }
  }
  return (receivable: receivable, payable: payable, dueSoon: dueSoon);
}
