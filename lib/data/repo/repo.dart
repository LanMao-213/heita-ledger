import 'package:sqflite/sqflite.dart';

import '../../core/local_date.dart';
import '../../core/period.dart';
import '../db/db.dart';
import '../models/models.dart';
import 'account_repo.dart';
import 'budget_repo.dart';
import 'category_repo.dart';
import 'debt_repo.dart';
import 'goal_repo.dart';
import 'ledger_repo.dart';
import 'recurring_repo.dart';
import 'setting_repo.dart';
import 'stats_repo.dart';
import 'template_repo.dart';
import 'txn_repo.dart';

/// 数据层**门面**。
///
/// 三条规定（架构设计 §2.2）：
/// 1. **本文件一行查询语句都不写** —— 聚合与查询都在各领域 repo 里；
/// 2. 只放「跨领域、必须同一事务」的复合写：记一笔、改一笔、删一笔、
///    记借贷、还款、删往来、清空重建、导入写入；
/// 3. 门面 ≤ 130 行。超过说明有业务逻辑漏到门面里了，该回到对应 repo。
abstract final class Repo {
  /// 11 个领域 repo 的实例（全都无状态，可以当常量复用）。
  static const LedgerRepo ledger = LedgerRepo();
  static const AccountRepo account = AccountRepo();
  static const CategoryRepo category = CategoryRepo();
  static const TxnRepo txn = TxnRepo();
  static const StatsRepo stats = StatsRepo();
  static const BudgetRepo budget = BudgetRepo();
  static const DebtRepo debt = DebtRepo();
  static const RecurringRepo recurring = RecurringRepo();
  static const TemplateRepo template = TemplateRepo();
  static const GoalRepo goal = GoalRepo();
  static const SettingRepo setting = SettingRepo();

  /// 记一笔（普通模式）：算归属期 → 插流水 → 维护余额 →（可选）模板计数，单事务。
  ///
  /// 返回落库后的 [Txn]（`id` 与 `periodStart` 都填好了）—— 调用方拿它去搬游标、
  /// 拼 toast，**不要自己再算一遍归属期**（原版两处各算一次，文案与跳转对不上）。
  static Future<Txn> saveTxn(
    Txn draft, {
    required int cycleStartDay,
    bool touchTemplate = true,
  }) async {
    final LocalDate periodStart = Period.periodStartOf(
      draft.date,
      cycleStartDay,
    );
    final Txn withPeriod = draft.copyWith(periodStart: periodStart);
    final int id = await txn.insert(
      withPeriod,
      touchTemplate: touchTemplate && withPeriod.templateId != null,
    );
    return withPeriod.copyWith(id: id);
  }

  /// 改一笔：日期变了就重算归属期，再交给 `TxnRepo.update` 维护余额。
  static Future<Txn> updateTxn(
    Txn before,
    Txn after, {
    required int cycleStartDay,
  }) async {
    final Txn next = after.copyWith(
      periodStart:
          after.periodStart ??
          Period.periodStartOf(after.date, cycleStartDay),
    );
    await txn.update(before, next);
    return next;
  }

  /// 删一笔（事务内先回滚余额，再删行）。
  static Future<void> deleteTxn(Txn t) => txn.delete(t);

  /// 记一笔借贷（`debt` + 本金流水 + 余额，单事务）。
  static Future<int> createDebt(Debt draft, {required int cycleStartDay}) =>
      debt.createDebt(draft: draft, cycleStartDay: cycleStartDay);

  /// 还款 / 收回（超额抛 `ArgumentError`，还满自动结清）。
  static Future<Debt> repayDebt({
    required Debt target,
    required int amountCents,
    required int cycleStartDay,
    LocalDate? date,
  }) => debt.repay(
    debt: target,
    amountCents: amountCents,
    cycleStartDay: cycleStartDay,
    date: date,
  );

  /// 删往来（回滚余额 + 删流水 + 删 debt，单事务）。
  static Future<void> deleteDebt(int id) => debt.deleteDebt(id);

  /// 清空全部业务数据并重建默认账本（单事务，含回滚）。
  static Future<void> wipeAndRebuild() => Db.wipeAllData();

  /// 全量替换（导入 / 恢复），父表先插。
  ///
  /// 插完**同一事务内**按流水重算余额（`balance = opening + Σ流水`）：
  /// 备份里的 balance 是导出那一刻的快照，重算才能保证「导入后恒等式仍成立」
  /// （不变量 I1 的导入场景）。
  static Future<void> importPayload(
    Map<String, List<Map<String, Object?>>> payload,
  ) {
    return Db.replaceAll(
      payload,
      afterInsert: (DatabaseExecutor db) =>
          account.recalcBalances(ex: db),
    );
  }

  /// 账户余额增量（跨领域写流水时用；单独暴露给 `integrity_service` 之类的工具）。
  static Future<void> applyBalanceDelta(Txn t, {bool reverse = false}) async {
    await Db.transaction(
      (txn) => account.applyBalanceDelta(txn, t, reverse: reverse),
    );
  }
}
