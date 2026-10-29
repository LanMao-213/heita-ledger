import 'package:sqflite/sqflite.dart';

import 'backup_compat.dart';
import 'command.dart';
import 'cycle.dart';
import 'db.dart';
import 'models.dart';
import 'sql_fragments.dart';

part 'repo/settings.dart';
part 'repo/ledger.dart';
part 'repo/account.dart';
part 'repo/category.dart';
part 'repo/txn.dart';
part 'repo/debt.dart';
part 'repo/budget.dart';
part 'repo/goal.dart';
part 'repo/recurring.dart';
part 'repo/template.dart';
part 'repo/backup.dart';
part 'repo/commands.dart';

/// 数据访问层。所有 SQL 集中在这里，页面不直接碰数据库。
class Repo {
  // --------------------------------------------------------------- 周期（F5）

  /// 账单日（周期起始日）设置键。默认 1 = 自然月，老用户升级后行为完全不变。
  static const cycleStartDayKey = 'cycle_start_day';

  /// 抬期池（D23）：只有这三类收入默认算进「下一期」。
  /// 兼职 / 理财 / 红包 / 其他不进池 —— 零星收入按真实日期更准，抬期反而失真。
  static const liftableIncomeNames = {'工资', '奖金', '提成'};

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
    // goal_flow 是 saving_goal 的子表（goal_id 软关联），必须排在它后面
    'goal_flow',
    'recurring',
    'txn_template',
    'setting',
  ];

  // ---------------------------------------------------------------- 通用设置
  static Future<String?> getSetting(String key) => _repoGetSetting(key);

  static Future<void> setSetting(String key, String value) => _repoSetSetting(key, value);

  /// 当前账本 id。
  ///
  /// ★ 存下来的 id **必须校验还活着**：1.4.1 的清空 bug 会在库里留下
  /// 「`current_ledger_id` 指着已删除的账本」这种状态，直接沿用的话，
  /// 明细、分类、预算全部按一个不存在的 ledger_id 去查 —— 界面上一片空白，
  /// 记一笔也看不见（新记录挂在另一个账本上）。这里发现对不上就改成真实存在的
  /// 那一本，让已经中招的库在下次启动时自愈，不用重装。
  static Future<int> currentLedgerId() => _repoCurrentLedgerId();

  // ------------------------------------------------------------------- 账本
  static Future<List<Ledger>> listLedgers({
    bool includeArchived = false,
  }) => _repoListLedgers(includeArchived: includeArchived);

  static Future<int> insertLedger(Ledger l) => _repoInsertLedger(l);

  static Future<void> updateLedger(Ledger l) => _repoUpdateLedger(l);

  /// 删除账本会级联删掉它的分类与交易（外键 ON DELETE CASCADE）
  static Future<void> deleteLedger(int id) => _repoDeleteLedger(id);

  // ------------------------------------------------------------------- 账户
  static Future<List<Account>> listAccounts({
    bool includeArchived = false,
  }) => _repoListAccounts(includeArchived: includeArchived);

  /// 净资产：只累计 `include_in_total = 1` 的账户
  static Future<int> totalBalanceCents() => _repoTotalBalanceCents();

  /// 建账户。
  ///
  /// ★ v8 起 `opening_cents` 必须与 `balance_cents` 一致 —— 新建账户还没有
  ///   任何流水，`余额 = 期初 + 流水合计` 要成立只能是「期初 = 余额」。
  ///   这里**强制**对齐，不信调用方传了什么：dev 种子、Excel 导入建空账户、
  ///   以后任何新入口都会走这条，漏一个就会出现「账面 1744、按流水 -3256」
  ///   这种自造的漂移（1.4.5 真机体检发现的第一个问题就是它）。
  static Future<int> insertAccount(Account a) => _repoInsertAccount(a);

  /// 改账户的「属性」：名称 / 类型 / 是否计入总资产 / 排序 / 停用。
  ///
  /// ★ **不写 `balance_cents` 与 `opening_cents`**。
  ///   这两列是一对恒等式的两端（`余额 = 期初 + 流水合计`），只有两条路能改它们：
  ///   `saveAccount`（用户手填余额 → 反算期初）和 `_applyBalanceDelta`（流水增减）。
  ///   如果这里跟着 `toMap()` 一起写，调用方随手构造一个 `Account(balanceCents: x)`
  ///   就会把期初抹成 0 —— 1.4.5 真机体检第一眼就抓到了这个（微信 1744 / 应 -3256）。
  static Future<void> updateAccount(Account a) => _repoUpdateAccount(a);

  /// 某账户名下的流水笔数（含转出与转入），删除前要给用户看个数。
  static Future<int> accountTxnCount(int id) => _repoAccountTxnCount(id);

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
  static Future<void> mergeAccount({
    required int from,
    required int to,
  }) => _repoMergeAccount(from: from, to: to);

  /// 删除一个**没有流水、余额为 0** 的账户。有数据时必须走 [mergeAccount]。
  static Future<void> deleteAccount(int id) => _repoDeleteAccount(id);

  /// 某账户的流水合计。加减规则与 [_applyBalanceDelta] **逐字对应**：
  /// 收入 +、支出 −、转账在转出端 −、在转入端 +。
  ///
  /// 金额允许为负（键盘行首打 `-` 就是负数），所以这里不做 `ABS`。
  static Future<int> accountFlowSum(int accountId) => _repoAccountFlowSum(accountId);

  /// 保存账户编辑：名称 / 类型 / 是否计入总资产 + 用户手填的「实际余额」。
  ///
  /// 手填余额改的是 **期初值**（`opening_cents`），不是余额本身 —— 直接写
  /// `balance_cents` 会打破恒等式 `余额 = 期初 + 流水合计`，下次体检就报一条
  /// 假的「余额不一致」。两列在同一个事务里写，不会出现只更新一半。
  ///
  /// [a] 是**新值**（调用方已 copyWith 过），[balanceCents] 是用户在输入框里
  /// 打出来的数字。
  static Future<void> saveAccount(Account a, int balanceCents) => _repoSaveAccount(a, balanceCents);

  // ------------------------------------------------------------------- 分类
  static Future<List<Category>> listCategories(
    int ledgerId, {
    TxnType? type,
    bool includeArchived = false,
  }) => _repoListCategories(ledgerId, type: type, includeArchived: includeArchived);

  static Future<int> insertCategory(Category c) => _repoInsertCategory(c);

  static Future<void> updateCategory(Category c) => _repoUpdateCategory(c);

  /// 分类被删时，历史交易的 `category_id` 置空（不连带删交易）。
  ///
  /// 删一级分类会**连同它的子分类一起删**：子分类失去父级之后既不会出现在
  /// 轮盘里，也没法在界面上找到，留着只会变成孤儿行。
  static Future<void> deleteCategory(int id) => _repoDeleteCategory(id);

  /// 当前账单日，1–31；非法值一律回落到 1。
  static Future<int> cycleStartDay() => _repoCycleStartDay();

  /// 某账本里属于「抬期池」的收入分类 id。
  ///
  /// 白名单只按**分类名**判定，用户改名/删掉分类后自动失效 —— 这正是设计里
  /// 「白名单只决定默认值」的意思：真正落库前每笔仍可手动改（阶段 5 的开关）。
  static Future<Set<int>> liftableCategoryIds(int ledgerId) => _repoLiftableCategoryIds(ledgerId);

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
  }) => _repoPeriodFor(t, startDay, liftableIds, liftToNext: liftToNext);

  /// 重算某账本全部记录的归属期（改账单日后必须调，否则历史全部错位）。
  ///
  /// 返回真正被改写的行数。实现是「一次查询 + 一次 batch」，不是逐条 await：
  /// 几千行仍在毫秒级，且只写有变化的行。为什么不写成一条 SQL —— 短月收拢
  /// （D14）和抬期白名单（D23）落到 SQL 里要两层 CASE + julianday，还会跟
  /// [periodStartOf] 各维护一份口径；口径漂移的代价远大于几毫秒。
  static Future<int> rebuildPeriods(int ledgerId) => _repoRebuildPeriods(ledgerId);

  /// 补齐 `period_start` 为空的记录（升级到 v4 后首次启动 / 从旧备份恢复后）。
  static Future<int> backfillMissingPeriods() => _repoBackfillMissingPeriods();

  // ------------------------------------------------------------------- 交易
  //
  // ★ 从这里往下到「借贷」小节的五条写路径（insertTxn / updateTxn / deleteTxn /
  //   createDebt / repayDebt）全部走 `WriteGateway.run`：事务边界只有那一处，
  //   业务层拿不到 `Database`，所以「忘记开事务」在结构上不成立。
  //   其余写方法都是**单条 SQL**，本身就原子，不进网关。
  static Future<int> insertTxn(Txn t, {bool? liftToNext}) => _repoInsertTxn(t, liftToNext: liftToNext);

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
  static Future<int> importBillRows({required List<Txn> txns}) => _repoImportBillRows(txns: txns);

  static Future<void> updateTxn(Txn old, Txn now, {bool? liftToNext}) => _repoUpdateTxn(old, now, liftToNext: liftToNext);

  static Future<void> deleteTxn(Txn t) => _repoDeleteTxn(t);

  /// 批量删除，返回实际删除条数。
  ///
  /// 不循环调 [deleteTxn]：那样每条开一次事务、每次都要 `afterTxnChange`，
  /// 删几十条会卡住界面；更要紧的是中途失败会留下「删了一半」——
  /// 用户看到「已删除 20 笔」，其实只有 8 笔没了。
  static Future<int> batchDeleteTxns(List<Txn> items) => _repoBatchDeleteTxns(items);

  // ------------------------------------------------------------------- 借贷

  /// 记一笔借贷：建 `debt` 记录 + 本金流水，同一事务，要么都成要么都不成。
  ///
  /// 本金流水的方向**由方向决定**（借出=支出、借入=收入），不接受调用方传，
  /// 否则「借出却记成收入」会让账户余额反向。两条都带 `debt_id`，统计一律排除。
  static Future<int> createDebt(
    Debt debt,
    Txn principal, {
    bool? liftToNext,
  }) => _repoCreateDebt(debt, principal, liftToNext: liftToNext);

  /// 某账本的全部借贷：未结清优先 → 有应还日的在前 → 应还日升序。
  ///
  /// `repaid_cents` 在这里按流水汇总，不落库：本金方向是「借出支出 / 借入收入」，
  /// 还款方向正好相反，所以借出数 income、借入数 expense。
  static Future<List<Debt>> listDebts({required int ledgerId}) => _repoListDebts(ledgerId: ledgerId);

  /// 记一笔还款：生成反向流水 + 必要时标记结清。
  ///
  /// 金额约束放在这里而不是界面上：任何入口（详情页、以后可能的批量核销）
  /// 都受同一条规则，不会出现某个入口漏校验、把剩余冲成负数。
  static Future<void> repayDebt({
    required Debt debt,
    required int amountCents,
    required int accountId,
    required String date,
  }) => _repoRepayDebt(debt: debt, amountCents: amountCents, accountId: accountId, date: date);

  /// 手动结清 / 撤销结清。结清只改状态，不动流水与余额 ——
  /// 「钱已经还完了但流水没记」这种账，用户自己承担，App 不去编造一笔。
  static Future<void> setDebtClosed(int debtId, {required bool closed}) => _repoSetDebtClosed(debtId, closed: closed);

  static Future<void> deleteDebt(int debtId) => _repoDeleteDebt(debtId);

  /// 删掉这笔往来时会被连带删掉的流水笔数（本金 + 每次还款）。
  ///
  /// 确认弹窗里的「还会删掉 N 笔流水」只能来自这里。写死一个数字、或者
  /// 按「本金 + 已还笔数」自己算，用户点下去删掉的东西就和提示对不上 ——
  /// 而这一步是不可撤销的，提示必须和 `_DeleteDebt` 的实际行为一致。
  static Future<int> debtTxnCount(int debtId) => _repoDebtTxnCount(debtId);

  /// 往来摘要：应收合计、应付合计、这段日期内到期且未结清的笔数。
  ///
  /// 金额取**剩余**而不是本金 —— 已经还掉的部分不该再算进「还欠多少」。
  static Future<({int receivable, int payable, int dueSoon})> debtSummary({
    required int ledgerId,
    required String from,
    required String to,
  }) => _repoDebtSummary(ledgerId: ledgerId, from: from, to: to);

  /// 某月明细（按月倒排日期、同日按 id 倒排）—— [rangeListTxns] 的薄委托。
  static Future<List<Txn>> listTxns({
    required int ledgerId,
    required String month,
    TxnType? type,
    int? categoryId,
    String? keyword,
    int limit = 500,
    int offset = 0,
  }) => _repoListTxns(ledgerId: ledgerId, month: month, type: type, categoryId: categoryId, keyword: keyword, limit: limit, offset: offset);

  /// 某一期的明细，条件打在 `period_start` 上；排序仍按真实 `date`。
  ///
  /// 翻页优先用游标 [afterDate] + [afterId]（取上一页最后一条），
  /// 而不是 [offset] —— 理由见 `_repoRangeListTxns` 的文档。
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
    String? afterDate,
    int? afterId,
  }) => _repoRangeListTxns(
    ledgerId: ledgerId,
    from: from,
    to: to,
    type: type,
    categoryId: categoryId,
    keyword: keyword,
    limit: limit,
    offset: offset,
    basis: basis,
    afterDate: afterDate,
    afterId: afterId,
  );

  /// 批量改分类：一条 UPDATE，要么全中要么全不动。
  ///
  /// 为什么不逐条调 [updateTxn]：那会逐条重算归属期、逐条回滚再应用余额，
  /// 20 条就是 20 次事务、40 次余额写。分类既不参与余额也不改日期，
  /// 逐条走只会把风险放大 20 倍。
  ///
  /// 但**归属期确实可能变**：把记录改到「工资」这类抬期分类上时，它该落到
  /// 下一期。所以改完重算一次归属期 —— 漏了这步会出现「日期对、期归错」
  /// 的记录，而这在明细里几乎看不出来，只会在预算/汇总里悄悄错位。
  static Future<int> batchSetCategory({
    required int ledgerId,
    required List<int> txnIds,
    required int? categoryId,
  }) => _repoBatchSetCategory(ledgerId: ledgerId, txnIds: txnIds, categoryId: categoryId);

  /// 按筛选条件取**全部**记录（导出用）。
  ///
  /// 与明细列表共用 [_txnWhere]：导出的行数必须和用户在屏幕上看到的一致。
  /// 条件写两遍迟早会漂（一处加了账户条件、另一处忘了），那次「导出 800 条、
  /// 列表 137 条」的解释成本远高于复用这一个小函数。
  static Future<List<Txn>> txnForExport({
    required int ledgerId,
    TxnFilter? filter,
  }) => _repoTxnForExport(ledgerId: ledgerId, filter: filter);

  static Future<(List<Txn>, bool)> searchTxns({
    required int ledgerId,
    String? keyword,
    TxnFilter? filter,
    int limit = searchLimit,
  }) => _repoSearchTxns(ledgerId: ledgerId, keyword: keyword, filter: filter, limit: limit);

  /// 筛选结果的合计：`(支出, 收入, 笔数)`。
  ///
  /// 与 [searchTxns] 共用同一份 WHERE，但**不受 [searchLimit] 截断影响**（D20）：
  /// 汇总交给 SQLite 做，笔数永远是真实的。口径与 [monthTotals] 一致
  /// （负数交叉归集，转账两侧都不参与）。
  static Future<(int expense, int income, int count)> sumFiltered({
    required int ledgerId,
    String? keyword,
    TxnFilter? filter,
  }) => _repoSumFiltered(ledgerId: ledgerId, keyword: keyword, filter: filter);

  /// 把 10 张表整个读出来（备份用）。行是原始 map，交给上层序列化。
  ///
  /// 老备份（v6 及以前）里没有 `debt` 这一项，恢复时按空表处理 ——
  /// 借贷是 v7 才有的，旧账本本来就没有往来。
  static Future<Map<String, List<Map<String, Object?>>>> dumpTables() => _repoDumpTables();

  /// 整库覆盖式回填，返回每张表写入的行数。
  ///
  /// **必须在事务里**：中途任何一张表失败都要整体回滚，
  /// 否则会留下「记账记录已经清了、分类还没回来」的半截库。
  ///
  /// [keepSettings] 是不跟着备份走、但也不该被清掉的设置项
  /// （应用名、实验开关这类「这台机器的状态」），在同一个事务里补回去。
  ///
  /// [report] 可选：把「旧字段被忽略 / 换名 / 类型纠正」记进这份账本，
  /// 界面据此告诉用户「这份备份是哪一年的、有些字段没带过来」。
  /// 不传也能正常恢复 —— 兼容动作照样生效，只是没人记录。
  /// [afterLoad] 见 `_repoReplaceTables` 的同名参数：在**同一事务内**、
  /// 提交之前执行，用于旧备份恢复后补做的迁移（分类升级）。
  static Future<Map<String, int>> replaceTables(
    Map<String, List<Map<String, Object?>>> data, {
    Map<String, String> keepSettings = const {},
    ConformReport? report,
    Future<void> Function(Transaction txn)? afterLoad,
  }) => _repoReplaceTables(
    data,
    keepSettings: keepSettings,
    report: report,
    afterLoad: afterLoad,
  );

  // 旧格式备份的行改写（`budget.month` → `period_start` 等）已统一收进
  // `backup_compat.dart` 的 `conformRow`：那里有完整的兼容表、类型对齐与
  // 「未知列丢弃并记账」的规则。这里不再保留第二份实现 ——
  // 同一个规则有两个落点，改一边忘一边就是下一次「换机丢数据」。

  /// 读出全部设置项（键值对），恢复时用来保留机器状态
  static Future<Map<String, String>> listSettings() => _repoListSettings();

  /// 有记账记录的年月集合，用于月份选择器做「有数据的月份」提示
  static Future<Set<String>> monthsWithData(int ledgerId) => _repoMonthsWithData(ledgerId);

  // ------------------------------------------------------------------- 预算

  /// 某一期的预算明细（`category_id IS NULL` 那条是总预算）
  static Future<List<Budget>> listBudgets(
    int ledgerId,
    String periodStart,
  ) => _repoListBudgets(ledgerId, periodStart);

  /// 总预算（category_id 为 NULL 的那条）
  static Future<int?> totalBudgetCents(int ledgerId, String periodStart) => _repoTotalBudgetCents(ledgerId, periodStart);

  static Future<void> setBudget({
    required int ledgerId,
    required String periodStart,
    int? categoryId,
    required int amountCents,
  }) => _repoSetBudget(ledgerId: ledgerId, periodStart: periodStart, categoryId: categoryId, amountCents: amountCents);

  /// 改账单日后，把预算挪到新的归属期上。
  ///
  /// 预算的 key 是 `period_start`，账单日一变，原来那些 key 就落在期中间了
  /// （10-15 起的一期，在账单日改回 1 号后已经不存在）。规则是：
  /// **按「旧期第一天」找到它现在落进哪一期**，挪过去。
  ///
  /// 两条旧预算可能挤进同一期（期变长时），此时**金额相加**而不是让后一条
  /// 覆盖前一条 —— 覆盖等于凭空吃掉一笔预算，用户只会觉得「我的预算少了」。
  static Future<int> remapBudgetPeriods(int startDay) => _repoRemapBudgetPeriods(startDay);

  // --------------------------------------------------------------- 储蓄目标
  static Future<List<SavingGoal>> listGoals({
    bool includeArchived = false,
  }) => _repoListGoals(includeArchived: includeArchived);

  static Future<int> insertGoal(SavingGoal g) => _repoInsertGoal(g);

  static Future<void> updateGoal(SavingGoal g) => _repoUpdateGoal(g);

  static Future<void> deleteGoal(int id) => _repoDeleteGoal(id);

  /// 某个目标的存/取流水（最近在前）。用于「目标详情」回看，以及算月均存入速率。
  static Future<List<GoalFlow>> listGoalFlows(int goalId) => _repoListGoalFlows(goalId);

  /// 所有目标的流水，一次查完（计划页给每张卡算预计时间用，避免 N+1）。
  static Future<List<GoalFlow>> listAllGoalFlows() => _repoListAllGoalFlows();

  /// 存钱 / 取钱（金额可为负）。
  ///
  /// [date] 默认今天；[accountId] 记的是「这笔钱从哪个账户挪进目标」，
  /// 可以为空（用户只想记一句「我存了 500」，不想牵扯账户余额）。
  static Future<void> addFunds(
    int goalId,
    int deltaCents, {
    String? date,
    int? accountId,
    String note = '',
  }) => _repoAddFunds(goalId, deltaCents, date: date, accountId: accountId, note: note);

  // --------------------------------------------------------------- 周期账单
  static Future<List<RecurringRule>> listRecurring(
    int ledgerId, {
    bool onlyEnabled = false,
  }) => _repoListRecurring(ledgerId, onlyEnabled: onlyEnabled);

  static Future<int> insertRecurring(RecurringRule r) => _repoInsertRecurring(r);

  static Future<void> updateRecurring(RecurringRule r) => _repoUpdateRecurring(r);

  static Future<void> deleteRecurring(int id) => _repoDeleteRecurring(id);

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
  static Future<int> runDueRecurring(int ledgerId, {DateTime? now}) => _repoRunDueRecurring(ledgerId, now: now);

  // ------------------------------------------------------------------- 模板

  /// 管理页用的顺序：用户拖出来的顺序优先
  static Future<List<TxnTemplate>> listTemplates(int ledgerId) => _repoListTemplates(ledgerId);

  /// 记一笔面板顶部那排「常用模板」：用得多的在前，同频次看最近用过谁
  static Future<List<TxnTemplate>> recentTemplates(
    int ledgerId, {
    int limit = 3,
  }) => _repoRecentTemplates(ledgerId, limit: limit);

  static Future<int> insertTemplate(TxnTemplate t) => _repoInsertTemplate(t);

  static Future<void> updateTemplate(TxnTemplate t) => _repoUpdateTemplate(t);

  static Future<void> deleteTemplate(int id) => _repoDeleteTemplate(id);

  /// 用了一次模板 —— 只动统计列，不动用户填的内容
  static Future<void> touchTemplate(int id) => _repoTouchTemplate(id);

  /// 拖动排序：把当前顺序整体写回 sort_order
  static Future<void> reorderTemplates(List<int> orderedIds) => _repoReorderTemplates(orderedIds);

  /// 按传入顺序重写分类的 `sort_order`（0..n-1）。
  ///
  /// 只动排序，不碰名称、图标、停用状态。停用的分类不参与排序 ——
  /// 管理页把它们单独排在下面，拖的是「使用中」那一段。
  static Future<void> reorderCategories(List<int> orderedIds) => _repoReorderCategories(orderedIds);

  /// 停用 / 恢复一个分类。
  ///
  /// 不级联：停用一级分类时，它的子分类保持原状。理由是一级分类消失后，
  /// 子分类本来就到不了（选择器先选一级再选二级），级联反而会让「恢复一级」
  /// 顺手把用户单独停用过的子分类也放出来。
  static Future<void> setCategoryArchived(int id, {required bool archived}) => _repoSetCategoryArchived(id, archived: archived);

}
