part of '../store.dart';

// ---------------------------------------------------------------------------
// 用例方法：一次调用完成「写库 → 刷新投影」
// ---------------------------------------------------------------------------
//
// 1.5.0 之前这两步分写在页面里：
//
//     await Repo.insertGoal(...);
//     await Store.i.afterGoalChange();
//
// 忘掉第二句**不会报错**，只会让界面停在旧数字。下面每个方法都是一个完整的
// 写用例，页面只调一次。这与 `WriteGateway` 消灭「忘记开事务」是同一个思路：
// **让错误在结构上不成立**，而不是靠 review 时记得。
//
// ## 为什么是 extension 而不是留在类里
//
// 类体不能跨文件（`part` 是顶层文本插入，不能续写 class），而 `store.dart`
// 已经 1000+ 行。用例方法只依赖**公开**的 `afterXxxChange` / `loadTemplates`
// 与只读投影，天然是一个可以独立成组的"面"，用 extension 搬出去即可 ——
// 调用点 `Store.i.addTxn(...)` 一行都不用改。
//
// ## 约定
//
// - 只读查询不进这里：页面直接调 `Repo.listXxx` 不会产生不一致状态；
// - 返回值与 Repo 对齐（新建返回 id、批量返回条数），页面不必再查一遍；
// - 新增一个写用例时，同步在 `test/store_actions_test.dart` 加一条用例，
//   并且**同时断言「库变了」和「投影变了」**。
// ---------------------------------------------------------------------------

extension StoreActions on Store {
  // ---------------------------------------------------------- 用例方法
  //
  // 「写库 → 刷新」必须成对发生。1.5.0 之前这两步分写在页面里：
  //
  //     await Repo.insertGoal(...);
  //     await Store.i.afterGoalChange();
  //
  // 忘掉第二句**不会报错**，只会让界面停在旧数字；而且未必有测试能抓到
  // （除非恰好有一条用例断言了刷新后的值）。下面每个方法都是一个完整的
  // 写用例：调 Repo、再调对应的 after，页面只调一次。
  //
  // 这与 `WriteGateway` 消灭「忘记开事务」是同一个思路 ——
  // **让错误在结构上不成立**，而不是靠 review 时记得。
  //
  // 约定：
  // - 只读查询不进这里：页面直接调 `Repo.listXxx` 不会产生不一致状态；
  // - 返回值与 Repo 对齐（新建返回 id、批量返回条数），页面不必再查一遍。

  /// 归属期算法只有一处：`Repo.periodFor`（内部转 `cycle.periodStartOf`）。
  /// 这里不自己拼，避免「提示文案里的期」与「真正落库的期」算成两个。
  String _periodOf(Txn t, {bool? liftToNext}) =>
      Repo.periodFor(t, _cycleStartDay, _liftableCatIds, liftToNext: liftToNext);

  // ---- 流水

  /// 新增一笔：写库 → 记一次模板使用 → 把视角搬到这笔身上。
  ///
  /// 返回归属期首日：记一笔面板要拿它拼「已记入 10-15 至 11-14」，
  /// 调用方不该再按另一套规则算第二遍。
  Future<String> addTxn(
    Txn t, {
    bool? liftToNext,
    int? touchTemplateId,
  }) async {
    await Repo.insertTxn(t, liftToNext: liftToNext);
    if (touchTemplateId != null) {
      await Repo.touchTemplate(touchTemplateId);
      // 只重载、不通知：末尾 afterTxnInserted 会统一发一次
      await loadTemplates();
    }
    final periodStart = _periodOf(t, liftToNext: liftToNext);
    await afterTxnInserted(date: t.date, periodStart: periodStart);
    return periodStart;
  }

  /// 改一笔：写库 → 原地刷新。
  ///
  /// 不跳期：用户正在看的就是那一行，把视角搬走等于打断他。
  Future<void> updateTxn(Txn old, Txn now, {bool? liftToNext}) async {
    await Repo.updateTxn(old, now, liftToNext: liftToNext);
    await afterTxnChange();
  }

  /// 删除一笔（账户余额由 Repo 在同事务里回滚）
  Future<void> deleteTxn(Txn t) async {
    await Repo.deleteTxn(t);
    await afterTxnChange();
  }

  /// 批量删除，返回实际删除条数
  Future<int> deleteTxns(List<Txn> items) async {
    final n = await Repo.batchDeleteTxns(items);
    await afterTxnChange();
    return n;
  }

  /// 批量改分类，返回实际改动条数
  Future<int> setTxnsCategory(List<Txn> items, int? categoryId) async {
    final n = await Repo.batchSetCategory(
      ledgerId: _ledgerId,
      txnIds: [for (final t in items) t.id],
      categoryId: categoryId,
    );
    await afterTxnChange();
    return n;
  }

  /// 导入账单（Repo 内按账户反补期初，余额不动）→ 刷新
  Future<int> importBillRows(List<Txn> txns) async {
    final n = await Repo.importBillRows(txns: txns);
    await afterTxnChange();
    return n;
  }

  /// 从 Excel 导入（选文件 → 解析 → 写库都在 `ExcelService` 里）→ 刷新。
  ///
  /// 用户取消时返回 null，此时**不刷新**（什么都没写，重查一遍纯属浪费）。
  Future<ImportResult?> importExcel() async {
    final result = await ExcelService.pickAndImport(_ledgerId);
    if (result != null) await afterTxnChange();
    return result;
  }

  // ---- 借贷

  /// 新建往来（本金流水同事务写入），并把视角搬到这笔。
  Future<String> addDebt(Debt debt, Txn principal) async {
    await Repo.createDebt(debt, principal);
    // 本金流水一律不抬期：借出去的钱不是「支撑下一期生活的工资」
    final periodStart = _periodOf(principal, liftToNext: false);
    await afterTxnInserted(date: principal.date, periodStart: periodStart);
    return periodStart;
  }

  Future<void> repayDebt({
    required Debt debt,
    required int amountCents,
    required int accountId,
    required String date,
  }) async {
    await Repo.repayDebt(
      debt: debt,
      amountCents: amountCents,
      accountId: accountId,
      date: date,
    );
    await afterTxnChange();
  }

  Future<void> setDebtClosed(int debtId, {required bool closed}) async {
    await Repo.setDebtClosed(debtId, closed: closed);
    await afterTxnChange();
  }

  Future<void> deleteDebt(int debtId) async {
    await Repo.deleteDebt(debtId);
    await afterTxnChange();
  }

  // ---- 账户

  /// 新建或保存账户。
  ///
  /// 手填余额改的是**期初**（`opening_cents`），不是余额本身：余额由
  /// `期初 + 流水` 决定，直接改余额会让恒等式当场不成立。
  /// 新建时还没有流水，所以期初 = 手填余额。
  Future<int> saveAccount(Account a, {required int balanceCents}) async {
    final int id;
    if (a.id == 0) {
      id = await Repo.insertAccount(
        a.copyWith(balanceCents: balanceCents, openingCents: balanceCents),
      );
    } else {
      await Repo.saveAccount(a, balanceCents);
      id = a.id;
    }
    await afterAccountChange();
    return id;
  }

  Future<void> deleteAccount(int id) async {
    await Repo.deleteAccount(id);
    await afterAccountChange();
  }

  Future<void> mergeAccount({required int from, required int to}) async {
    await Repo.mergeAccount(from: from, to: to);
    await afterAccountChange();
  }

  /// 设置 / 取消「默认支出账户」。
  ///
  /// 取消（[id] 为 null）写的是**空串**而不是删掉这一行：`setting` 表只有
  /// k/v 两列，读侧本来就会把「键不存在」和「值为空」折成同一个 null，
  /// 多写一条 DELETE 只是多一条会出错的语句。
  ///
  /// ★ 这里**不校验**传进来的 id 还在不在：校验放在读取处（记账面板初始化时
  /// 回落到第一个账户）而不是写入处，是因为账户可能在设置之后才被删 ——
  /// 写入时校验得再严，也拦不住「先设默认、再删账户」这条正常操作。
  Future<void> setDefaultExpenseAccount(int? id) async {
    await Repo.setSetting(
      Store._kDefaultExpenseAccount,
      id == null ? '' : '$id',
    );
    _defaultExpenseAccountId = id;
    notifyListeners();
  }

  /// 新建账本并切过去；返回补记的周期账单条数（0 = 没有补记）
  Future<int> addLedger(String name) async {
    final id = await Repo.insertLedger(Ledger(id: 0, name: name));
    return switchLedger(id);
  }

  /// 删除账本（连同账内的流水 / 往来 / 预算 / 周期账单 / 模板 / 分类）。
  ///
  /// 删的若是**当前账本**，必须切走：所有查询都按 `_ledgerId` 过滤，留在一个
  /// 已删除的 id 上会让明细、分类、预算全部查空 —— 用户看到的是「数据没了」。
  /// 切走复用 [switchLedger] 那条路径（清筛选 → 重载 → 补记），不另开一套。
  ///
  /// 「只剩一个账本不许删」的规则放在界面层（`mine_page.dart`）：那是产品约束，
  /// 不是数据层约束 —— 测试或恢复流程直接调数据层时不该被它挡住。
  Future<void> deleteLedger(int id) async {
    final wasCurrent = id == _ledgerId;
    await Repo.deleteLedger(id);

    if (!wasCurrent) {
      // 删的是别的账本：只有账本列表变了，其它投影不受影响
      _ledgers = await Repo.listLedgers();
      notifyListeners();
      return;
    }

    final remaining = await Repo.listLedgers();
    if (remaining.isEmpty) {
      // 界面拦住了这种操作，真走到这里说明库里本来就只剩这一本：
      // 让 `currentLedgerId()` 自己建一本，别让界面停在一个已删的 id 上
      _ledgerId = await Repo.currentLedgerId();
      await loadAll();
      return;
    }
    await switchLedger(remaining.first.id);
  }

  /// 重算所有账户余额（体检页的修复动作）→ 刷新。
  ///
  /// 这里写的是 `balance_cents` 而不是 `opening_cents`：修的是「增量维护漏加
  /// 导致账面偏离」，期初是用户手填的基准，任何自动流程都不该动它。
  Future<int> recalcBalances() async {
    final fixed = await Integrity.recalcBalances();
    await afterAccountChange();
    return fixed;
  }

  // ---- 分类

  Future<int> saveCategory(Category c) async {
    final int id;
    if (c.id == 0) {
      id = await Repo.insertCategory(c);
    } else {
      await Repo.updateCategory(c);
      id = c.id;
    }
    await afterCategoryChange();
    return id;
  }

  Future<void> deleteCategory(int id) async {
    await Repo.deleteCategory(id);
    await afterCategoryChange();
  }

  Future<void> setCategoryArchived(int id, {required bool archived}) async {
    await Repo.setCategoryArchived(id, archived: archived);
    await afterCategoryChange();
  }

  Future<void> reorderCategories(List<int> orderedIds) async {
    await Repo.reorderCategories(orderedIds);
    await afterCategoryChange();
  }

  // ---- 预算

  Future<void> setBudget({
    required String periodStart,
    int? categoryId,
    required int amountCents,
  }) async {
    await Repo.setBudget(
      ledgerId: _ledgerId,
      periodStart: periodStart,
      categoryId: categoryId,
      amountCents: amountCents,
    );
    await afterBudgetChange();
  }

  // ---- 储蓄目标

  Future<int> saveGoal(SavingGoal g) async {
    final int id;
    if (g.id == 0) {
      id = await Repo.insertGoal(g);
    } else {
      await Repo.updateGoal(g);
      id = g.id;
    }
    await afterGoalChange();
    return id;
  }

  Future<void> deleteGoal(int id) async {
    await Repo.deleteGoal(id);
    await afterGoalChange();
  }

  /// 存钱 / 取钱（金额可为负）→ 刷新目标投影与流水。
  ///
  /// [date] 默认今天、[accountId] 可空（用户只想记一句「我存了 500」时不必
  /// 牵扯账户余额）、[note] 一句话备注。三者都会落到 `goal_flow` 那一行上 ——
  /// 「预计何时达成」全靠这张表算速率，漏传日期就等于把速率算错。
  Future<void> addFunds(
    int goalId,
    int deltaCents, {
    String? date,
    int? accountId,
    String note = '',
  }) async {
    await Repo.addFunds(
      goalId,
      deltaCents,
      date: date,
      accountId: accountId,
      note: note,
    );
    await afterGoalChange();
  }

  // ---- 模板

  Future<int> saveTemplate(TxnTemplate t) async {
    final int id;
    if (t.id == 0) {
      id = await Repo.insertTemplate(t);
    } else {
      await Repo.updateTemplate(t);
      id = t.id;
    }
    await afterTemplateChange();
    return id;
  }

  Future<void> deleteTemplate(int id) async {
    await Repo.deleteTemplate(id);
    await afterTemplateChange();
  }

  Future<void> reorderTemplates(List<int> orderedIds) async {
    await Repo.reorderTemplates(orderedIds);
    await afterTemplateChange();
  }
}
