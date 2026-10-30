part of '../repo.dart';

// ---------------------------------------------------------------------------
// 周期账单：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  // --------------------------------------------------------------- 周期账单
Future<List<RecurringRule>> _repoListRecurring(
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

Future<int> _repoInsertRecurring(RecurringRule r) async {
  final db = await Db.open();
  return db.insert('recurring', r.toMap());
}

Future<void> _repoUpdateRecurring(RecurringRule r) async {
  final db = await Db.open();
  await db.update('recurring', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
}

Future<void> _repoDeleteRecurring(int id) async {
  final db = await Db.open();
  await db.delete('recurring', where: 'id = ?', whereArgs: [id]);
}

  /// 补记所有到期的周期账单。
  ///
  /// ★ 单机应用没有后台服务，做不到「到点自动执行」。
  ///   真实机制就是这里：**扫一遍 `next_run_date <= 今天` 的规则**，
  ///   逐条生成交易，然后把 `next_run_date` 推进到下一次。
  ///   交易日期用**规则本应触发的日期**，而不是补记当天 —— 否则账目会错位。
  ///
  ///   1.4.4 起有**两个**触发点：冷启动（`Store.boot`）和「从后台回到前台」
  ///   （`Store.onAppResumed`）。加第二个是因为前者不够用：Android 上应用
  ///   常驻后台过夜是常态，只靠冷启动的话，1 号该扣的房租可能三天后才补记，
  ///   而这三天里余额和预算都是错的。
  ///
  ///   两个触发点意味着可能几乎同时调用，所以每期插入前都要查重（见下），
  ///   调用方还得负责按账本限流（`Store.catchUpRecurring`）。
  ///
  /// 返回补记的条数，便于在界面上给用户一个提示。
Future<int> _repoRunDueRecurring(int ledgerId, {DateTime? now}) async {
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
  final startDay = await _repoCycleStartDay();
  final liftable = await _liftableCategoryIds(db, ledgerId);

  var created = 0;
  for (final row in rows) {
    var rule = RecurringRule.fromMap(row);

    // 还原这条规则的「原始日」。`next_run_date` 是被 clamp 过的日期
    // （1-31 走到 2 月就写成 2-28），直接拿它递推会永久停在 28 号。
    // 用该规则**最早一笔流水**的日期反推：存量规则也能自愈。
    // `ux_txn_recurring_date` 是 (recurring_id, date) 唯一索引，MIN 走索引。
    final anchorRow = await db.rawQuery(
      'SELECT MIN(date) AS d FROM txn WHERE recurring_id = ?',
      [rule.id],
    );
    final anchorDate = anchorRow.first['d'] as String?;
    final anchorDay = anchorDate != null
        ? DateTime.parse(anchorDate).day
        : DateTime.parse(rule.nextRunDate).day;

    // 单条规则连续欠多期时逐期补，最多 60 期防止死循环
    var guard = 0;
    while (rule.nextRunDate.compareTo(todayStr) <= 0 && guard++ < 60) {
      final runDate = rule.nextRunDate;
      if (rule.endDate != null && runDate.compareTo(rule.endDate!) > 0) {
        break;
      }
      // 幂等护栏：这条规则的这一期已经有记录了就跳过，只推进日期。
      //
      // 为什么需要（1.4.4）：补记从一个触发点（冷启动）变成两个（再加上
      // 「从后台回到前台」）。`txn` 表对 `(recurring_id, date)` 没有唯一约束，
      // 两个触发点挨得近时会把同一条规则的同一期插两遍 —— 房租记成两份。
      // 不改成唯一索引是因为那要升 schema v8，而老库里若已存在重复行，
      // 建索引会直接失败；「插入前查一次」代价只有一次主键查找。
      //
      // 这条还没搬进 WriteGateway（它外面还有「推进 next_run_date」一段，
      // 整段搬进来要先把循环结构拆开）。这里只是把作用域包一层，
      // 让 `_applyBalanceDelta` 的签名统一 —— 行为与 1.4.4 完全一致。
      final inserted = await db.transaction((txn) async {
        final w = WriteScope(txn);
        final dup = await w.query(
          'txn',
          columns: const ['id'],
          where: 'recurring_id = ? AND date = ?',
          whereArgs: [rule.id, runDate],
          limit: 1,
        );
        if (dup.isNotEmpty) return false;

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
        await w.insert('txn', _txnRow(t, _repoPeriodFor(t, startDay, liftable)));
        await _applyBalanceDelta(w, t, reverse: false);
        return true;
      });
      if (inserted) created++;

      final next = _advance(
        runDate,
        rule.freq,
        rule.interval,
        anchorDay: anchorDay,
      );
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

String _advance(String date, String freq, int interval, {int? anchorDay}) {
  final d = DateTime.parse(date);
  final step = interval < 1 ? 1 : interval;
  // 月 / 年的递推必须回到「原始日」再 clamp，不能拿已经 clamp 过的日子当基数：
  // 1-31 走到 2 月被 clamp 成 2-28，再用 28 递推就永久停在 28 号，
  // 3-31、5-31 都不再回来（1.7.2 修）。
  final day = anchorDay ?? d.day;
  switch (freq) {
    case 'daily':
      return Fmt.date(d.add(Duration(days: step)));
    case 'weekly':
      return Fmt.date(d.add(Duration(days: 7 * step)));
    case 'yearly':
      return Fmt.date(_clampMonth(d.year + step, d.month, day));
    case 'monthly':
    default:
      final m = d.month + step;
      final year = d.year + (m - 1) ~/ 12;
      final month = (m - 1) % 12 + 1;
      return Fmt.date(_clampMonth(year, month, day));
  }
}

  /// 月末对齐：1月31日 + 1个月 → 2月28/29日，而不是溢出到 3月
DateTime _clampMonth(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}
