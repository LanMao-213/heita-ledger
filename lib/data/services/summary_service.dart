import '../models/models.dart';

/// 派生口径的**唯一来源**：可用额度 / 剩余 / 超支 / 净资产 / 应收应付 / 占比。
///
/// ★ 为什么要有这个文件：这几条口径在界面上会出现十几次（概览卡、预算条、
///   计划页、我的页净资产、往来卡…）。各处各写一遍的下场是「同一个数字，
///   两页不一样」—— 原版就出现过「预算条说还剩 200，计划页说超了 50」。
///
/// ★ 谁都不许绕过它自己加减（口径 3.1 / 3.2 / 3.4）。
abstract final class SummaryService {
  /// 可用额度 = 总预算额度 + 本期计入预算的借入。
  ///
  /// 借入**只抬可用额度**，不改额度本身：`total` 永远是用户设的那个数，
  /// `available` 才是「这一期实际能动用的钱」。
  static int budgetAvailable({int? totalCents, int borrowedInBudgetCents = 0}) =>
      (totalCents ?? 0) + borrowedInBudgetCents;

  /// 剩余；没设预算 → 0（不是负数）。
  static int budgetLeft(BudgetStats stats) => stats.leftCents;

  /// 预算派生值打包（`budget_stats` 表的读取方都走这里）。
  static BudgetStats budgetStats({
    required int? totalCents,
    required int usedCents,
    int borrowedInBudgetCents = 0,
  }) {
    return BudgetStats(
      totalBudgetCents: totalCents,
      usedCents: usedCents,
      borrowedInBudgetCents: borrowedInBudgetCents,
    );
  }

  /// 账户资产合计（只算 `include_in_total` 的账户）。
  static int accountAssets(Iterable<Account> accounts) {
    int sum = 0;
    for (final Account a in accounts) {
      if (!a.includeInTotal) continue;
      sum += a.balanceCents;
    }
    return sum;
  }

  /// 应收合计（借出未还部分）。
  static int receivable(Iterable<Debt> debts, RepaidIndex index) {
    int sum = 0;
    for (final Debt d in debts) {
      if (!d.isReceivable) continue;
      sum += d.remainingCents(index);
    }
    return sum;
  }

  /// 应付合计（借入未还部分）。
  static int payable(Iterable<Debt> debts, RepaidIndex index) {
    int sum = 0;
    for (final Debt d in debts) {
      if (d.isReceivable) continue;
      sum += d.remainingCents(index);
    }
    return sum;
  }

  /// 净资产 = Σ账户余额（计入净资产的）+ 应收 − 应付。
  ///
  /// 为什么要把应收加回来：借出去的钱从账户里扣走了，但它不是消费，
  /// 只是换了个形式待着（别人欠我）。
  ///
  /// [receivableOverride] / [payableOverride] 给「已经用 SQL 聚合好应收应付」的
  /// 调用方用（`CatalogStore` 一次查全，不必再把每笔债读进内存）。
  static int netWorth({
    required Iterable<Account> accounts,
    Iterable<Debt> debts = const <Debt>[],
    RepaidIndex index = RepaidIndex.empty,
    int? receivableOverride,
    int? payableOverride,
  }) {
    return accountAssets(accounts) +
        (receivableOverride ?? receivable(debts, index)) -
        (payableOverride ?? payable(debts, index));
  }

  /// 预算占比（0–1 之外不截断；界面自己 clamp）。
  static double usedRatio(BudgetStats stats) => stats.usedRatio;

  /// 借贷对预算的影响：本期借入且 `count_in_budget` 的合计。
  ///
  /// 借出**恒不计入**（数据层把 `count_in_budget` 强改 0），所以这里只看借入。
  static int borrowedInBudget({
    required Iterable<Debt> debts,
    required bool Function(Debt debt) inCurrentPeriod,
  }) {
    int sum = 0;
    for (final Debt d in debts) {
      if (d.isReceivable || !d.countInBudget) continue;
      if (!inCurrentPeriod(d)) continue;
      sum += d.amountCents;
    }
    return sum;
  }
}
