import 'package:sqflite/sqflite.dart';

import 'cycle.dart';
import 'db.dart';
import 'models.dart';

/// 数据访问层。所有 SQL 集中在这里，页面不直接碰数据库。
class Repo {
  Repo._();

  // ---------------------------------------------------------------- 通用设置

  static Future<String?> getSetting(String key) async {
    final db = await Db.open();
    final rows = await db.query('setting', where: 'k = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['v'] as String;
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await Db.open();
    await db.insert('setting', {
      'k': key,
      'v': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> currentLedgerId() async {
    final v = await getSetting('current_ledger_id');
    if (v != null) {
      final id = int.tryParse(v);
      if (id != null) return id;
    }
    final ledgers = await listLedgers();
    if (ledgers.isEmpty) {
      final db = await Db.open();
      final id = await db.insert('ledger', {
        'name': '日常账本',
        'icon': 'book',
        'sort_order': 0,
        'archived': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await setSetting('current_ledger_id', '$id');
      return id;
    }
    await setSetting('current_ledger_id', '${ledgers.first.id}');
    return ledgers.first.id;
  }

  // ------------------------------------------------------------------- 账本

  static Future<List<Ledger>> listLedgers({
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

  static Future<int> insertLedger(Ledger l) async {
    final db = await Db.open();
    final id = await db.insert('ledger', l.toMap());
    // 新账本要带上默认分类，否则记一笔时没分类可选
    await _seedCategoriesFor(db, id);
    return id;
  }

  static Future<void> updateLedger(Ledger l) async {
    final db = await Db.open();
    await db.update('ledger', l.toMap(), where: 'id = ?', whereArgs: [l.id]);
  }

  /// 删除账本会级联删掉它的分类与交易（外键 ON DELETE CASCADE）
  static Future<void> deleteLedger(int id) async {
    final db = await Db.open();
    await db.delete('ledger', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _seedCategoriesFor(Database db, int ledgerId) async {
    const expense = [
      ('餐饮', 'food'),
      ('交通', 'transport'),
      ('购物', 'shopping'),
      ('居住', 'home'),
      ('娱乐', 'fun'),
      ('医疗', 'medical'),
      ('学习', 'study'),
      ('通讯', 'comm'),
      ('人情', 'gift'),
      ('其他', 'more'),
    ];
    const income = [
      ('工资', 'salary'),
      ('奖金', 'bonus'),
      ('兼职', 'parttime'),
      ('理财', 'invest'),
      ('红包', 'redpacket'),
      ('其他', 'more'),
    ];
    var order = 0;
    for (final (name, icon) in expense) {
      await db.insert('category', {
        'ledger_id': ledgerId,
        'type': 'expense',
        'name': name,
        'icon': icon,
        'sort_order': order++,
        'archived': 0,
      });
    }
    order = 0;
    for (final (name, icon) in income) {
      await db.insert('category', {
        'ledger_id': ledgerId,
        'type': 'income',
        'name': name,
        'icon': icon,
        'sort_order': order++,
        'archived': 0,
      });
    }
  }

  // ------------------------------------------------------------------- 账户

  static Future<List<Account>> listAccounts({
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
  static Future<int> totalBalanceCents() async {
    final db = await Db.open();
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(balance_cents), 0) AS t FROM account '
      'WHERE archived = 0 AND include_in_total = 1',
    );
    return (r.first['t'] as int?) ?? 0;
  }

  static Future<int> insertAccount(Account a) async {
    final db = await Db.open();
    return db.insert('account', a.toMap());
  }

  static Future<void> updateAccount(Account a) async {
    final db = await Db.open();
    await db.update('account', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
  }

  static Future<void> deleteAccount(int id) async {
    final db = await Db.open();
    await db.delete('account', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------- 分类

  static Future<List<Category>> listCategories(
    int ledgerId, {
    TxnType? type,
    bool includeArchived = false,
  }) async {
    final db = await Db.open();
    final where = StringBuffer('ledger_id = ?');
    final args = <Object?>[ledgerId];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.code);
    }
    if (!includeArchived) where.write(' AND archived = 0');
    final rows = await db.query(
      'category',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'sort_order, id',
    );
    return rows.map(Category.fromMap).toList();
  }

  static Future<int> insertCategory(Category c) async {
    final db = await Db.open();
    // 两级上限：父级自己必须是一级分类，否则就会长出第三层。
    // 数据层拦一道，比在界面上藏入口可靠 —— 导入 Excel、恢复备份都会走这里。
    if (c.parentId != null) {
      final parent = await db.query(
        'category',
        columns: ['parent_id'],
        where: 'id = ?',
        whereArgs: [c.parentId],
        limit: 1,
      );
      if (parent.isEmpty || parent.first['parent_id'] != null) {
        throw ArgumentError('子分类的父级必须是一级分类');
      }
    }
    return db.insert('category', c.toMap());
  }

  static Future<void> updateCategory(Category c) async {
    final db = await Db.open();
    await db.update('category', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  /// 分类被删时，历史交易的 `category_id` 置空（不连带删交易）。
  ///
  /// 删一级分类会**连同它的子分类一起删**：子分类失去父级之后既不会出现在
  /// 轮盘里，也没法在界面上找到，留着只会变成孤儿行。
  static Future<void> deleteCategory(int id) async {
    final db = await Db.open();
    await db.transaction((txn) async {
      final subs = await txn.query(
        'category',
        columns: ['id'],
        where: 'parent_id = ?',
        whereArgs: [id],
      );
      final ids = [id, ...subs.map((r) => r['id'] as int)];
      final marks = List.filled(ids.length, '?').join(',');
      await txn.update(
        'txn',
        {'category_id': null},
        where: 'category_id IN ($marks)',
        whereArgs: ids,
      );
      // 指向这些分类的预算也要一起清掉，否则会留下查不到分类的预算行
      await txn.delete(
        'budget',
        where: 'category_id IN ($marks)',
        whereArgs: ids,
      );
      await txn.delete('category', where: 'id IN ($marks)', whereArgs: ids);
    });
  }

  // --------------------------------------------------------------- 周期（F5）

  /// 账单日（周期起始日）设置键。默认 1 = 自然月，老用户升级后行为完全不变。
  static const cycleStartDayKey = 'cycle_start_day';

  /// 抬期池（D23）：只有这三类收入默认算进「下一期」。
  /// 兼职 / 理财 / 红包 / 其他不进池 —— 零星收入按真实日期更准，抬期反而失真。
  static const liftableIncomeNames = {'工资', '奖金', '提成'};

  /// 当前账单日，1–31；非法值一律回落到 1。
  static Future<int> cycleStartDay() async {
    final raw = await getSetting(cycleStartDayKey);
    return (int.tryParse(raw ?? '') ?? 1).clamp(1, 31);
  }

  /// 某账本里属于「抬期池」的收入分类 id。
  ///
  /// 白名单只按**分类名**判定，用户改名/删掉分类后自动失效 —— 这正是设计里
  /// 「白名单只决定默认值」的意思：真正落库前每笔仍可手动改（阶段 5 的开关）。
  static Future<Set<int>> liftableCategoryIds(int ledgerId) async {
    final db = await Db.open();
    return _liftableCategoryIds(db, ledgerId);
  }

  static Future<Set<int>> _liftableCategoryIds(
    DatabaseExecutor db,
    int ledgerId,
  ) async {
    final keys = liftableIncomeNames.toList();
    final rows = await db.query(
      'category',
      columns: ['id'],
      where:
          'ledger_id = ? AND type = ? '
          'AND name IN (${List.filled(keys.length, '?').join(',')})',
      whereArgs: [ledgerId, TxnType.income.code, ...keys],
    );
    return rows.map((r) => r['id'] as int).toSet();
  }

  /// 一条记录算在哪一期 —— 判定「这笔该不该抬期」的唯一入口。
  /// 区间与抬期规则本身在 `cycle.dart` 的 [periodStartOf] 里，不在这里重写一遍。
  ///
  /// [liftToNext] 为 null 时按分类白名单给默认值；给了 true/false 就是用户在
  /// 记一笔面板里手动拨过的结果（设计 §5.2：白名单只决定初值，最终值听用户的）。
  static String periodFor(
    Txn t,
    int startDay,
    Set<int> liftableIds, {
    bool? liftToNext,
  }) {
    final lift =
        liftToNext ??
        (t.type.isIncome &&
            t.categoryId != null &&
            liftableIds.contains(t.categoryId));
    return periodStartOf(t.date, startDay, liftToNext: lift);
  }

  /// 写入用的行（补上 `period_start`）。
  ///
  /// `Txn.toMap()` 故意不带这个字段：归属期是派生值，只能由 [periodFor] 算。
  /// 别处不要自己拼 map 直接 insert —— 漏算一条，这笔就会从某一期里凭空消失，
  /// 而且列表条数和合计对不上时极难定位。
  static Map<String, Object?> _txnRow(Txn t, String period) => {
    ...t.toMap(),
    'period_start': period,
  };

  /// 重算某账本全部记录的归属期（改账单日后必须调，否则历史全部错位）。
  ///
  /// 返回真正被改写的行数。实现是「一次查询 + 一次 batch」，不是逐条 await：
  /// 几千行仍在毫秒级，且只写有变化的行。为什么不写成一条 SQL —— 短月收拢
  /// （D14）和抬期白名单（D23）落到 SQL 里要两层 CASE + julianday，还会跟
  /// [periodStartOf] 各维护一份口径；口径漂移的代价远大于几毫秒。
  static Future<int> rebuildPeriods(int ledgerId) =>
      _recomputePeriods(ledgerId: ledgerId);

  /// 补齐 `period_start` 为空的记录（升级到 v4 后首次启动 / 从旧备份恢复后）。
  static Future<int> backfillMissingPeriods() =>
      _recomputePeriods(onlyMissing: true);

  static Future<int> _recomputePeriods({
    int? ledgerId,
    bool onlyMissing = false,
  }) async {
    final db = await Db.open();
    final startDay = await cycleStartDay();

    final where = StringBuffer();
    final args = <Object?>[];
    if (ledgerId != null) {
      where.write('ledger_id = ?');
      args.add(ledgerId);
    }
    if (onlyMissing) {
      if (where.isNotEmpty) where.write(' AND ');
      where.write('period_start IS NULL');
    }

    final rows = await db.query(
      'txn',
      columns: [
        'id',
        'ledger_id',
        'type',
        'date',
        'category_id',
        'period_start',
      ],
      where: where.isEmpty ? null : where.toString(),
      whereArgs: args.isEmpty ? null : args,
    );
    if (rows.isEmpty) return 0;

    // 每个账本的白名单各查一次，不按行查
    final liftable = <int, Set<int>>{};
    for (final lid in rows.map((r) => r['ledger_id'] as int).toSet()) {
      liftable[lid] = await _liftableCategoryIds(db, lid);
    }

    final updates = <(int, String)>[];
    for (final r in rows) {
      final type = TxnType.fromCode((r['type'] as String?) ?? 'expense');
      final categoryId = r['category_id'] as int?;
      final ids = liftable[r['ledger_id']] ?? const <int>{};
      final period = periodStartOf(
        r['date'] as String,
        startDay,
        liftToNext:
            type.isIncome && categoryId != null && ids.contains(categoryId),
      );
      if (period != r['period_start']) {
        updates.add((r['id'] as int, period));
      }
    }
    if (updates.isEmpty) return 0;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final (id, period) in updates) {
        batch.update(
          'txn',
          {'period_start': period},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await batch.commit(noResult: true);
    });
    return updates.length;
  }

  // ------------------------------------------------------------------- 交易

  static Future<int> insertTxn(Txn t, {bool? liftToNext}) async {
    final db = await Db.open();
    final startDay = await cycleStartDay();
    final liftable = await _liftableCategoryIds(db, t.ledgerId);
    final id = await db.insert(
      'txn',
      _txnRow(t, periodFor(t, startDay, liftable, liftToNext: liftToNext)),
    );
    await _applyBalanceDelta(db, t, reverse: false);
    return id;
  }

  static Future<void> updateTxn(Txn old, Txn now, {bool? liftToNext}) async {
    final db = await Db.open();
    final startDay = await cycleStartDay();
    final liftable = await _liftableCategoryIds(db, now.ledgerId);
    await db.transaction((txn) async {
      await _applyBalanceDelta(txn, old, reverse: true);
      await txn.update(
        'txn',
        _txnRow(
          now,
          periodFor(now, startDay, liftable, liftToNext: liftToNext),
        ),
        where: 'id = ?',
        whereArgs: [now.id],
      );
      await _applyBalanceDelta(txn, now, reverse: false);
    });
  }

  static Future<void> deleteTxn(Txn t) async {
    final db = await Db.open();
    await db.transaction((txn) async {
      await _applyBalanceDelta(txn, t, reverse: true);
      await txn.delete('txn', where: 'id = ?', whereArgs: [t.id]);
    });
  }

  /// 账户余额随交易增减。
  /// [reverse] 为 true 时反向回滚（改单/删单前先回滚旧值）。
  static Future<void> _applyBalanceDelta(
    DatabaseExecutor db,
    Txn t, {
    required bool reverse,
  }) async {
    if (t.type == TxnType.transfer) {
      // 转账：转出账户减、转入账户加
      final sign = reverse ? -1 : 1;
      if (t.accountId != null) {
        await db.rawUpdate(
          'UPDATE account SET balance_cents = balance_cents + ? WHERE id = ?',
          [-t.amountCents * sign, t.accountId],
        );
      }
      if (t.toAccountId != null) {
        await db.rawUpdate(
          'UPDATE account SET balance_cents = balance_cents + ? WHERE id = ?',
          [t.amountCents * sign, t.toAccountId],
        );
      }
      return;
    }
    if (t.accountId == null) return;
    final delta = t.type.isIncome ? t.amountCents : -t.amountCents;
    await db.rawUpdate(
      'UPDATE account SET balance_cents = balance_cents + ? WHERE id = ?',
      [reverse ? -delta : delta, t.accountId],
    );
  }

  // ------------------------------------------------------------------- 借贷

  /// 记一笔借贷：建 `debt` 记录 + 本金流水，同一事务，要么都成要么都不成。
  ///
  /// 本金流水的方向**由方向决定**（借出=支出、借入=收入），不接受调用方传，
  /// 否则「借出却记成收入」会让账户余额反向。两条都带 `debt_id`，统计一律排除。
  static Future<int> createDebt(
    Debt debt,
    Txn principal, {
    bool? liftToNext,
  }) async {
    final db = await Db.open();
    final startDay = await cycleStartDay();
    final liftable = await _liftableCategoryIds(db, debt.ledgerId);
    late int debtId;
    await db.transaction((txn) async {
      // 借出恒不计入预算：钱出去了，不是可花的钱。入口只给「借入」显示这个开关，
      // 但口径由数据层兜住，不指望每个调用方都记得传 false。
      final map = debt.toMap();
      if (debt.direction.isReceivable) map['count_in_budget'] = 0;
      debtId = await txn.insert('debt', map);
      final row = principal.copyWith(
        debtId: debtId,
        type: debt.direction.isMoneyOut ? TxnType.expense : TxnType.income,
      );
      await txn.insert(
        'txn',
        _txnRow(row, periodFor(row, startDay, liftable, liftToNext: liftToNext)),
      );
      await _applyBalanceDelta(txn, row, reverse: false);
    });
    return debtId;
  }

  /// 某账本的全部借贷：未结清优先 → 有应还日的在前 → 应还日升序。
  ///
  /// `repaid_cents` 在这里按流水汇总，不落库：本金方向是「借出支出 / 借入收入」，
  /// 还款方向正好相反，所以借出数 income、借入数 expense。
  static Future<List<Debt>> listDebts({required int ledgerId}) async {
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
  static Future<void> repayDebt({
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
    final db = await Db.open();
    final startDay = await cycleStartDay();
    final liftable = await _liftableCategoryIds(db, debt.ledgerId);
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
    await db.transaction((txn) async {
      await txn.insert(
        'txn',
        _txnRow(t, periodFor(t, startDay, liftable)),
      );
      await _applyBalanceDelta(txn, t, reverse: false);
      if (amountCents >= remain) {
        await txn.update(
          'debt',
          {'closed_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [debt.id],
        );
      }
    });
  }

  /// 手动结清 / 撤销结清。结清只改状态，不动流水与余额 ——
  /// 「钱已经还完了但流水没记」这种账，用户自己承担，App 不去编造一笔。
  static Future<void> setDebtClosed(int debtId, {required bool closed}) async {
    final db = await Db.open();
    await db.update(
      'debt',
      {'closed_at': closed ? DateTime.now().toIso8601String() : null},
      where: 'id = ?',
      whereArgs: [debtId],
    );
  }

  static Future<void> deleteDebt(int debtId) async {
    final db = await Db.open();
    await db.transaction((txn) async {
      // 先回滚余额：把挂在这笔上的流水逐条反向应用
      final rows = await txn.query('txn', where: 'debt_id = ?', whereArgs: [debtId]);
      for (final r in rows) {
        await _applyBalanceDelta(txn, Txn.fromMap(r), reverse: true);
      }
      await txn.delete('txn', where: 'debt_id = ?', whereArgs: [debtId]);
      await txn.delete('debt', where: 'id = ?', whereArgs: [debtId]);
    });
  }

  /// 往来摘要：应收合计、应付合计、这段日期内到期且未结清的笔数。
  ///
  /// 金额取**剩余**而不是本金 —— 已经还掉的部分不该再算进「还欠多少」。
  static Future<({int receivable, int payable, int dueSoon})> debtSummary({
    required int ledgerId,
    required String from,
    required String to,
  }) async {
    final debts = await listDebts(ledgerId: ledgerId);
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

  /// 某月明细（按月倒排日期、同日按 id 倒排）—— [rangeListTxns] 的薄委托。
  static Future<List<Txn>> listTxns({
    required int ledgerId,
    required String month,
    TxnType? type,
    int? categoryId,
    String? keyword,
    int limit = 500,
    int offset = 0,
  }) => rangeListTxns(
    ledgerId: ledgerId,
    from: monthStart(month),
    to: monthEnd(month),
    type: type,
    categoryId: categoryId,
    keyword: keyword,
    limit: limit,
    offset: offset,
  );

  /// 某一期的明细，条件打在 `period_start` 上；排序仍按真实 `date`。
  static Future<List<Txn>> rangeListTxns({
    required int ledgerId,
    required String from,
    required String to,
    TxnType? type,
    int? categoryId,
    String? keyword,
    int limit = 500,
    int offset = 0,
    DateBasis basis = DateBasis.period,
  }) async {
    final db = await Db.open();
    final where = StringBuffer(
      'ledger_id = ? AND ${_col(basis)} BETWEEN ? AND ?',
    );
    final args = <Object?>[ledgerId, from, to];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.code);
    }
    if (categoryId != null) {
      where.write(' AND $_catScope');
      args
        ..add(categoryId)
        ..add(categoryId);
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.write(' AND $_keywordWhere');
      final k = '%${keyword.trim()}%';
      for (var i = 0; i < _keywordCols.length; i++) {
        args.add(k);
      }
    }
    final rows = await db.query(
      'txn',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// 跨月检索：关键词（备注）+ 多条件筛选，全部 AND 组合。
  ///
  /// 返回 `(结果, 是否被上限截断)`。多查一条来判定截断 —— 只返回列表的话，
  /// 「正好 500 条」和「500 条之外还有」在调用方无法区分，界面上那句
  /// 「仅显示前 500 条」就落不了地。
  ///
  /// ★ 列表有上限，**合计没有**（D20）：合计走 [sumFiltered] 单独聚合。
  ///   拿列表相加当合计，超过 [searchLimit] 时数字会偏小，而条件条上还写着
  ///   「仅显示前 500 条」—— 用户看到两个互相矛盾的数字。
  static const int searchLimit = 500;

  /// 交叉归集的求和表达式（支出侧 / 收入侧）。
  ///
  /// 负数按交叉口径：支出里的负数算进收入，收入里的负数算进支出。
  /// [monthTotals] 与 [sumFiltered] 共用这两段，避免两处口径漂移。
  ///
  /// **借贷流水一律算 0**：借出去的钱不是消费，收回来的也不是收入。
  /// 排除条件写在这两个表达式里而不是各查询的 WHERE —— 只写 WHERE 的话，
  /// 哪天有人新加一个只用表达式、不复用 WHERE 的查询，就会漏掉。
  static const _expSumSql =
      'COALESCE(SUM(CASE '
      '  WHEN debt_id IS NOT NULL THEN 0 '
      "  WHEN type = 'expense' AND amount_cents >= 0 THEN amount_cents "
      "  WHEN type = 'income'  AND amount_cents <  0 THEN -amount_cents "
      '  ELSE 0 END), 0)';
  static const _incSumSql =
      'COALESCE(SUM(CASE '
      '  WHEN debt_id IS NOT NULL THEN 0 '
      "  WHEN type = 'income'  AND amount_cents >= 0 THEN amount_cents "
      "  WHEN type = 'expense' AND amount_cents <  0 THEN -amount_cents "
      '  ELSE 0 END), 0)';

  /// 关键词要搜的列。备注之外还要带上 v6 的详情字段 ——
  /// 记了「红包 · 对象=张三」却搜不到「张三」，那这个字段等于白填。
  static const _keywordCols = [
    'note',
    'person',
    'subject',
    'place_from',
    'place_to',
  ];

  static final _keywordWhere =
      '(${_keywordCols.map((c) => '$c LIKE ?').join(' OR ')})';

  /// 「按某个分类筛」的条件：**把它的子分类一起带上**。
  ///
  /// 两级分类之后绝大多数记录挂在子分类上（餐饮 / 正餐）。只写
  /// `category_id = ?` 的话，选「餐饮」会筛出 0 条 —— 而那正是最常被点的格子。
  /// 子分类用子查询找，不把 id 列表拼进 `IN`：拼列表在分类多时会撞 SQLite 的
  /// 参数上限，而这里只需多一个参数。
  static const _catScope =
      '(category_id = ? OR category_id IN '
      '(SELECT id FROM category WHERE parent_id = ?))';

  /// 明细查询的公共 WHERE。
  ///
  /// 列表（[searchTxns]）与合计（[sumFiltered]）必须共用同一份条件，
  /// 否则「列表 500 条、合计却按 501 条算」这类错位迟早会出现。
  static (String, List<Object?>) _txnWhere({
    required int ledgerId,
    String? keyword,
    TxnFilter? filter,
  }) {
    final where = <String>['ledger_id = ?'];
    final args = <Object?>[ledgerId];

    final k = keyword?.trim() ?? '';
    if (k.isNotEmpty) {
      where.add(_keywordWhere);
      for (var i = 0; i < _keywordCols.length; i++) {
        args.add('%$k%');
      }
    }
    if (filter?.type != null) {
      where.add('type = ?');
      args.add(filter!.type!.code);
    }
    if (filter?.categoryId != null) {
      where.add(_catScope);
      args
        ..add(filter!.categoryId)
        ..add(filter.categoryId);
    }
    final accountId = filter?.accountId;
    if (accountId != null) {
      // 转账的转出与转入都算「涉及该账户」；漏掉 to_account_id 会让转账记录凭空消失
      where.add('(account_id = ? OR to_account_id = ?)');
      args
        ..add(accountId)
        ..add(accountId);
    }
    if (filter?.minCents != null) {
      where.add('amount_cents >= ?');
      args.add(filter!.minCents);
    }
    if (filter?.maxCents != null) {
      where.add('amount_cents <= ?');
      args.add(filter!.maxCents);
    }
    if (filter?.dateFrom != null) {
      where.add('date >= ?');
      args.add(filter!.dateFrom);
    }
    if (filter?.dateTo != null) {
      where.add('date <= ?');
      args.add(filter!.dateTo);
    }
    return (where.join(' AND '), args);
  }

  static Future<(List<Txn>, bool)> searchTxns({
    required int ledgerId,
    String? keyword,
    TxnFilter? filter,
    int limit = searchLimit,
  }) async {
    final (whereSql, args) = _txnWhere(
      ledgerId: ledgerId,
      keyword: keyword,
      filter: filter,
    );

    final db = await Db.open();
    final rows = await db.query(
      'txn',
      where: whereSql,
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
      limit: limit + 1, // 多取一条，只为判断有没有被截断
    );
    final truncated = rows.length > limit;
    final page = truncated ? rows.sublist(0, limit) : rows;
    return (page.map(Txn.fromMap).toList(), truncated);
  }

  /// 筛选结果的合计：`(支出, 收入, 笔数)`。
  ///
  /// 与 [searchTxns] 共用同一份 WHERE，但**不受 [searchLimit] 截断影响**（D20）：
  /// 汇总交给 SQLite 做，笔数永远是真实的。口径与 [monthTotals] 一致
  /// （负数交叉归集，转账两侧都不参与）。
  static Future<(int expense, int income, int count)> sumFiltered({
    required int ledgerId,
    String? keyword,
    TxnFilter? filter,
  }) async {
    final (whereSql, args) = _txnWhere(
      ledgerId: ledgerId,
      keyword: keyword,
      filter: filter,
    );

    final db = await Db.open();
    final r = await db.rawQuery(
      'SELECT $_expSumSql AS exp, $_incSumSql AS inc, COUNT(*) AS cnt '
      'FROM txn WHERE $whereSql',
      args,
    );
    final row = r.first;
    return (
      (row['exp'] as int?) ?? 0,
      (row['inc'] as int?) ?? 0,
      (row['cnt'] as int?) ?? 0,
    );
  }

  /// 最近 [count] 个月（含 [endMonth]）的收支合计，按月升序。
  ///
  /// 统计页的「近 6 个月」用。逐月调 [monthTotals] 是有意的：
  /// 一条 GROUP BY 走 substr(date,1,7) 反而用不上索引，而这里最多 6 次、
  /// 每次都是毫秒级（实测 5000 条 1.4ms），没必要为它加复杂度。
  static Future<List<(String month, int expense, int income)>> recentMonths({
    required int ledgerId,
    required String endMonth,
    int count = 6,
  }) async {
    final y = int.parse(endMonth.substring(0, 4));
    final m = int.parse(endMonth.substring(5, 7));
    final out = <(String, int, int)>[];
    for (var i = count - 1; i >= 0; i--) {
      final d = DateTime(y, m - i);
      final ym = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final t = await rangeTotals(
        ledgerId,
        '$ym-01',
        '$ym-${Fmt.daysInMonth(d.year, d.month).toString().padLeft(2, '0')}',
        basis: DateBasis.date,
      );
      out.add((ym, t.$1, t.$2));
    }
    return out;
  }

  /// 最近 [count] 期（含 [endFrom] 那一期）的收支合计，按期升序。
  ///
  /// 统计页的「近 6 期」用。逐期调 [rangeTotals] 与 [recentMonths] 同理由：
  /// 最多 6 次、每次毫秒级，不值得为它写一条按周期分组的复杂 SQL。
  static Future<List<(String from, int expense, int income)>> recentPeriods({
    required int ledgerId,
    required String endFrom,
    required int startDay,
    int count = 6,
  }) async {
    final out = <(String, int, int)>[];
    final base = DateTime.parse(endFrom);
    for (var i = count - 1; i >= 0; i--) {
      final from = Fmt.date(shiftCycle(base, startDay, -i));
      final to = Fmt.date(
        shiftCycle(
          DateTime.parse(from),
          startDay,
          1,
        ).subtract(const Duration(days: 1)),
      );
      final t = await rangeTotals(ledgerId, from, to);
      out.add((from, t.$1, t.$2));
    }
    return out;
  }

  /// 全量备份涉及的业务表，按**父表在前**的顺序排列。
  ///
  /// 清空时反向遍历（子表先删），回填时正向插入；ID 一律原样保留，
  /// 这样 `txn.category_id` / `account_id` 这些软关联恢复后仍然成立。
  static const backupTables = <String>[
    'ledger',
    'account',
    'category',
    // debt 必须在 txn 之前：txn.debt_id 指向它。删除时反向遍历，txn 先走。
    'debt',
    'txn',
    'budget',
    'saving_goal',
    'recurring',
    'txn_template',
    'setting',
  ];

  /// 把 10 张表整个读出来（备份用）。行是原始 map，交给上层序列化。
  ///
  /// 老备份（v6 及以前）里没有 `debt` 这一项，恢复时按空表处理 ——
  /// 借贷是 v7 才有的，旧账本本来就没有往来。
  static Future<Map<String, List<Map<String, Object?>>>> dumpTables() async {
    final db = await Db.open();
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in backupTables) {
      out[t] = await db.query(t);
    }
    return out;
  }

  /// 整库覆盖式回填，返回每张表写入的行数。
  ///
  /// **必须在事务里**：中途任何一张表失败都要整体回滚，
  /// 否则会留下「记账记录已经清了、分类还没回来」的半截库。
  ///
  /// [keepSettings] 是不跟着备份走、但也不该被清掉的设置项
  /// （应用名、实验开关这类「这台机器的状态」），在同一个事务里补回去。
  static Future<Map<String, int>> replaceTables(
    Map<String, List<Map<String, Object?>>> data, {
    Map<String, String> keepSettings = const {},
  }) async {
    final db = await Db.open();
    final counts = <String, int>{};
    await db.transaction((txn) async {
      for (final t in backupTables.reversed) {
        await txn.delete(t);
      }
      for (final t in backupTables) {
        final rows = <Map<String, Object?>>[...?data[t]];
        counts[t] = rows.length;
        if (t == 'setting' && keepSettings.isNotEmpty) {
          for (final e in keepSettings.entries) {
            rows.add({'k': e.key, 'v': e.value});
          }
        }
        final batch = txn.batch();
        for (final row in rows) {
          batch.insert(
            t,
            _normalizeBackupRow(t, row),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
    });
    // 旧备份（v3 及更早）里没有 period_start，回填一次即可；新备份自带，等于空跑
    await backfillMissingPeriods();
    return counts;
  }

  /// 把旧格式备份里的行改写成当前 schema 的形状。
  ///
  /// 现在只有一处：v4 及更早的备份里 `budget` 按 `month` 存，v5 起按
  /// `period_start` 存。直接插会报「没有 month 列」，所以在这里换算一次。
  /// 账单日默认 1 时 `2026-10` → `2026-10-01` 是无损的。
  static Map<String, Object?> _normalizeBackupRow(
    String table,
    Map<String, Object?> row,
  ) {
    if (table != 'budget') return row;
    if (row.containsKey('period_start')) return row;
    final month = row['month'] as String?;
    if (month == null) return row;
    final out = Map<String, Object?>.from(row)
      ..remove('month')
      ..['period_start'] = '$month-01';
    return out;
  }

  /// 读出全部设置项（键值对），恢复时用来保留机器状态
  static Future<Map<String, String>> listSettings() async {
    final db = await Db.open();
    final rows = await db.query('setting');
    return {for (final r in rows) r['k'] as String: r['v'] as String};
  }

  /// 月收支合计。
  ///
  /// 阶段 3 起只是 [rangeTotals] 的薄委托：`month` 折算成月初/月末。账单日
  /// 默认 1 时 `period_start` 就是月初，结果与按 `date` 查完全一致。
  static Future<(int expense, int income, int count)> monthTotals(
    int ledgerId,
    String month,
  ) => rangeTotals(ledgerId, monthStart(month), monthEnd(month));

  /// 归集口径对应的字段名：周期视图筛 `period_start`，月份视图筛 `date`。
  static String _col(DateBasis basis) =>
      basis == DateBasis.period ? 'period_start' : 'date';

  /// 某一期的收支合计。[from] / [to] 是该期的首尾日期（含两端）。
  ///
  /// 条件打在 **`period_start`** 上，不是 `date` —— 这是周期归集的口径：
  /// 10-10 到账的工资被抬进 10-15 那一期后，就该算在那一期里。
  static Future<(int expense, int income, int count)> rangeTotals(
    int ledgerId,
    String from,
    String to, {
    DateBasis basis = DateBasis.period,
  }) async {
    final db = await Db.open();
    final r = await db.rawQuery(
      // 负数交叉归集：支出里的负数算进收入，收入里的负数算进支出
      'SELECT $_expSumSql AS exp, $_incSumSql AS inc, COUNT(*) AS cnt '
      'FROM txn WHERE ledger_id = ? AND ${_col(basis)} BETWEEN ? AND ?',
      [ledgerId, from, to],
    );
    final row = r.first;
    return (
      (row['exp'] as int?) ?? 0,
      (row['inc'] as int?) ?? 0,
      (row['cnt'] as int?) ?? 0,
    );
  }

  /// 分类聚合（饼图 / 排行）。结果按金额降序，直接对应灰阶由深到浅。
  static Future<List<CatStat>> categoryStats({
    required int ledgerId,
    required String month,
    required TxnType type,
  }) => rangeCategoryStats(
    ledgerId: ledgerId,
    from: monthStart(month),
    to: monthEnd(month),
    type: type,
  );

  /// 某一期的分类聚合（[categoryStats] 的区间版）
  static Future<List<CatStat>> rangeCategoryStats({
    required int ledgerId,
    required String from,
    required String to,
    required TxnType type,
    DateBasis basis = DateBasis.period,
  }) async {
    final db = await Db.open();
    // 对侧类型：支出饼要吸收「收入里的负数」，反之亦然
    final other = type == TxnType.income ? TxnType.expense : TxnType.income;
    final rows = await db.rawQuery(
      // 本侧的正数 + 对侧的负数（金额取绝对值）—— 与 rangeTotals 的口径保持一致，
      // 否则饼图分项之和会跟合计对不上
      //
      // **按根分类聚合**：两级分类之后，交易可能挂在子分类（正餐）上，
      // 也可能直接挂一级（餐饮）。饼图与排行只按一级呈现，所以用
      // `COALESCE(p.id, c.id)` 把子分类折回它的一级；未分类时三者都空，
      // 落在同一组里显示为「未分类」。
      'SELECT COALESCE(p.id, c.id) AS cid, '
      "  COALESCE(p.name, c.name, '未分类') AS name, "
      "  COALESCE(p.icon, c.icon, 'more')  AS icon, "
      '  SUM(CASE WHEN t.amount_cents < 0 THEN -t.amount_cents'
      '          ELSE t.amount_cents END) AS total, '
      '  COUNT(*) AS cnt '
      'FROM txn t '
      '  LEFT JOIN category c ON c.id = t.category_id '
      '  LEFT JOIN category p ON p.id = c.parent_id '
      'WHERE t.ledger_id = ? AND t.${_col(basis)} BETWEEN ? AND ? '
      '  AND t.debt_id IS NULL '
      '  AND ((t.type = ? AND t.amount_cents >= 0)'
      '    OR (t.type = ? AND t.amount_cents < 0)) '
      'GROUP BY COALESCE(p.id, c.id) '
      'ORDER BY total DESC',
      [ledgerId, from, to, type.code, other.code],
    );
    return rows
        .map(
          (m) => CatStat(
            categoryId: (m['cid'] as int?) ?? -1,
            name: m['name'] as String,
            icon: m['icon'] as String,
            totalCents: (m['total'] as int?) ?? 0,
            count: (m['cnt'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// 每日收支（趋势图）—— 月的薄委托，见 [rangeDailyTotals]。
  static Future<List<(String date, int expense, int income)>> dailyTotals(
    int ledgerId,
    String month,
  ) => rangeDailyTotals(ledgerId, monthStart(month), monthEnd(month));

  /// 某一期的每日收支（趋势图）。
  ///
  /// **筛的是归属期，分组仍按真实 `date`** —— 趋势图的柱子代表「那天花了多少」，
  /// 把它挪到账单日会变成谎报。所以一笔 10-10 的工资在 10-15 那一期里，
  /// 仍然显示在 10-10 这根柱子上。
  static Future<List<(String date, int expense, int income)>> rangeDailyTotals(
    int ledgerId,
    String from,
    String to, {
    DateBasis basis = DateBasis.period,
  }) async {
    final db = await Db.open();
    final rows = await db.rawQuery(
      'SELECT date, '
      '  COALESCE(SUM(CASE '
      "    WHEN type = 'expense' AND amount_cents >= 0 THEN amount_cents "
      "    WHEN type = 'income'  AND amount_cents <  0 THEN -amount_cents "
      '    ELSE 0 END), 0) AS exp, '
      '  COALESCE(SUM(CASE '
      "    WHEN type = 'income'  AND amount_cents >= 0 THEN amount_cents "
      "    WHEN type = 'expense' AND amount_cents <  0 THEN -amount_cents "
      '    ELSE 0 END), 0) AS inc '
      'FROM txn WHERE ledger_id = ? AND ${_col(basis)} BETWEEN ? AND ? '
      '  AND debt_id IS NULL '
      'GROUP BY date ORDER BY date',
      [ledgerId, from, to],
    );
    return rows
        .map(
          (m) => (
            m['date'] as String,
            (m['exp'] as int?) ?? 0,
            (m['inc'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// 有记账记录的年月集合，用于月份选择器做「有数据的月份」提示
  static Future<Set<String>> monthsWithData(int ledgerId) async {
    final db = await Db.open();
    final rows = await db.rawQuery(
      'SELECT DISTINCT substr(date, 1, 7) AS ym FROM txn WHERE ledger_id = ?',
      [ledgerId],
    );
    return rows.map((m) => m['ym'] as String).toSet();
  }

  // ------------------------------------------------------------------- 预算

  /// 某一期的预算明细（`category_id IS NULL` 那条是总预算）
  static Future<List<Budget>> listBudgets(
    int ledgerId,
    String periodStart,
  ) async {
    final db = await Db.open();
    final rows = await db.query(
      'budget',
      where: 'ledger_id = ? AND period_start = ?',
      whereArgs: [ledgerId, periodStart],
    );
    return rows.map(Budget.fromMap).toList();
  }

  /// 总预算（category_id 为 NULL 的那条）
  static Future<int?> totalBudgetCents(int ledgerId, String periodStart) async {
    final db = await Db.open();
    final rows = await db.query(
      'budget',
      columns: ['amount_cents'],
      where: 'ledger_id = ? AND period_start = ? AND category_id IS NULL',
      whereArgs: [ledgerId, periodStart],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['amount_cents'] as int?) ?? 0;
  }

  static Future<void> setBudget({
    required int ledgerId,
    required String periodStart,
    int? categoryId,
    required int amountCents,
  }) async {
    final db = await Db.open();
    if (amountCents <= 0) {
      await db.delete(
        'budget',
        where:
            'ledger_id = ? AND period_start = ? AND '
            '${categoryId == null ? 'category_id IS NULL' : 'category_id = ?'}',
        whereArgs: [ledgerId, periodStart, ?categoryId],
      );
      return;
    }
    await db.insert('budget', {
      'ledger_id': ledgerId,
      'period_start': periodStart,
      'category_id': categoryId,
      'amount_cents': amountCents,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 改账单日后，把预算挪到新的归属期上。
  ///
  /// 预算的 key 是 `period_start`，账单日一变，原来那些 key 就落在期中间了
  /// （10-15 起的一期，在账单日改回 1 号后已经不存在）。规则是：
  /// **按「旧期第一天」找到它现在落进哪一期**，挪过去。
  ///
  /// 两条旧预算可能挤进同一期（期变长时），此时**金额相加**而不是让后一条
  /// 覆盖前一条 —— 覆盖等于凭空吃掉一笔预算，用户只会觉得「我的预算少了」。
  static Future<int> remapBudgetPeriods(int startDay) async {
    final db = await Db.open();
    final rows = await db.query(
      'budget',
      columns: ['ledger_id', 'period_start', 'category_id', 'amount_cents'],
    );
    if (rows.isEmpty) return 0;

    final merged = <(int, String, int?), int>{};
    for (final r in rows) {
      final newStart = periodStartOf(r['period_start'] as String, startDay);
      final key = (r['ledger_id'] as int, newStart, r['category_id'] as int?);
      merged[key] = (merged[key] ?? 0) + ((r['amount_cents'] as int?) ?? 0);
    }

    await db.transaction((txn) async {
      await txn.delete('budget');
      final batch = txn.batch();
      merged.forEach((key, amount) {
        batch.insert('budget', {
          'ledger_id': key.$1,
          'period_start': key.$2,
          'category_id': key.$3,
          'amount_cents': amount,
        });
      });
      await batch.commit(noResult: true);
    });
    return merged.length;
  }

  /// 分类预算 + 实际支出 —— 计划页进度条的数据源。
  /// 返回结果包含**设置了预算的分类**，以及**有支出但没设预算的分类**
  /// （后者 budgetCents 为 0，用于展示「未设预算」）。
  ///
  /// [periodStart] 决定读哪一期的预算；[from] / [to] 是该期的首尾日期，
  /// 支出按 `period_start` 归集 —— 与明细页的「本期支出」同口径。
  static Future<List<BudgetStat>> budgetStats({
    required int ledgerId,
    required String periodStart,
    required String from,
    required String to,
  }) async {
    final db = await Db.open();
    final rows = await db.rawQuery(
      // 只列一级分类（`parent_id IS NULL`）：预算设在「餐饮」上，
      // 不该出现「正餐」。已用金额则要**含该一级下的所有子分类**，
      // 否则把交易记到子分类之后，餐饮的预算进度条永远不动。
      'SELECT c.id AS cid, c.name AS name, c.icon AS icon, '
      '  b.amount_cents AS budget, '
      '  COALESCE((SELECT SUM(t.amount_cents) FROM txn t '
      '     JOIN category tc ON tc.id = t.category_id '
      "     WHERE COALESCE(tc.parent_id, tc.id) = c.id AND t.type = 'expense' "
      '       AND t.debt_id IS NULL '
      '       AND t.period_start BETWEEN ? AND ?), 0) AS spent '
      'FROM category c '
      'LEFT JOIN budget b ON b.category_id = c.id '
      '  AND b.ledger_id = c.ledger_id AND b.period_start = ? '
      "WHERE c.ledger_id = ? AND c.type = 'expense' AND c.archived = 0 "
      '  AND c.parent_id IS NULL '
      '  AND (b.amount_cents IS NOT NULL OR spent > 0) '
      'ORDER BY (b.amount_cents IS NULL), b.amount_cents DESC',
      [from, to, periodStart, ledgerId],
    );
    return rows
        .map(
          (m) => BudgetStat(
            categoryId: (m['cid'] as int?) ?? -1,
            name: m['name'] as String,
            icon: m['icon'] as String,
            spentCents: (m['spent'] as int?) ?? 0,
            budgetCents: (m['budget'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  // --------------------------------------------------------------- 储蓄目标

  static Future<List<SavingGoal>> listGoals({
    bool includeArchived = false,
  }) async {
    final db = await Db.open();
    final rows = await db.query(
      'saving_goal',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'sort_order, id',
    );
    return rows.map(SavingGoal.fromMap).toList();
  }

  static Future<int> insertGoal(SavingGoal g) async {
    final db = await Db.open();
    return db.insert('saving_goal', g.toMap());
  }

  static Future<void> updateGoal(SavingGoal g) async {
    final db = await Db.open();
    await db.update(
      'saving_goal',
      g.toMap(),
      where: 'id = ?',
      whereArgs: [g.id],
    );
  }

  static Future<void> deleteGoal(int id) async {
    final db = await Db.open();
    await db.delete('saving_goal', where: 'id = ?', whereArgs: [id]);
  }

  /// 存钱 / 取钱（金额可为负）
  static Future<void> addFunds(int goalId, int deltaCents) async {
    final db = await Db.open();
    await db.rawUpdate(
      'UPDATE saving_goal SET saved_cents = MAX(0, saved_cents + ?) WHERE id = ?',
      [deltaCents, goalId],
    );
  }

  // --------------------------------------------------------------- 周期账单

  static Future<List<RecurringRule>> listRecurring(
    int ledgerId, {
    bool onlyEnabled = false,
  }) async {
    final db = await Db.open();
    final rows = await db.query(
      'recurring',
      where: onlyEnabled ? 'ledger_id = ? AND enabled = 1' : 'ledger_id = ?',
      whereArgs: [ledgerId],
      orderBy: 'next_run_date, id',
    );
    return rows.map(RecurringRule.fromMap).toList();
  }

  static Future<int> insertRecurring(RecurringRule r) async {
    final db = await Db.open();
    return db.insert('recurring', r.toMap());
  }

  static Future<void> updateRecurring(RecurringRule r) async {
    final db = await Db.open();
    await db.update('recurring', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
  }

  static Future<void> deleteRecurring(int id) async {
    final db = await Db.open();
    await db.delete('recurring', where: 'id = ?', whereArgs: [id]);
  }

  /// 补记所有到期的周期账单。
  ///
  /// ★ 单机应用没有后台服务，做不到「到点自动执行」。
  ///   真实机制就是这里：**打开 App 时扫一遍 `next_run_date <= 今天` 的规则**，
  ///   逐条生成交易，然后把 `next_run_date` 推进到下一次。
  ///   交易日期用**规则本应触发的日期**，而不是补记当天 —— 否则账目会错位。
  ///
  /// 返回补记的条数，便于在界面上给用户一个提示。
  static Future<int> runDueRecurring(int ledgerId, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final todayStr = Fmt.date(today);
    final db = await Db.open();

    final rows = await db.query(
      'recurring',
      where: 'ledger_id = ? AND enabled = 1 AND next_run_date <= ?',
      whereArgs: [ledgerId, todayStr],
      orderBy: 'next_run_date',
    );

    // 归属期在补记时一次算好，跟手动记一笔同口径（周期账单不抬期由白名单决定）
    final startDay = await cycleStartDay();
    final liftable = await _liftableCategoryIds(db, ledgerId);

    var created = 0;
    for (final row in rows) {
      var rule = RecurringRule.fromMap(row);
      // 单条规则连续欠多期时逐期补，最多 60 期防止死循环
      var guard = 0;
      while (rule.nextRunDate.compareTo(todayStr) <= 0 && guard++ < 60) {
        final runDate = rule.nextRunDate;
        if (rule.endDate != null && runDate.compareTo(rule.endDate!) > 0) {
          break;
        }
        await db.transaction((txn) async {
          final t = Txn(
            id: 0,
            ledgerId: ledgerId,
            type: rule.type,
            amountCents: rule.amountCents,
            date: runDate,
            categoryId: rule.categoryId,
            accountId: rule.accountId,
            note: rule.note.isEmpty ? '周期账单' : rule.note,
            recurringId: rule.id,
          );
          await txn.insert('txn', _txnRow(t, periodFor(t, startDay, liftable)));
          await _applyBalanceDelta(txn, t, reverse: false);
          created++;
        });

        final next = _advance(runDate, rule.freq, rule.interval);
        rule = RecurringRule(
          id: rule.id,
          ledgerId: rule.ledgerId,
          type: rule.type,
          amountCents: rule.amountCents,
          categoryId: rule.categoryId,
          accountId: rule.accountId,
          note: rule.note,
          freq: rule.freq,
          interval: rule.interval,
          nextRunDate: next,
          endDate: rule.endDate,
          enabled: rule.enabled,
        );
        await db.update(
          'recurring',
          rule.toMap(),
          where: 'id = ?',
          whereArgs: [rule.id],
        );
      }
    }
    return created;
  }

  static String _advance(String date, String freq, int interval) {
    final d = DateTime.parse(date);
    final step = interval < 1 ? 1 : interval;
    switch (freq) {
      case 'daily':
        return Fmt.date(d.add(Duration(days: step)));
      case 'weekly':
        return Fmt.date(d.add(Duration(days: 7 * step)));
      case 'yearly':
        return Fmt.date(_clampMonth(d.year + step, d.month, d.day));
      case 'monthly':
      default:
        final m = d.month + step;
        final year = d.year + (m - 1) ~/ 12;
        final month = (m - 1) % 12 + 1;
        return Fmt.date(_clampMonth(year, month, d.day));
    }
  }

  /// 月末对齐：1月31日 + 1个月 → 2月28/29日，而不是溢出到 3月
  static DateTime _clampMonth(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > last ? last : day);
  }

  // ------------------------------------------------------------------- 模板

  /// 管理页用的顺序：用户拖出来的顺序优先
  static Future<List<TxnTemplate>> listTemplates(int ledgerId) async {
    final db = await Db.open();
    final rows = await db.query(
      'txn_template',
      where: 'ledger_id = ?',
      whereArgs: [ledgerId],
      orderBy: 'sort_order, id',
    );
    return rows.map(TxnTemplate.fromMap).toList();
  }

  /// 记一笔面板顶部那排「常用模板」：用得多的在前，同频次看最近用过谁
  static Future<List<TxnTemplate>> recentTemplates(
    int ledgerId, {
    int limit = 3,
  }) async {
    final db = await Db.open();
    final rows = await db.query(
      'txn_template',
      where: 'ledger_id = ?',
      whereArgs: [ledgerId],
      orderBy:
          "use_count DESC, COALESCE(last_used_at, '') DESC, sort_order, id",
      limit: limit,
    );
    return rows.map(TxnTemplate.fromMap).toList();
  }

  static Future<int> insertTemplate(TxnTemplate t) async {
    final db = await Db.open();
    // 新模板排到最后
    final r = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM txn_template WHERE ledger_id = ?',
      [t.ledgerId],
    );
    final order = (r.first['n'] as int?) ?? 0;
    return db.insert('txn_template', t.copyWith(sortOrder: order).toMap());
  }

  static Future<void> updateTemplate(TxnTemplate t) async {
    final db = await Db.open();
    await db.update(
      'txn_template',
      t.toMap(),
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  static Future<void> deleteTemplate(int id) async {
    final db = await Db.open();
    await db.delete('txn_template', where: 'id = ?', whereArgs: [id]);
  }

  /// 用了一次模板 —— 只动统计列，不动用户填的内容
  static Future<void> touchTemplate(int id) async {
    final db = await Db.open();
    await db.rawUpdate(
      'UPDATE txn_template SET use_count = use_count + 1, last_used_at = ? '
      'WHERE id = ?',
      [DateTime.now().toIso8601String(), id],
    );
  }

  /// 拖动排序：把当前顺序整体写回 sort_order
  static Future<void> reorderTemplates(List<int> orderedIds) async {
    final db = await Db.open();
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'txn_template',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  /// 按传入顺序重写分类的 `sort_order`（0..n-1）。
  ///
  /// 只动排序，不碰名称、图标、停用状态。停用的分类不参与排序 ——
  /// 管理页把它们单独排在下面，拖的是「使用中」那一段。
  static Future<void> reorderCategories(List<int> orderedIds) async {
    final db = await Db.open();
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'category',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  /// 停用 / 恢复一个分类。
  ///
  /// 不级联：停用一级分类时，它的子分类保持原状。理由是一级分类消失后，
  /// 子分类本来就到不了（选择器先选一级再选二级），级联反而会让「恢复一级」
  /// 顺手把用户单独停用过的子分类也放出来。
  static Future<void> setCategoryArchived(int id, {required bool archived}) async {
    final db = await Db.open();
    await db.update(
      'category',
      {'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // -------------------------------------------------------------------- 工具

  /// 月份参数统一成日期区间，这样能吃到 `idx_txn_ledger_date` 索引；
  /// 用 `LIKE '2026-10%'` 也行但走不了索引。
  static String monthStart(String ym) => '$ym-01';

  static String monthEnd(String ym) {
    final p = ym.split('-');
    final y = int.parse(p[0]);
    final m = int.parse(p[1]);
    final last = DateTime(y, m + 1, 0).day;
    return '$ym-${last.toString().padLeft(2, '0')}';
  }
}
