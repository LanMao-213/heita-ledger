import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/scope.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/stores/book_store.dart';
import 'package:heita_ledger/stores/catalog_store.dart';
import 'package:heita_ledger/stores/plan_store.dart';
import 'package:heita_ledger/stores/shell_store.dart';
import 'package:heita_ledger/theme/app_theme.dart';
import 'package:heita_ledger/theme/palette.dart';

/// UI 测试的公共装配：四层作用域 + 中文 MaterialApp。
///
/// 不用 `HeitaApp`（它带 BootGate 与 PageView 外壳），这样单页可以独立测。
class UiHarness {
  UiHarness({
    ShellStore? shell,
    BookStore? book,
    CatalogStore? catalog,
    PlanStore? plan,
  }) : shell = shell ?? ShellStore(),
       book = book ?? BookStore(),
       catalog = catalog ?? CatalogStore(),
       plan = plan ?? PlanStore();

  final ShellStore shell;
  final BookStore book;
  final CatalogStore catalog;
  final PlanStore plan;

  /// 把三个业务 Store 绑到当前库并加载一次（测试用真库，不 mock）。
  Future<void> load({int? ledgerId}) async {
    final int id = ledgerId ?? await Repo.ledger.currentId();
    final int startDay = await Repo.setting.cycleStartDay();
    await book.bind(ledgerId: id, cycleStartDay: startDay);
    final period = book.cycle;
    await plan.bind(ledgerId: id, period: period);
    await catalog.loadCatalog(id);
    await book.reloadCycle();
    await plan.reload();
  }

  /// 四层作用域必须在 `MaterialApp` **外面**：
  /// 底部面板走 Navigator 的 Overlay，路由的 context 挂在 MaterialApp 之下，
  /// 作用域放里面的话面板里 `CatalogScope.watch` 会拿不到。
  Widget wrap(Widget child) {
    return ShellScope(
      store: shell,
      child: BookScope(
        store: book,
        child: CatalogScope(
          store: catalog,
          child: PlanScope(
            store: plan,
            child: MaterialApp(
              theme: buildTheme(paletteInk(), Brightness.light),
              home: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(wrap(child));
    await tester.pumpAndSettle();
  }
}

/// 一个最小的宿主页：把被测组件放进 Scaffold。
Widget host(Widget child) => Scaffold(body: SafeArea(child: child));
