part of '../repo.dart';

// ---------------------------------------------------------------------------
// 写命令（WriteGateway 的载荷）
//
// 约定：这里只放「一次写入的完整语义」。计算归属期、查分类白名单这类**读**
// 都在 `Repo.xxx` 里先做完再传进来 —— 那几个查询本来就在事务外，放进事务
// 只会拉长持锁时间。
//
// 每个命令的 `verify` 都只校验「这次动过的账户」。全表对账在
// `Integrity.check()` 里，不放在写入路径上。
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 写命令（WriteGateway 的载荷）
//
// 约定：这里只放「一次写入的完整语义」。计算归属期、查分类白名单这类**读**
// 都在 `Repo.xxx` 里先做完再传进来 —— 那几个查询本来就在事务外，放进事务
// 只会拉长持锁时间。
//
// 每个命令的 `verify` 都只校验「这次动过的账户」。全表对账在
// `Integrity.check()` 里，不放在写入路径上。
// ---------------------------------------------------------------------------

/// 校验一笔流水影响到的账户（转账要校验两侧）。
Future<void> _verifyTxnBalance(Verifier v, Txn t) async {
if (t.type == TxnType.transfer) {
  await v.checkBalance(t.accountId);
  await v.checkBalance(t.toAccountId);
  return;
}
await v.checkBalance(t.accountId);
}

/// 批量导入账单。一次事务写全部流水，然后按账户反补期初。
///
/// 为什么不是「循环调 insertTxn」：那样每条开一次事务，中途失败会留下
/// 半批数据 —— 用户看到「导入成功 87 条」，其实只进了一半。
class _ImportBills extends Command<int> {
_ImportBills(this.txns, this.rows);

final List<Txn> txns;

/// 已算好归属期的行（`_txnRow` 的结果），与 [txns] 一一对应
final List<Map<String, Object?>> rows;

@override
Future<int> apply(WriteScope w) async {
  // ★ 这里**故意不调 `_applyBalanceDelta`**。
  //
  // 那个方法是给「现在花了一笔」用的：它把流水和余额一起改。
  // 而导入历史账单的语义是「流水要进来，余额不能动」—— 若先调它再把
  // 余额补回去，等于一进一出写两次同一个数，中间只要有一处漏了，
  // 就会留下只能靠体检才发现的漂移（第一版就是这么写错的，
  // 被 WriteGateway 的自检当场抓到：账面 −3000、按流水应为 0）。
  //
  // 正确做法：只把期初调过来。因为 `余额 = 期初 + 流水合计`，
  // 流水变了而余额不许变，那就只能由期初来吸收这个差额。
  final openingFix = <int, int>{};

  for (var i = 0; i < txns.length; i++) {
    final t = txns[i];
    await w.insert('txn', rows[i]);

    final acc = t.accountId;
    if (acc != null) {
      // 支出让流水变负，期初就补正；收入反之。
      final delta = t.type.isIncome ? -t.amountCents : t.amountCents;
      openingFix[acc] = (openingFix[acc] ?? 0) + delta;
    }
  }

  for (final e in openingFix.entries) {
    if (e.value == 0) continue;
    await w.rawUpdate(
      'UPDATE account SET opening_cents = opening_cents + ? WHERE id = ?',
      [e.value, e.key],
    );
  }

  return txns.length;
}

@override
Future<void> verify(Verifier v) async {
  // 导入最容易踩的就是「余额被重复扣一次」，所以每个碰到的账户都对一次账
  for (final id in txns.map((t) => t.accountId).whereType<int>().toSet()) {
    await v.checkBalance(id);
  }
}
}

class _InsertTxn extends Command<int> {
_InsertTxn(this.t, this.row);

final Txn t;

/// 已算好归属期的行（`_txnRow` 的结果）
final Map<String, Object?> row;

@override
Future<int> apply(WriteScope w) async {
  final id = await w.insert('txn', row);
  await _applyBalanceDelta(w, t, reverse: false);
  return id;
}

@override
Future<void> verify(Verifier v) => _verifyTxnBalance(v, t);
}

class _UpdateTxn extends Command<void> {
_UpdateTxn(this.old, this.now, this.row);

final Txn old;
final Txn now;
final Map<String, Object?> row;

@override
Future<void> apply(WriteScope w) async {
  // 先按旧值回滚余额，再写新行，再按新值应用 —— 三步同事务，
  // 中间任何一步失败都不会留下「余额按旧值扣了、流水已是新值」的库。
  await _applyBalanceDelta(w, old, reverse: true);
  await w.update('txn', row, where: 'id = ?', whereArgs: [now.id]);
  await _applyBalanceDelta(w, now, reverse: false);
}

@override
Future<void> verify(Verifier v) async {
  // 改单可能换了账户（从现金改成支付宝），两侧都要校验
  await _verifyTxnBalance(v, old);
  await _verifyTxnBalance(v, now);
}
}

class _DeleteTxn extends Command<void> {
_DeleteTxn(this.t);

final Txn t;

@override
Future<void> apply(WriteScope w) async {
  await _applyBalanceDelta(w, t, reverse: true);
  await w.delete('txn', where: 'id = ?', whereArgs: [t.id]);
}

@override
Future<void> verify(Verifier v) => _verifyTxnBalance(v, t);
}

/// 批量删除。一个事务里逐条回滚余额再删行。
///
/// 顺序不能反：先 `_applyBalanceDelta(reverse)` 再 `delete`，与 [_DeleteTxn]
/// 完全一致 —— 余额回滚是按这条流水算的，删完行就没得算了。
class _DeleteTxns extends Command<int> {
_DeleteTxns(this.items);

final List<Txn> items;

@override
Future<int> apply(WriteScope w) async {
  for (final t in items) {
    await _applyBalanceDelta(w, t, reverse: true);
    await w.delete('txn', where: 'id = ?', whereArgs: [t.id]);
  }
  return items.length;
}

@override
Future<void> verify(Verifier v) async {
  // 同一账户被删多笔时只校验一次：`checkBalance` 是整账户重算，
  // 重复调用不会出错，但会白跑
  final seen = <int>{};
  for (final t in items) {
    for (final id in [t.accountId, t.toAccountId]) {
      if (id != null && seen.add(id)) await v.checkBalance(id);
    }
  }
}
}

class _CreateDebt extends Command<int> {
_CreateDebt(this.debt, this.principal, this.startDay, this.liftable, this.liftToNext);

final Debt debt;
final Txn principal;
final int startDay;
final Set<int> liftable;
final bool? liftToNext;

@override
Future<int> apply(WriteScope w) async {
  // 借出恒不计入预算：钱出去了，不是可花的钱。入口只给「借入」显示这个开关，
  // 但口径由数据层兜住，不指望每个调用方都记得传 false。
  final map = debt.toMap();
  if (debt.direction.isReceivable) map['count_in_budget'] = 0;

  final debtId = await w.insert('debt', map);
  // 本金流水的方向由方向决定，不接受调用方传 —— 否则「借出却记成收入」
  // 会让账户余额反向。
  final row = principal.copyWith(
    debtId: debtId,
    type: debt.direction.isMoneyOut ? TxnType.expense : TxnType.income,
  );
  await w.insert(
    'txn',
    _txnRow(
      row,
      Repo.periodFor(
        row,
        startDay,
        liftable,
        liftToNext: liftToNext,
      ),
    ),
  );
  await _applyBalanceDelta(w, row, reverse: false);
  return debtId;
}

@override
Future<void> verify(Verifier v) => v.checkBalance(principal.accountId);
}

class _RepayDebt extends Command<void> {
_RepayDebt({
  required this.txnRow,
  required this.t,
  required this.debtId,
  required this.closeIt,
});

final Map<String, Object?> txnRow;
final Txn t;
final int debtId;
final bool closeIt;

@override
Future<void> apply(WriteScope w) async {
  await w.insert('txn', txnRow);
  await _applyBalanceDelta(w, t, reverse: false);
  if (closeIt) {
    await w.update(
      'debt',
      {'closed_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [debtId],
    );
  }
}

@override
Future<void> verify(Verifier v) => v.checkBalance(t.accountId);
}

class _DeleteDebt extends Command<void> {
_DeleteDebt(this.debtId);

final int debtId;

@override
Future<void> apply(WriteScope w) async {
  // 先回滚余额：把挂在这笔上的流水逐条反向应用，再连流水一起删
  final rows = await w.query(
    'txn',
    where: 'debt_id = ?',
    whereArgs: [debtId],
  );
  for (final r in rows) {
    await _applyBalanceDelta(w, Txn.fromMap(r), reverse: true);
  }
  await w.delete('txn', where: 'debt_id = ?', whereArgs: [debtId]);
  await w.delete('debt', where: 'id = ?', whereArgs: [debtId]);
}
}

