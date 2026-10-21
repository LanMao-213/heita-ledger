import 'package:flutter/widgets.dart';

import '../stores/book_store.dart';
import '../stores/catalog_store.dart';
import '../stores/plan_store.dart';
import '../stores/shell_store.dart';

/// 四个 Store 的作用域（`InheritedNotifier`）。
///
/// 用法两档：
/// ```dart
/// final shell = ShellScope.watch(context);   // build 里订阅（会重建）
/// ShellScope.of(context).switchTab(0);       // 事件回调里只读（不订阅）
/// ```
///
/// **为什么不用 provider / riverpod**：只需要「往下传 + 订阅」两件事，
/// `InheritedNotifier` 就够；多一个包就多一处依赖解析风险，而依赖获取是这个
/// 项目最大的外部风险（架构设计 §1.2）。
class ShellScope extends InheritedNotifier<ShellStore> {
  const ShellScope({
    super.key,
    required ShellStore store,
    required super.child,
  }) : super(notifier: store);

  static ShellStore watch(BuildContext context) {
    final ShellScope? scope = context
        .dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'ShellScope 缺失：MaterialApp 的 home 必须套四层作用域');
    return scope!.notifier!;
  }

  static ShellStore of(BuildContext context) {
    final ShellScope? scope = context
        .getInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'ShellScope 缺失：MaterialApp 的 home 必须套四层作用域');
    return scope!.notifier!;
  }
}

/// 明细 / 期游标 / 分页 / 筛选。
class BookScope extends InheritedNotifier<BookStore> {
  const BookScope({
    super.key,
    required BookStore store,
    required super.child,
  }) : super(notifier: store);

  static BookStore watch(BuildContext context) {
    final BookScope? scope = context
        .dependOnInheritedWidgetOfExactType<BookScope>();
    assert(scope != null, 'BookScope 缺失');
    return scope!.notifier!;
  }

  static BookStore of(BuildContext context) {
    final BookScope? scope = context.getInheritedWidgetOfExactType<BookScope>();
    assert(scope != null, 'BookScope 缺失');
    return scope!.notifier!;
  }
}

/// 账户 / 分类树 / 模板 / 目标 / 净资产。
class CatalogScope extends InheritedNotifier<CatalogStore> {
  const CatalogScope({
    super.key,
    required CatalogStore store,
    required super.child,
  }) : super(notifier: store);

  static CatalogStore watch(BuildContext context) {
    final CatalogScope? scope = context
        .dependOnInheritedWidgetOfExactType<CatalogScope>();
    assert(scope != null, 'CatalogScope 缺失');
    return scope!.notifier!;
  }

  static CatalogStore of(BuildContext context) {
    final CatalogScope? scope = context
        .getInheritedWidgetOfExactType<CatalogScope>();
    assert(scope != null, 'CatalogScope 缺失');
    return scope!.notifier!;
  }
}

/// 预算 / 往来 / 周期账单 / 统计快照。
class PlanScope extends InheritedNotifier<PlanStore> {
  const PlanScope({
    super.key,
    required PlanStore store,
    required super.child,
  }) : super(notifier: store);

  static PlanStore watch(BuildContext context) {
    final PlanScope? scope = context
        .dependOnInheritedWidgetOfExactType<PlanScope>();
    assert(scope != null, 'PlanScope 缺失');
    return scope!.notifier!;
  }

  static PlanStore of(BuildContext context) {
    final PlanScope? scope = context.getInheritedWidgetOfExactType<PlanScope>();
    assert(scope != null, 'PlanScope 缺失');
    return scope!.notifier!;
  }
}
