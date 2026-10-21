import 'package:flutter/material.dart';

import '../../core/scope.dart';
import '../../stores/plan_store.dart';
import '../../stores/shell_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../pages/detail/detail_page.dart';
import '../pages/mine/mine_page.dart';
import '../pages/plan/plan_page.dart';
import '../pages/record/record_sheet.dart';
import '../pages/stats/stats_page.dart';
import '../widgets/toast.dart';

/// 应用外壳（架构设计 §2.2 / M01-F01、M01-F02）。
///
/// 结构是**最终结构**（阶段 0 就把壳定死，后面只往里填页面内容）：
/// - `PageView` 横滑 4 页，每页自己 `AutomaticKeepAliveClientMixin` 保活；
/// - 底部 5 槽：明细 / 图表 / ＋ / 计划 / 我的，中央是「记一笔」浮钮；
/// - 底栏与 `PageView` 的 `tabIndex` 双向同步（点底栏翻页、滑页面点亮底栏）。
///
/// 只订阅 [ShellStore]：其余数据变化不会让底栏重建。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageController _controller = PageController();

  /// 回前台补记（M01-F05）。`AppLifecycleListener` 比自己记
  /// `didChangeAppLifecycleState` 好：它只在真正 resume 时回调，切后台过程中的
  /// inactive/paused 不会各触发一次。
  AppLifecycleListener? _lifecycle;

  /// 启动提示只弹一次：热重载会重建 `HomeShell`，不加这个标志会重复提示。
  bool _startupNotified = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    WidgetsBinding.instance.addPostFrameCallback(
      (Duration _) => _notifyStartup(),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 启动一次性提示：**只弹一条**（把「分类升级」与「已补记 N 笔」拼起来）。
  void _notifyStartup() {
    if (!mounted || _startupNotified) return;
    _startupNotified = true;
    final String? summary = ShellScope.of(context).bootSummary;
    if (summary == null || summary.isEmpty) return;
    showToast(context, summary);
  }

  /// 回前台：补记到期账单。
  ///
  /// 三件事的次序不能反：
  /// 1. `catchUp` —— 日期与账本都没变时它**0 次查询**直接返回（闸一）；
  /// 2. 补记 > 0 才重查 —— 空转时不用刷新整棵树；
  /// 3. **不动 `BookStore` 的期游标** —— 用户可能正翻旧账，被拽回本期很恼人。
  Future<void> _onResume() async {
    if (!mounted) return;
    final PlanStore plan = PlanScope.of(context);
    final int added = await plan.catchUpOnResume();
    if (!mounted || added <= 0) return;
    // afterTxnChange 只重查当前期，**不搬游标** —— 正是这里要的
    await BookScope.of(context).afterTxnChange();
    if (!mounted) return;
    await CatalogScope.of(context).reloadMoney();
    if (!mounted) return;
    plan.markStatsStale();
    showToast(context, '已补记 $added 笔周期账单');
  }

  /// 把 `PageView` 拉回 Store 说的那一页。
  ///
  /// 为什么需要它：**切 tab 不止底栏一个入口** —— 图表页点一行要跳明细、
  /// 记事之后要回明细，这些都是页面直接改 `ShellStore.tabIndex`。
  /// 只靠底栏点按去动画，Store 被别处改了之后底栏高亮和页面就会分家。
  ///
  /// 帧后执行：`build` 阶段驱动 `PageController` 会撞「build 期间 setState」。
  void _syncPageToStore(int tab) {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || !_controller.hasClients) return;
      final double? page = _controller.page;
      if (page == null) return;
      if (page.round() == tab) return;
      _controller.animateToPage(tab, duration: Dur.page, curve: Ease.enter);
    });
  }

  /// 中央「记一笔」：开面板 → 回执 → 搬游标 → toast。
  ///
  /// 「搬游标」**只在 Store 里做一次**（`afterTxnInserted` 会清筛选 + 对齐期 +
  /// 重查）。UI 这里只负责「回到明细页 + 说一句话」，绝不自己改 cycle ——
  /// 原版 1.4.1 的「记完看不见」就是两处各搬一遍、搬歪了。
  Future<void> _onRecord() async {
    final RecordOutcome? outcome = await showRecordSheet(context);
    if (outcome == null || !mounted) return;
    await BookScope.of(context).afterTxnInserted(outcome.periodStart);
    if (!mounted) return;
    // 记完一笔，统计一定变了：打脏标记（只打标记 + 1 次通知，不在这查统计）
    PlanScope.of(context).markStatsStale();
    _goTo(ShellStore.tabDetail);
    showToast(context, '已记账 · ${outcome.label}');
  }

  /// 点底栏：先改 Store（底栏高亮立刻响应），再翻页。
  ///
  /// 点当前 tab 时**直接返回**：不重放翻页动画，也不发通知
  /// （`ShellStore.switchTab` 对同值也是空操作，两处都挡一次）。
  void _onBarSelect(int tab) => _goTo(tab);

  /// 切 tab（底栏点、或记完一笔之后回来都用它，保证底栏与页面同步）。
  ///
  /// 只改 Store，**翻页交给 [_syncPageToStore]**：两个入口（底栏点、页面内跳转）
  /// 走同一条路，才不会出现「底栏亮了但页面没翻」。
  void _goTo(int tab) {
    final ShellStore shell = ShellScope.of(context);
    if (shell.tabIndex == tab) {
      return;
    }
    shell.switchTab(tab);
  }

  @override
  Widget build(BuildContext context) {
    final ShellStore shell = ShellScope.watch(context);
    final AppPalette pal = context.pal;

    // Store 被别处改了（图表页下钻、记完一笔）时，页面跟着走
    _syncPageToStore(shell.tabIndex);

    return Scaffold(
      backgroundColor: pal.bg,
      body: PageView(
        controller: _controller,
        // 滑动手势由页面自己接管（明细页将来要横滑翻期，筛选态下更要让出外层的
        // PageView），这里保持默认的整页滚动。
        onPageChanged: (int page) => ShellScope.of(context).switchTab(page),
        children: const <Widget>[
          DetailPage(),
          StatsPage(),
          PlanPage(),
          MinePage(),
        ],
      ),
      bottomNavigationBar: _HomeBar(
        current: shell.tabIndex,
        onSelect: _onBarSelect,
      ),
      floatingActionButton: _RecordFab(onTap: _onRecord),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

/// 底部 5 槽栏。中央槽位留给浮钮，不承载页面。
class _HomeBar extends StatelessWidget {
  const _HomeBar({required this.current, required this.onSelect});

  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border(top: BorderSide(color: pal.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              _BarSlot(
                tab: ShellStore.tabDetail,
                icon: Icons.receipt_long_outlined,
                label: '明细',
                selected: current == ShellStore.tabDetail,
                onSelect: onSelect,
              ),
              _BarSlot(
                tab: ShellStore.tabStats,
                icon: Icons.pie_chart_outline,
                label: '图表',
                selected: current == ShellStore.tabStats,
                onSelect: onSelect,
              ),
              // 中央浮钮的位置。宽度与浮钮直径同量级，让两侧 tab 不被挤在一起。
              const SizedBox(width: 72),
              _BarSlot(
                tab: ShellStore.tabPlan,
                icon: Icons.event_note_outlined,
                label: '计划',
                selected: current == ShellStore.tabPlan,
                onSelect: onSelect,
              ),
              _BarSlot(
                tab: ShellStore.tabMine,
                icon: Icons.person_outline,
                label: '我的',
                selected: current == ShellStore.tabMine,
                onSelect: onSelect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarSlot extends StatelessWidget {
  const _BarSlot({
    required this.tab,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final int tab;
  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final Color color = selected ? pal.navActive : pal.ink3;
    return Expanded(
      child: InkWell(
        key: ValueKey<String>('nav-$label'),
        // 点击区撑满整个槽位（最小 44×44）
        onTap: () => onSelect(tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: Ts.badge.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中央「记一笔」浮钮（M01-F02）。
///
/// 视觉规范（架构设计 §6.4）：`accent` 底 + 3px `bg` 描边 + `Elev.fab` 阴影。
/// 阶段 0 只占位不记账 —— 点一下给一句 toast，面板本身在 T02-1 落地。
class _RecordFab extends StatelessWidget {
  const _RecordFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Semantics(
      button: true,
      label: '记一笔',
      child: GestureDetector(
        key: const ValueKey<String>('fab-record'),
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: Elev.fab(pal),
          ),
          child: Material(
            color: pal.accent,
            shape: CircleBorder(side: BorderSide(color: pal.bg, width: 3)),
            child: Icon(Icons.add, size: 26, color: pal.onInverse),
          ),
        ),
      ),
    );
  }
}
