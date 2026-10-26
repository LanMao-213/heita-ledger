part of '../repo.dart';

// ---------------------------------------------------------------------------
// 流水（含归属期、检索、筛选聚合）：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  /// 一条记录算在哪一期 —— 判定「这笔该不该抬期」的唯一入口。
  /// 区间与抬期规则本身在 `cycle.dart` 的 [periodStartOf] 里，不在这里重写一遍。
  ///
  /// [liftToNext] 为 null 时按分类白名单给默认值；给了 true/false 就是用户在
  /// 记一笔面板里手动拨过的结果（设计 §5.2：白名单只决定初值，最终值听用户的）。
String _repoPeriodFor(
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
Map<String, Object?> _txnRow(Txn t, String period) => {
  ...t.toMap(),
  'period_start': period,
};

  /// 重算某账本全部记录的归属期（改账单日后必须调，否则历史全部错位）。
  ///
  /// 返回真正被改写的行数。实现是「一次查询 + 一次 batch」，不是逐条 await：
  /// 几千行仍在毫秒级，且只写有变化的行。为什么不写成一条 SQL —— 短月收拢
  /// （D14）和抬期白名单（D23）落到 SQL 里要两层 CASE + julianday，还会跟
  /// [periodStartOf] 各维护一份口径；口径漂移的代价远大于几毫秒。
Future<int> _repoRebuildPeriods(int ledgerId) =>
    _recomputePeriods(ledgerId: ledgerId);

  /// 补齐 `period_start` 为空的记录（升级到 v4 后首次启动 / 从旧备份恢复后）。
Future<int> _repoBackfillMissingPeriods() =>
    _recomputePeriods(onlyMissing: true);

Future<int> _recomputePeriods({
  int? ledgerId,
  bool onlyMissing = false,
}) async {
  final db = await Db.open();
  final startDay = await _repoCycleStartDay();

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
  //
  // ★ 从这里往下到「借贷」小节的五条写路径（insertTxn / updateTxn / deleteTxn /
  //   createDebt / repayDebt）全部走 `WriteGateway.run`：事务边界只有那一处，
  //   业务层拿不到 `Database`，所以「忘记开事务」在结构上不成立。
  //   其余写方法都是**单条 SQL**，本身就原子，不进网关。
Future<int> _repoInsertTxn(Txn t, {bool? liftToNext}) async {
  final startDay = await _repoCycleStartDay();
  final liftable = await _liftableCategoryIds(await Db.open(), t.ledgerId);
  return WriteGateway.run(
    _InsertTxn(
      t,
      _txnRow(t, _repoPeriodFor(t, startDay, liftable, liftToNext: liftToNext)),
    ),
  );
}

  /// 批量导入账单：插入流水 + 按账户反补期初，**一个事务**。
  ///
  /// ## 为什么补期初，而不是让余额变
  ///
  /// 导入的是「历史账单」——这些钱早就花出去了，用户此刻的账户余额里
  /// 本来就包含它们。若只插流水，余额会凭空再少一次。
  ///
  /// 做法：流水照常写（`余额 = 期初 + 流水合计` 这条恒等式不破），
  /// 同时把该账户的**期初**反向补齐同样的金额：
  ///     期初 += (支出合计 − 收入合计)
  /// 于是 `期初 + 流水` 的净变化为 0，**余额不动**。
  ///
  /// ★ 必须**按账户分别调**。一份账单跨 3 个账户时，按总额调会让
  ///   A 账户凭空多钱、B 账户凭空少钱，体检立刻报漂移（`integrity.dart`）。
  ///   这也是本方法不接收「一个总金额」的原因。
Future<int> _repoImportBillRows({required List<Txn> txns}) async {
  if (txns.isEmpty) return 0;
  final startDay = await _repoCycleStartDay();
  final ledgerId = txns.first.ledgerId;
  final liftable = await _liftableCategoryIds(await Db.open(), ledgerId);
  final rows = [
    for (final t in txns)
      // 导入的记录一律不抬期：抬期是「工资」这类收入的专属规则，
      // 账单里的收入行是不是工资，我们无从判断，宁可不动。
      _txnRow(t, _repoPeriodFor(t, startDay, liftable, liftToNext: false)),
  ];
  return WriteGateway.run(_ImportBills(txns, rows));
}

Future<void> _repoUpdateTxn(Txn old, Txn now, {bool? liftToNext}) async {
  final startDay = await _repoCycleStartDay();
  final liftable = await _liftableCategoryIds(await Db.open(), now.ledgerId);
  return WriteGateway.run(
    _UpdateTxn(
      old,
      now,
      _txnRow(now, _repoPeriodFor(now, startDay, liftable, liftToNext: liftToNext)),
    ),
  );
}

Future<void> _repoDeleteTxn(Txn t) => WriteGateway.run(_DeleteTxn(t));

  /// 批量删除，返回实际删除条数。
  ///
  /// 不循环调 [deleteTxn]：那样每条开一次事务、每次都要 `afterTxnChange`，
  /// 删几十条会卡住界面；更要紧的是中途失败会留下「删了一半」——
  /// 用户看到「已删除 20 笔」，其实只有 8 笔没了。
Future<int> _repoBatchDeleteTxns(List<Txn> items) =>
    WriteGateway.run(_DeleteTxns(items));

  /// 某月明细（按月倒排日期、同日按 id 倒排）—— [rangeListTxns] 的薄委托。
Future<List<Txn>> _repoListTxns({
  required int ledgerId,
  required String month,
  TxnType? type,
  int? categoryId,
  String? keyword,
  int limit = 500,
  int offset = 0,
}) => _repoRangeListTxns(
  ledgerId: ledgerId,
  from: Fmt.monthStart(month),
  to: Fmt.monthEnd(month),
  type: type,
  categoryId: categoryId,
  keyword: keyword,
  limit: limit,
  offset: offset,
);

  /// 某一期的明细，条件打在 `period_start` 上；排序仍按真实 `date`。
Future<List<Txn>> _repoRangeListTxns({
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
    'ledger_id = ? AND ${kDateCol(basis)} BETWEEN ? AND ?',
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
    final (kwSql, kwArgs) = _keywordClause(keyword.trim());
    where.write(' AND $kwSql');
    args.addAll(kwArgs);
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

  /// 关键词要搜的列。备注之外还要带上 v6 的详情字段 ——
  /// 记了「红包 · 对象=张三」却搜不到「张三」，那这个字段等于白填。
const _keywordCols = [
  'note',
  'person',
  'subject',
  'place_from',
  'place_to',
];

  /// 关键词匹配：文本列 + 分类名 + 账户名 + 金额。
  ///
  /// 为什么不止搜文本列（1.4.4）：用户脑海里的索引不是「我当初在备注里写了什么」，
  /// 而是「在餐饮花的」「38 块 5 那笔」「用支付宝付的」。只搜 note/person/subject/
  /// place_* 的话，这几条最常想的线索全都搜不到 —— 而 0 条结果看起来像「没记过」。
  ///
  /// 全部用**子查询**取 id，不在 Dart 里先查一遍再拼 `IN (...)`：
  /// 拼 id 列表在分类多时会撞 SQLite 的参数上限，而且列表与合计必须共用同一份
  /// 条件（[searchTxns] 和 [sumFiltered] 都走 [_txnWhere]），拼列表就得两处各拼一遍。
(String, List<Object?>) _keywordClause(String k) {
  final like = '%${_escapeLike(k)}%';
  // 分类：命中自己的名字，或者它父分类的名字。
  // 记录大多挂在子分类上（餐饮 / 正餐），用户搜的是「餐饮」。
  // 每个 LIKE 都带 `ESCAPE '\'`：不加的话，搜「50%」会命中全部记录，
  // 搜「a_b」会命中「aab」—— 关键词里的这两个字符必须当字面量。
  const catSql =
      'category_id IN (SELECT c.id FROM category c '
      'LEFT JOIN category p ON c.parent_id = p.id '
      "WHERE c.name LIKE ? ESCAPE '\\' OR p.name LIKE ? ESCAPE '\\')";
  // 账户：转出与转入都算「跟这个账户有关」
  const accSql =
      "(account_id IN (SELECT id FROM account WHERE name LIKE ? ESCAPE '\\') "
      "OR to_account_id IN (SELECT id FROM account "
      "WHERE name LIKE ? ESCAPE '\\'))";

  final parts = <String>[
    '(${_keywordCols.map((c) => "$c LIKE ? ESCAPE '\\'").join(' OR ')})',
    catSql,
    accSql,
  ];
  final args = <Object?>[
    for (var i = 0; i < _keywordCols.length; i++) like,
    like,
    like,
    like,
    like,
  ];

  // 金额只在「关键词就是个数字」时参与匹配。
  // 否则「午饭」也会被当成金额去比一遍；而且一位数（「1」）几乎能匹配全部记录，
  // 噪音会盖掉真正命中的那几条。所以要两位以上。
  final digits = k.replaceAll(RegExp(r'[^0-9]'), '');
  final isNumber = RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(k);
  if (isNumber && digits.length >= 2) {
    // 「38.5」→「385」，再在 amount_cents 的文本里找包含关系：
    // 38.50 / 138.50 / 3.85 都能被搜到，符合「我记不清具体多少」的用法
    parts.add("CAST(amount_cents AS TEXT) LIKE ? ESCAPE '\\'");
    args.add('%$digits%');
  }

  return ('(${parts.join(' OR ')})', args);
}

  /// 把关键词里的 `\` `%` `_` 转义成字面量（配合 SQL 里的 `ESCAPE '\'`）。
  ///
  /// 顺序不能反：先转义反斜杠本身，否则 `\%` 会被二次转义成 `\\%`，
  /// 反而变成「一个反斜杠 + 通配符」。
String _escapeLike(String raw) => raw
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

  /// 「按某个分类筛」的条件：**把它的子分类一起带上**。
  ///
  /// 两级分类之后绝大多数记录挂在子分类上（餐饮 / 正餐）。只写
  /// `category_id = ?` 的话，选「餐饮」会筛出 0 条 —— 而那正是最常被点的格子。
  /// 子分类用子查询找，不把 id 列表拼进 `IN`：拼列表在分类多时会撞 SQLite 的
  /// 参数上限，而这里只需多一个参数。
const _catScope =
    '(category_id = ? OR category_id IN '
    '(SELECT id FROM category WHERE parent_id = ?))';

  /// 明细查询的公共 WHERE。
  ///
  /// 列表（[searchTxns]）与合计（[sumFiltered]）必须共用同一份条件，
  /// 否则「列表 500 条、合计却按 501 条算」这类错位迟早会出现。
(String, List<Object?>) _txnWhere({
  required int ledgerId,
  String? keyword,
  TxnFilter? filter,
}) {
  final where = <String>['ledger_id = ?'];
  final args = <Object?>[ledgerId];

  final k = keyword?.trim() ?? '';
  if (k.isNotEmpty) {
    final (kwSql, kwArgs) = _keywordClause(k);
    where.add(kwSql);
    args.addAll(kwArgs);
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

  /// 批量改分类：一条 UPDATE，要么全中要么全不动。
  ///
  /// 为什么不逐条调 [updateTxn]：那会逐条重算归属期、逐条回滚再应用余额，
  /// 20 条就是 20 次事务、40 次余额写。分类既不参与余额也不改日期，
  /// 逐条走只会把风险放大 20 倍。
  ///
  /// 但**归属期确实可能变**：把记录改到「工资」这类抬期分类上时，它该落到
  /// 下一期。所以改完重算一次归属期 —— 漏了这步会出现「日期对、期归错」
  /// 的记录，而这在明细里几乎看不出来，只会在预算/汇总里悄悄错位。
Future<int> _repoBatchSetCategory({
  required int ledgerId,
  required List<int> txnIds,
  required int? categoryId,
}) async {
  if (txnIds.isEmpty) return 0;
  final db = await Db.open();
  final marks = List.filled(txnIds.length, '?').join(',');
  final n = await db.update(
    'txn',
    {'category_id': categoryId},
    where: 'ledger_id = ? AND id IN ($marks)',
    whereArgs: [ledgerId, ...txnIds],
  );
  if (n > 0) await _repoRebuildPeriods(ledgerId);
  return n;
}

  /// 按筛选条件取**全部**记录（导出用）。
  ///
  /// 与明细列表共用 [_txnWhere]：导出的行数必须和用户在屏幕上看到的一致。
  /// 条件写两遍迟早会漂（一处加了账户条件、另一处忘了），那次「导出 800 条、
  /// 列表 137 条」的解释成本远高于复用这一个小函数。
Future<List<Txn>> _repoTxnForExport({
  required int ledgerId,
  TxnFilter? filter,
}) async {
  final (whereSql, args) = _txnWhere(ledgerId: ledgerId, filter: filter);
  final db = await Db.open();
  final rows = await db.query(
    'txn',
    where: whereSql,
    whereArgs: args,
    orderBy: 'date ASC, id ASC',
  );
  return rows.map(Txn.fromMap).toList();
}

Future<(List<Txn>, bool)> _repoSearchTxns({
  required int ledgerId,
  String? keyword,
  TxnFilter? filter,
  int limit = Repo.searchLimit,
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
Future<(int expense, int income, int count)> _repoSumFiltered({
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
    'SELECT $kExpSumSql AS exp, $kIncSumSql AS inc, COUNT(*) AS cnt '
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

  /// 有记账记录的年月集合，用于月份选择器做「有数据的月份」提示
Future<Set<String>> _repoMonthsWithData(int ledgerId) async {
  final db = await Db.open();
  final rows = await db.rawQuery(
    'SELECT DISTINCT substr(date, 1, 7) AS ym FROM txn WHERE ledger_id = ?',
    [ledgerId],
  );
  return rows.map((m) => m['ym'] as String).toSet();
}
