import 'package:sqflite/sqflite.dart';

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
    await db.insert(
      'setting',
      {'k': key, 'v': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  static Future<List<Ledger>> listLedgers({bool includeArchived = false}) async {
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
      ('餐饮', 'food'), ('交通', 'transport'), ('购物', 'shopping'),
      ('居住', 'home'), ('娱乐', 'fun'), ('医疗', 'medical'),
      ('学习', 'study'), ('通讯', 'comm'), ('人情', 'gift'), ('其他', 'more'),
    ];
    const income = [
      ('工资', 'salary'), ('奖金', 'bonus'), ('兼职', 'parttime'),
      ('理财', 'invest'), ('红包', 'redpacket'), ('其他', 'more'),
    ];
    var order = 0;
    for (final (name, icon) in expense) {
      await db.insert('category', {
        'ledger_id': ledgerId, 'type': 'expense', 'name': name,
        'icon': icon, 'sort_order': order++, 'archived': 0,
      });
    }
    order = 0;
    for (final (name, icon) in income) {
      await db.insert('category', {
        'ledger_id': ledgerId, 'type': 'income', 'name': name,
        'icon': icon, 'sort_order': order++, 'archived': 0,
      });
    }
  }

  // ------------------------------------------------------------------- 账户

  static Future<List<Account>> listAccounts({bool includeArchived = false}) async {
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
    return db.insert('category', c.toMap());
  }

  static Future<void> updateCategory(Category c) async {
    final db = await Db.open();
    await db.update('category', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  /// 分类被删时，历史交易的 category_id 置空（不连带删交易）
  static Future<void> deleteCategory(int id) async {
    final db = await Db.open();
    await db.transaction((txn) async {
      await txn.update('txn', {'category_id': null},
          where: 'category_id = ?', whereArgs: [id]);
      await txn.delete('category', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ------------------------------------------------------------------- 交易

  static Future<int> insertTxn(Txn t) async {
    final db = await Db.open();
    final id = await db.insert('txn', t.toMap());
    await _applyBalanceDelta(db, t, reverse: false);
    return id;
  }

  static Future<void> updateTxn(Txn old, Txn now) async {
    final db = await Db.open();
    await db.transaction((txn) async {
      await _applyBalanceDelta(txn, old, reverse: true);
      await txn.update('txn', now.toMap(), where: 'id = ?', whereArgs: [now.id]);
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

  /// 某月明细（按月倒排日期、同日按 id 倒排）
  static Future<List<Txn>> listTxns({
    required int ledgerId,
    required String month,
    TxnType? type,
    int? categoryId,
    String? keyword,
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await Db.open();
    final where = StringBuffer('ledger_id = ? AND date BETWEEN ? AND ?');
    final args = <Object?>[
      ledgerId,
      monthStart(month),
      monthEnd(month),
    ];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.code);
    }
    if (categoryId != null) {
      where.write(' AND category_id = ?');
      args.add(categoryId);
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.write(' AND note LIKE ?');
      args.add('%${keyword.trim()}%');
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
  static const _expSumSql = 'COALESCE(SUM(CASE '
      "  WHEN type = 'expense' AND amount_cents >= 0 THEN amount_cents "
      "  WHEN type = 'income'  AND amount_cents <  0 THEN -amount_cents "
      '  ELSE 0 END), 0)';
  static const _incSumSql = 'COALESCE(SUM(CASE '
      "  WHEN type = 'income'  AND amount_cents >= 0 THEN amount_cents "
      "  WHEN type = 'expense' AND amount_cents <  0 THEN -amount_cents "
      '  ELSE 0 END), 0)';

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
      where.add('note LIKE ?');
      args.add('%$k%');
    }
    if (filter?.type != null) {
      where.add('type = ?');
      args.add(filter!.type!.code);
    }
    if (filter?.categoryId != null) {
      where.add('category_id = ?');
      args.add(filter!.categoryId);
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
      final t = await monthTotals(ledgerId, ym);
      out.add((ym, t.$1, t.$2));
    }
    return out;
  }

  /// 月收支合计
  static Future<(int expense, int income, int count)> monthTotals(
    int ledgerId,
    String month,
  ) async {
    final db = await Db.open();
    final r = await db.rawQuery(
      // 负数交叉归集：支出里的负数算进收入，收入里的负数算进支出
      'SELECT $_expSumSql AS exp, $_incSumSql AS inc, COUNT(*) AS cnt '
      'FROM txn WHERE ledger_id = ? AND date BETWEEN ? AND ?',
      [ledgerId, monthStart(month), monthEnd(month)],
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
  }) async {
    final db = await Db.open();
    // 对侧类型：支出饼要吸收「收入里的负数」，反之亦然
    final other = type == TxnType.income ? TxnType.expense : TxnType.income;
    final rows = await db.rawQuery(
      // 本侧的正数 + 对侧的负数（金额取绝对值）—— 与 monthTotals 的口径保持一致，
      // 否则饼图分项之和会跟合计对不上
      'SELECT t.category_id AS cid, '
      "  COALESCE(c.name, '未分类') AS name, "
      "  COALESCE(c.icon, 'more')  AS icon, "
      '  SUM(CASE WHEN t.amount_cents < 0 THEN -t.amount_cents'
      '          ELSE t.amount_cents END) AS total, '
      '  COUNT(*) AS cnt '
      'FROM txn t LEFT JOIN category c ON c.id = t.category_id '
      'WHERE t.ledger_id = ? AND t.date BETWEEN ? AND ? '
      '  AND ((t.type = ? AND t.amount_cents >= 0)'
      '    OR (t.type = ? AND t.amount_cents < 0)) '
      'GROUP BY t.category_id '
      'ORDER BY total DESC',
      [ledgerId, monthStart(month), monthEnd(month), type.code, other.code],
    );
    return rows
        .map((m) => CatStat(
              categoryId: (m['cid'] as int?) ?? -1,
              name: m['name'] as String,
              icon: m['icon'] as String,
              totalCents: (m['total'] as int?) ?? 0,
              count: (m['cnt'] as int?) ?? 0,
            ))
        .toList();
  }

  /// 每日收支（趋势图）
  static Future<List<(String date, int expense, int income)>> dailyTotals(
    int ledgerId,
    String month,
  ) async {
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
      'FROM txn WHERE ledger_id = ? AND date BETWEEN ? AND ? '
      'GROUP BY date ORDER BY date',
      [ledgerId, monthStart(month), monthEnd(month)],
    );
    return rows
        .map((m) => (
              m['date'] as String,
              (m['exp'] as int?) ?? 0,
              (m['inc'] as int?) ?? 0,
            ))
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

  static Future<List<Budget>> listBudgets(int ledgerId, String month) async {
    final db = await Db.open();
    final rows = await db.query(
      'budget',
      where: 'ledger_id = ? AND month = ?',
      whereArgs: [ledgerId, month],
    );
    return rows.map(Budget.fromMap).toList();
  }

  /// 总预算（category_id 为 NULL 的那条）
  static Future<int?> totalBudgetCents(int ledgerId, String month) async {
    final db = await Db.open();
    final rows = await db.query(
      'budget',
      columns: ['amount_cents'],
      where: 'ledger_id = ? AND month = ? AND category_id IS NULL',
      whereArgs: [ledgerId, month],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['amount_cents'] as int?) ?? 0;
  }

  static Future<void> setBudget({
    required int ledgerId,
    required String month,
    int? categoryId,
    required int amountCents,
  }) async {
    final db = await Db.open();
    if (amountCents <= 0) {
      await db.delete(
        'budget',
        where: 'ledger_id = ? AND month = ? AND '
            '${categoryId == null ? 'category_id IS NULL' : 'category_id = ?'}',
        whereArgs: [
          ledgerId,
          month,
          ?categoryId,
        ],
      );
      return;
    }
    await db.insert(
      'budget',
      {
        'ledger_id': ledgerId,
        'month': month,
        'category_id': categoryId,
        'amount_cents': amountCents,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 分类预算 + 实际支出 —— 计划页进度条的数据源。
  /// 返回结果包含**设置了预算的分类**，以及**有支出但没设预算的分类**
  /// （后者 budgetCents 为 0，用于展示「未设预算」）。
  static Future<List<BudgetStat>> budgetStats(
    int ledgerId,
    String month,
  ) async {
    final db = await Db.open();
    final rows = await db.rawQuery(
      'SELECT c.id AS cid, c.name AS name, c.icon AS icon, '
      '  b.amount_cents AS budget, '
      '  COALESCE((SELECT SUM(t.amount_cents) FROM txn t '
      "     WHERE t.category_id = c.id AND t.type = 'expense' "
      '       AND t.date BETWEEN ? AND ?), 0) AS spent '
      'FROM category c '
      'LEFT JOIN budget b ON b.category_id = c.id '
      '  AND b.ledger_id = c.ledger_id AND b.month = ? '
      "WHERE c.ledger_id = ? AND c.type = 'expense' AND c.archived = 0 "
      '  AND (b.amount_cents IS NOT NULL OR spent > 0) '
      'ORDER BY (b.amount_cents IS NULL), b.amount_cents DESC',
      [monthStart(month), monthEnd(month), month, ledgerId],
    );
    return rows
        .map((m) => BudgetStat(
              categoryId: (m['cid'] as int?) ?? -1,
              name: m['name'] as String,
              icon: m['icon'] as String,
              spentCents: (m['spent'] as int?) ?? 0,
              budgetCents: (m['budget'] as int?) ?? 0,
            ))
        .toList();
  }

  // --------------------------------------------------------------- 储蓄目标

  static Future<List<SavingGoal>> listGoals({bool includeArchived = false}) async {
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
    await db.update('saving_goal', g.toMap(), where: 'id = ?', whereArgs: [g.id]);
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
          await txn.insert('txn', t.toMap());
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
        await db.update('recurring', rule.toMap(),
            where: 'id = ?', whereArgs: [rule.id]);
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
      orderBy: "use_count DESC, COALESCE(last_used_at, '') DESC, sort_order, id",
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
    await db.update('txn_template', t.toMap(),
        where: 'id = ?', whereArgs: [t.id]);
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
