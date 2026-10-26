part of '../models.dart';

// ---------------------------------------------------------------------------
// 统计口径的结果模型
// ---------------------------------------------------------------------------

/// 分类统计，用于饼图与排行
class CatStat {
  const CatStat({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.totalCents,
    required this.count,
  });

  final int categoryId;
  final String name;
  final String icon;
  final int totalCents;
  final int count;
}

/// 分类 + 预算，用于计划页的进度条
class BudgetStat {
  const BudgetStat({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.spentCents,
    required this.budgetCents,
  });

  final int categoryId;
  final String name;
  final String icon;
  final int spentCents;
  final int budgetCents;

  bool get over => budgetCents > 0 && spentCents > budgetCents;

  double get ratio => budgetCents <= 0 ? 0 : (spentCents / budgetCents);

  int get overCents => over ? spentCents - budgetCents : 0;
}

// --------------------------------------------------------------- 借贷往来
