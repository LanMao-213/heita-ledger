import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/scope.dart';
import 'stores/book_store.dart';
import 'stores/catalog_store.dart';
import 'stores/plan_store.dart';
import 'stores/shell_store.dart';
import 'theme/app_theme.dart';
import 'ui/boot/boot_gate.dart';

/// `MaterialApp` 骨架 + 四层 Store 作用域。
///
/// 三件事这里定死：
/// 1. **主题跟着 `ShellStore.palette` 变** —— `ListenableBuilder` 包住
///    `MaterialApp`，配色切换时 `theme` 换成另一份 `ThemeData`，
///    Material 内部的 `AnimatedTheme` 按 `AppPalette.lerp` 做 200ms 插值。
/// 2. **中文** —— 日期选择器、`Scaffold` 内置文案都要 `zh_CN` 委托。
/// 3. **字号夹紧** —— 0.8×–2.0× 放行，超出夹住（再大任何布局都会溢出）。
///
/// [book] / [catalog] / [plan] 可省略：省略时自己建（无参、无状态），
/// 这样只想测「壳」的用例（`shell_test`）不必装配四个 Store。
class HeitaApp extends StatefulWidget {
  const HeitaApp({
    super.key,
    required this.shell,
    this.book,
    this.catalog,
    this.plan,
    this.bootRunner,
  });

  final ShellStore shell;
  final BookStore? book;
  final CatalogStore? catalog;
  final PlanStore? plan;

  /// 覆盖启动序列（测试注入假实现时用）。为 `null` 走真实 12 步。
  final BootRunner? bootRunner;

  @override
  State<HeitaApp> createState() => _HeitaAppState();
}

class _HeitaAppState extends State<HeitaApp> {
  late final BookStore _book = widget.book ?? BookStore();
  late final CatalogStore _catalog = widget.catalog ?? CatalogStore();
  late final PlanStore _plan = widget.plan ?? PlanStore();

  /// 真实启动序列：把四个 Store 交给 `BootSequence`（12 步）。
  ///
  /// `BootSequence.run` 会返回 `BootOutcome`（补记笔数 / 分类升级），首帧后的
  /// 「；」拼接 toast 在阶段 2 与 `HomeShell` 一起接 —— 这里把返回值丢掉是
  /// 有意的（现在没有 toast 可弹），不是漏了。
  Future<void> _runBoot(ShellStore shell) async {
    await BootSequence.run(
      shell,
      book: _book,
      catalog: _catalog,
      plan: _plan,
    );
  }

  @override
  Widget build(BuildContext context) {
    final BootRunner runner = widget.bootRunner ?? _runBoot;
    return ListenableBuilder(
      listenable: widget.shell,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp(
          title: '黑塔账本',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(widget.shell.palette, Brightness.light),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const <Locale>[Locale('zh', 'CN')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData data = MediaQuery.of(context);
            return MediaQuery(
              data: data.copyWith(
                textScaler: data.textScaler.clamp(
                  minScaleFactor: 0.8,
                  maxScaleFactor: 2.0,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: ShellScope(
            store: widget.shell,
            child: BookScope(
              store: _book,
              child: CatalogScope(
                store: _catalog,
                child: PlanScope(
                  store: _plan,
                  child: BootGate(shell: widget.shell, runner: runner),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
