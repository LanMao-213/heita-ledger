part of '../repo.dart';

// ---------------------------------------------------------------------------
// 账户（含余额恒等式）：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  // ------------------------------------------------------------------- 账户

/// 一处「账户引用」在账户消失之后该怎么办。
///
/// 三类，不是四种事实的罗列：
///
/// - [repoint] / [detach] 是**两种真的会发生的事**，各有实现；
/// - [unrelated] 是**一个结论**：「核过了，这一列不用动」。
///
/// ## 为什么没有 `cascade`（「随账户一起删」）
///
/// 试过，砍掉了 —— 理由不是「今天用不上」，是它**性质不同**：
///
/// 外键 `ON DELETE CASCADE` 是**数据库执行的机制**，不是一个决定。本库
/// **没有任何指向 `account` 的外键**（见 `db.dart`，账户引用都是裸 INTEGER），
/// 所以这个类别永远空着。而更危险的是：它一旦被登记，`_detachAccountRefs`
/// 里**没有对应实现**，清理会静默不发生 —— 比没有这个类别更糟，因为登记
/// 这个动作本身看起来已经"处理完了"。
///
/// 所以真出现「账户没了这一行也该删」的表时，**加类别的时候连实现和测试一起加**。
/// 预置一个空壳类别是假的完整性。
///
/// [unrelated] 必须留着：面对一列「名字像账户引用但其实无关」的字段，人是需要
/// 一个诚实的出口的 —— 否则只有两个坏选择：标成 [detach]（错，会误清数据）
/// 或者不登记（测试红）。留个出口比逼人撒谎好。
enum AccountRefAction {
  /// 改挂到目标账户：这一行代表「钱曾经动过」，账户没了记录也要留着，
  /// 否则明细里会出现解析不出账户名的孤儿。
  repoint,

  /// 置空：列的语义是「默认记到哪 / 从哪个账户挪的钱」。账户没了就回到未选
  /// —— 改挂过去等于编造一个「你把这个账户的钱转走了」的事实。
  detach,

  /// 已核对无关：列名匹配，但它不是账户引用，账户消失不用动它。
  ///
  /// 当前全库**没有**这类列 —— 空集合本身是信息：它说的是「今天没有这种字段」。
  /// 不要为了「让每一类都有条目」硬塞一条。
  unrelated,
}

/// 全库所有指向账户的列 → 账户消失后的处理方式。**唯一来源**。
///
/// 谁读它：[mergeAccount] 的改挂（[AccountRefAction.repoint]）与
/// [_detachAccountRefs] 的置空（[AccountRefAction.detach]）。名单只有这一份，
/// 所以「加一张带账户列的表」只可能漏在这里 —— 而漏在这里会被测试抓住。
///
/// 谁守它：`test/account_refs_test.dart` 扫 `PRAGMA table_info`（建完库之后
/// 的真实形状），凡列名是 `account_id` / `to_account_id` 的表都必须在上面有
/// 登记，没登记就红；登记了但库里没有这一列也红。
///
/// 这条守卫比「抽个函数」值钱：抽函数只保证今天两条路径一致，扫 schema 保证
/// **将来加表时**不会又漏一处。
const kAccountRefPlan = <String, AccountRefAction>{
  'txn.account_id': AccountRefAction.repoint,
  'txn.to_account_id': AccountRefAction.repoint,
  'recurring.account_id': AccountRefAction.detach,
  'txn_template.account_id': AccountRefAction.detach,
  'debt.account_id': AccountRefAction.detach,
  // 储蓄目标的存/取流水不是账户流水：它记的是「这笔钱从哪个账户挪进目标」，
  // 储蓄目标卡片也不读它。置空而不是改挂，理由见上面 detach 的注释。
  'goal_flow.account_id': AccountRefAction.detach,
};

/// `'txn.account_id'` → `('txn', 'account_id')`。
(String, String) _splitAccountRef(String key) {
  final dot = key.indexOf('.');
  return (key.substring(0, dot), key.substring(dot + 1));
}

/// 账户被删之后，把所有「置空」类的账户引用清掉。
///
/// 合并与直删共用这一处。以前两条路径各写一份名单（一个 for 循环一个手写
/// update），加表时改一处漏一处 —— 而漏掉不会有任何报错，只是库里多一个指向
/// 不存在账户的 id，等哪天有界面读它才会露出来。
Future<void> _detachAccountRefs(DatabaseExecutor tx, int id) async {
  for (final entry in kAccountRefPlan.entries) {
    if (entry.value != AccountRefAction.detach) continue;
    final (table, column) = _splitAccountRef(entry.key);
    await tx.update(
      table,
      {column: null},
      where: '$column = ?',
      whereArgs: [id],
    );
  }
}

Future<List<Account>> _repoListAccounts({
  bool includeArchived = false,
}) async {
  final db = await Db.open();
  final rows = await db.query(
    'account',
    where: includeArchived ? null : 'archived = 0',
    orderBy: 'sort_order, id',
  );
  return rows.map(Account.fromMap).toList();
}

  /// 净资产：只累计 `include_in_total = 1` 的账户
Future<int> _repoTotalBalanceCents() async {
  final db = await Db.open();
  final r = await db.rawQuery(
    'SELECT COALESCE(SUM(balance_cents), 0) AS t FROM account '
    'WHERE archived = 0 AND include_in_total = 1',
  );
  return (r.first['t'] as int?) ?? 0;
}

  /// 建账户。
  ///
  /// ★ v8 起 `opening_cents` 必须与 `balance_cents` 一致 —— 新建账户还没有
  ///   任何流水，`余额 = 期初 + 流水合计` 要成立只能是「期初 = 余额」。
  ///   这里**强制**对齐，不信调用方传了什么：dev 种子、Excel 导入建空账户、
  ///   以后任何新入口都会走这条，漏一个就会出现「账面 1744、按流水 -3256」
  ///   这种自造的漂移（1.4.5 真机体检发现的第一个问题就是它）。
Future<int> _repoInsertAccount(Account a) async {
  final db = await Db.open();
  final map = a.toMap()..['opening_cents'] = a.balanceCents;
  return db.insert('account', map);
}

  /// 改账户的「属性」：名称 / 类型 / 是否计入总资产 / 排序 / 停用。
  ///
  /// ★ **不写 `balance_cents` 与 `opening_cents`**。
  ///   这两列是一对恒等式的两端（`余额 = 期初 + 流水合计`），只有两条路能改它们：
  ///   `saveAccount`（用户手填余额 → 反算期初）和 `_applyBalanceDelta`（流水增减）。
  ///   如果这里跟着 `toMap()` 一起写，调用方随手构造一个 `Account(balanceCents: x)`
  ///   就会把期初抹成 0 —— 1.4.5 真机体检第一眼就抓到了这个（微信 1744 / 应 -3256）。
Future<void> _repoUpdateAccount(Account a) async {
  final db = await Db.open();
  final map = a.toMap()
    ..remove('balance_cents')
    ..remove('opening_cents');
  await db.update('account', map, where: 'id = ?', whereArgs: [a.id]);
}

  /// 某账户名下的流水笔数（含转出与转入），删除前要给用户看个数。
Future<int> _repoAccountTxnCount(int id) async {
  final db = await Db.open();
  final r = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM txn WHERE account_id = ? OR to_account_id = ?',
    [id, id],
  );
  return (r.first['c'] as int?) ?? 0;
}

  /// 删除账户，并把它的余额与流水**并入**另一个账户。
  ///
  /// `txn.account_id` 没有外键约束（见 db.dart），直接 DELETE 会留下指向
  /// 不存在账户的孤儿流水 —— 明细里那几笔解析不出账户名。所以删除只有一条
  /// 路：先合并，再删。
  ///
  /// 四步都在同一个事务里：
  /// 1. 删掉 src ↔ dst 之间的转账 —— 流水迁过去之后它们会变成「自己转给自己」
  /// 2. 流水改挂到 dst（含转入端）
  /// 3. src 的**期初**并进 dst 的期初
  /// 4. 删 src，并把其它表里指向它的账户位置空
  ///
  /// 第 3 步并的是**期初**而不是余额：流水已经迁过去了，若再并一次余额，
  /// dst 会把 src 的流水算两遍。期初 + 流水 才是余额，这样恒等式
  /// `余额 = 期初 + 流水合计` 在合并后继续成立。
Future<void> _repoMergeAccount({
  required int from,
  required int to,
}) async {
  if (from == to) throw ArgumentError('不能并入自己');
  final db = await Db.open();
  await db.transaction((tx) async {
    final rows = await tx.query(
      'account',
      where: 'id IN (?, ?)',
      whereArgs: [from, to],
    );
    Map<String, Object?>? src;
    for (final r in rows) {
      if (r['id'] == from) src = r;
    }
    if (src == null) throw StateError('账户不存在');

    // 1. 双方之间的转账：迁移后会成为自转账，直接删
    await tx.delete(
      'txn',
      where: "type = 'transfer' AND ((account_id = ? AND to_account_id = ?) "
          'OR (account_id = ? AND to_account_id = ?))',
      whereArgs: [from, to, to, from],
    );
    // 2. 流水改挂（名单来自 [kAccountRefPlan]，不在这里另写一遍）
    for (final entry in kAccountRefPlan.entries) {
      if (entry.value != AccountRefAction.repoint) continue;
      final (table, column) = _splitAccountRef(entry.key);
      await tx.update(
        table,
        {column: to},
        where: '$column = ?',
        whereArgs: [from],
      );
    }
    // 3. 期初并入（余额随之增加同样的数，恒等式不破）
    final opening = (src['opening_cents'] as int?) ?? 0;
    final balance = (src['balance_cents'] as int?) ?? 0;
    await tx.rawUpdate(
      'UPDATE account SET opening_cents = opening_cents + ?, '
      'balance_cents = balance_cents + ? WHERE id = ?',
      [opening, balance, to],
    );
    // 4. 删除 + 其它表置空（模板/定期/借贷里的账户只是「默认记到哪」，
    //    账户没了就回到未选，不跟着迁移 —— 那些是未来的计划，不是历史）
    //
    //    `goal_flow` 也在名单里：那一列记的是「这笔钱从哪个账户挪进目标」。
    //    账户被删之后它就是一个指向不存在账户的 id，而储蓄目标卡片并不读它 ——
    //    于是没有任何界面会报错，脏数据就这么一直躺着（QA 提的 P3）。
    //    置空而不是改挂到目标账户：目标流水不是账户流水，并过去等于
    //    编造一个「你从这个账户取过钱」的事实。
    await tx.delete('account', where: 'id = ?', whereArgs: [from]);
    await _detachAccountRefs(tx, from);
  });
}

  /// 删除一个**没有流水、余额为 0** 的账户。有数据时必须走 [mergeAccount]。
/// 直接删除账户。
///
/// ★ 调用前提：**这个账户没有流水**。UI 就是这么分支的（`mine_page.dart` 里
///   `empty` 为真才走这里，否则走 [_repoMergeAccount] 把记录并入目标账户）。
///   所以这里不必处理 `txn.account_id` 的改挂 —— 那是合并路径的职责。
///
/// ★ 但 `goal_flow.account_id` 要清：储蓄目标的存/取流水**不是账户流水**，
///   「没有流水」这个前提管不到它。不清就会留下一个指向已删账户的 id
///   （`plan_page` 目前不读这一列，所以看不出来；等哪天要显示「这笔记的钱
///   是从哪个账户挪的」就会读出空账户）。名单与合并路径**共用**
///   [_detachAccountRefs]，不再各写一份。
Future<void> _repoDeleteAccount(int id) async {
  final db = await Db.open();
  await db.transaction((tx) async {
    await _detachAccountRefs(tx, id);
    await tx.delete('account', where: 'id = ?', whereArgs: [id]);
  });
}

  /// 某账户的流水合计。加减规则与 [_applyBalanceDelta] **逐字对应**：
  /// 收入 +、支出 −、转账在转出端 −、在转入端 +。
  ///
  /// 金额允许为负（键盘行首打 `-` 就是负数），所以这里不做 `ABS`。
  /// 公式本体在 [kAccountFlowSql] —— 体检与「删账本后重算」用的是同一份。
Future<int> _repoAccountFlowSum(int accountId) async {
  final db = await Db.open();
  final r = await db.rawQuery(
    'SELECT ${kAccountFlowSql('?')} AS s',
    [accountId, accountId, accountId, accountId],
  );
  return (r.first['s'] as int?) ?? 0;
}

  /// 保存账户编辑：名称 / 类型 / 是否计入总资产 + 用户手填的「实际余额」。
  ///
  /// 手填余额改的是 **期初值**（`opening_cents`），不是余额本身 —— 直接写
  /// `balance_cents` 会打破恒等式 `余额 = 期初 + 流水合计`，下次体检就报一条
  /// 假的「余额不一致」。两列在同一个事务里写，不会出现只更新一半。
  ///
  /// [a] 是**新值**（调用方已 copyWith 过），[balanceCents] 是用户在输入框里
  /// 打出来的数字。
Future<void> _repoSaveAccount(Account a, int balanceCents) async {
  final flow = await _repoAccountFlowSum(a.id);
  final db = await Db.open();
  await db.transaction((txn) async {
    await txn.update(
      'account',
      {
        'name': a.name,
        'kind': a.kind.code,
        'include_in_total': a.includeInTotal ? 1 : 0,
        'balance_cents': balanceCents,
        'opening_cents': balanceCents - flow,
      },
      where: 'id = ?',
      whereArgs: [a.id],
    );
  });
}

  /// 账户余额随交易增减。
  /// [reverse] 为 true 时反向回滚（改单/删单前先回滚旧值）。
  ///
  /// 参数是 [WriteScope] 而不是 `DatabaseExecutor`：改了余额就必须和写流水
  /// 在同一个事务里，接一个作用域比接一个连接更贴合这个约束。
Future<void> _applyBalanceDelta(
  WriteScope w,
  Txn t, {
  required bool reverse,
  }) async {
  if (t.type == TxnType.transfer) {
    // 转账：转出账户减、转入账户加
    final sign = reverse ? -1 : 1;
    if (t.accountId != null) {
      await w.rawUpdate(
        'UPDATE account SET balance_cents = balance_cents + ? WHERE id = ?',
        [-t.amountCents * sign, t.accountId],
      );
    }
    if (t.toAccountId != null) {
      await w.rawUpdate(
        'UPDATE account SET balance_cents = balance_cents + ? WHERE id = ?',
        [t.amountCents * sign, t.toAccountId],
      );
    }
    return;
  }
  if (t.accountId == null) return;
  final delta = t.type.isIncome ? t.amountCents : -t.amountCents;
  await w.rawUpdate(
    'UPDATE account SET balance_cents = balance_cents + ? WHERE id = ?',
    [reverse ? -delta : delta, t.accountId],
  );
}
