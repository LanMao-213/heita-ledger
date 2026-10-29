part of '../repo.dart';

// ---------------------------------------------------------------------------
// 账本：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  /// 当前账本 id。
  ///
  /// ★ 存下来的 id **必须校验还活着**：1.4.1 的清空 bug 会在库里留下
  /// 「`current_ledger_id` 指着已删除的账本」这种状态，直接沿用的话，
  /// 明细、分类、预算全部按一个不存在的 ledger_id 去查 —— 界面上一片空白，
  /// 记一笔也看不见（新记录挂在另一个账本上）。这里发现对不上就改成真实存在的
  /// 那一本，让已经中招的库在下次启动时自愈，不用重装。
Future<int> _repoCurrentLedgerId() async {
  final v = await _repoGetSetting('current_ledger_id');
  final saved = int.tryParse(v ?? '');
  if (saved != null) {
    final db = await Db.open();
    final hit = await db.query(
      'ledger',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [saved],
      limit: 1,
    );
    if (hit.isNotEmpty) return saved;
  }
  final ledgers = await _repoListLedgers();
  if (ledgers.isEmpty) {
    final db = await Db.open();
    final id = await db.insert('ledger', {
      'name': '日常账本',
      'icon': 'book',
      'sort_order': 0,
      'archived': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _repoSetSetting('current_ledger_id', '$id');
    return id;
  }
  await _repoSetSetting('current_ledger_id', '${ledgers.first.id}');
  return ledgers.first.id;
}

  // ------------------------------------------------------------------- 账本
Future<List<Ledger>> _repoListLedgers({
  bool includeArchived = false,
}) async {
  final db = await Db.open();
  final rows = await db.query(
    'ledger',
    where: includeArchived ? null : 'archived = 0',
    orderBy: 'sort_order, id',
  );
  return rows.map(Ledger.fromMap).toList();
}

Future<int> _repoInsertLedger(Ledger l) async {
  final db = await Db.open();
  final id = await db.insert('ledger', l.toMap());
  // 新账本要带上默认分类，否则记一笔时没分类可选。
  // 走 `Db.seedCategories` 而不是在这儿再列一份分类表 —— 两处各写一份，
  // 迟早出现「首启账本有正餐、新建账本只有餐饮」这种只在新建账本上复现的怪事。
  await Db.seedCategories(db, id);
  return id;
}

Future<void> _repoUpdateLedger(Ledger l) async {
  final db = await Db.open();
  await db.update('ledger', l.toMap(), where: 'id = ?', whereArgs: [l.id]);
}

  /// 删除账本：**单事务级联**删掉它名下的一切，并冲回这些流水对账户余额的影响。
  ///
  /// ★ 1.5.2 修正。原实现只有一句 `DELETE FROM ledger`，靠外键级联兜底；
  ///   但 `budget` / `recurring` / `txn_template` 三张表的 DDL 里**没有**指向
  ///   `ledger` 的外键（见 `db.dart`），于是删完账本会留下一堆指向死账本的
  ///   孤儿行：预算查不到归属、周期账单还留在库里等下一次补记扫到。
  ///   所以这里显式按「子表在前、主表在后」删一遍 —— 顺序错了会撞
  ///   `PRAGMA foreign_keys = ON`（与 `Db._wipeOrder` 同一条规矩）。
  ///
  /// ★ `saving_goal` / `goal_flow` **刻意不删**：`saving_goal` 的 schema 里
  ///   没有 `ledger_id`（储蓄目标是全局的，不按账本分），它不是账本的子表。
  ///   按账本去删它等于「删一个账本顺手清掉所有储蓄目标」。
  ///
  /// ★ **余额必须跟着回滚**（`account` 是全局表，没有 `ledger_id`）。被删账本
  ///   的流水花的是**共用账户**上的钱：删掉流水却不冲回余额，账户就永久少了
  ///   一笔 —— 而且症状极隐蔽，「数据体检」只会说「余额与流水不一致」，
  ///   没人能从这里看出起因是删了一本账。见事务末尾那一段。
Future<void> _repoDeleteLedger(int id) async {
  final db = await Db.open();
  await db.transaction((txn) async {
    // ① 先记下这些流水碰过哪些账户 —— 删完就再也查不到了。
    //    两个字段都要收：转账的转入端只出现在 `to_account_id` 上。
    final rows = await txn.query(
      'txn',
      columns: ['account_id', 'to_account_id'],
      where: 'ledger_id = ?',
      whereArgs: [id],
    );
    final touched = <int>{
      for (final r in rows) ...[
        if (r['account_id'] != null) r['account_id']! as int,
        if (r['to_account_id'] != null) r['to_account_id']! as int,
      ],
    };

    // ② 子表在前、主表在后
    await txn.delete('txn', where: 'ledger_id = ?', whereArgs: [id]);
    await txn.delete('debt', where: 'ledger_id = ?', whereArgs: [id]);
    await txn.delete('budget', where: 'ledger_id = ?', whereArgs: [id]);
    await txn.delete('recurring', where: 'ledger_id = ?', whereArgs: [id]);
    await txn.delete('txn_template', where: 'ledger_id = ?', whereArgs: [id]);
    // 分类：子分类的 parent_id 是同一张表里的软关联，一起删掉才不留孤儿
    await txn.delete('category', where: 'ledger_id = ?', whereArgs: [id]);
    await txn.delete('ledger', where: 'id = ?', whereArgs: [id]);

    // ③ 余额回滚：按「期初 + 剩余流水」**重算**受影响账户。
    //
    //    为什么重算而不是逐笔反向 `_applyBalanceDelta`：逐笔要先读回整行、
    //    按类型分正负号，等于把增量维护的公式抄第二遍；而重算用的
    //    `kAccountFlowSql` 与体检、与「重算余额」是**同一份公式**，
    //    结果可判定 —— 「重算之后体检必过」是能被测试钉住的事实。
    //
    //    口径：**不动 `opening_cents`**。期初是用户手填的基准，删一本账不该
    //    改写它；被删的那部分流水回到「没发生过」的状态，于是余额也回到
    //    「这些钱没花过」。想「这笔花费永久留在账户上」是另一种口径，
    //    那会让余额与明细对不上，体检照样报红。
    for (final accountId in touched) {
      await txn.rawUpdate(
        'UPDATE account SET balance_cents = opening_cents + '
        "${kAccountFlowSql('?')} WHERE id = ?",
        // 片段里 accountRef 出现 4 次，加上末尾 WHERE id = ? 共 5 个参数
        [accountId, accountId, accountId, accountId, accountId],
      );
    }
  });
}

/// 某账本名下的记账笔数（含转账、含借贷流水）—— 删除前的二次确认要说出这个数。
///
/// 用 `COUNT(*)` 而不是查列表再取长度：确认弹窗只要一个数字，
/// 把几万行读进内存只为数一遍没有意义。
Future<int> _repoLedgerTxnCount(int ledgerId) async {
  final db = await Db.open();
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM txn WHERE ledger_id = ?',
    [ledgerId],
  );
  return (rows.first['n'] as int?) ?? 0;
}
