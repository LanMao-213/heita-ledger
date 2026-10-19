import 'package:flutter/material.dart';

import '../design/haptics.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/record_sheet.dart';
import 'detail_page.dart';
import 'mine_page.dart';
import 'plan_page.dart';
import 'stats_page.dart';

/// 主界面：底部四页 + 中间「记一笔」。
///
/// 导航布局与原型一致：明细 · 图表 · ＋ · 计划 · 我的。
/// 「分类管理」按用户要求移到了「我的 → 设置」里。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// 启动提示只出一次（页面重建、热重载都不该再弹）
  bool _startupNotified = false;

  /// 页码的唯一真源是 `store.tabIndex`，这个 controller 只是它的投影：
  /// 点 tab、手指横滑、以及统计页的「看明细」调 `switchTab`，都从 [_syncPage] 汇进来
  late final PageController _page = PageController(
    initialPage: Store.i.tabIndex,
  );

  static const _tabs = [
    (icon: 'list', label: '明细'),
    (icon: 'pie', label: '图表'),
    (icon: 'target', label: '计划'),
    (icon: 'person', label: '我的'),
  ];

  @override
  void initState() {
    super.initState();
    Store.i.addListener(_syncPage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyStartup());
  }

  @override
  void dispose() {
    Store.i.removeListener(_syncPage);
    _page.dispose();
    super.dispose();
  }

  /// store 里的 tab 变了 → 页面滑过去（自己滑过去的情况在这里会直接 return）
  void _syncPage() {
    final want = Store.i.tabIndex;
    if (!mounted || !_page.hasClients) return;
    if ((_page.page?.round() ?? 0) == want) return;
    _page.animateToPage(
      want,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// 点底部 tab
  void _select(int i) {
    if (i == Store.i.tabIndex) return;
    Haptics.tap();
    // 只改 store，滑动交给 _syncPage —— 两处都动会互相打架
    Store.i.switchTab(i);
  }

  /// 手指横滑到位
  void _onSwipe(int i) {
    if (i == Store.i.tabIndex) return;
    Haptics.tap();
    Store.i.switchTab(i);
  }

  /// 周期账单补记只提示一次，不打扰
  /// 启动后的一次性提示：分类升级 / 补记的周期账单。
  ///
  /// 两条合并成一句：`showToast` 会先清掉上一条，连弹两次等于只有后一条
  /// 被看见 —— 而「分类改名了」恰恰是最不能说丢的那一条。
  void _notifyStartup() {
    if (_startupNotified) return;
    _startupNotified = true;
    final parts = <String>[
      if (Store.i.catsUpgradeJustDone) '分类已升级为「分类 + 子分类」两级，可在「我的 → 分类管理」里调整',
      if (Store.i.recurringJustAdded > 0)
        '已补记 ${Store.i.recurringJustAdded} 笔周期账单',
    ];
    if (parts.isEmpty || !mounted) return;
    showToast(context, parts.join('；'));
  }

  Future<void> _openRecord() async {
    final saved = await showRecordSheet(context);
    if (saved == true && mounted) {
      Haptics.success();
      showToast(context, '已记账');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Store.i;
    // 只有 tabbar 挂在这个 AnimatedBuilder 上：页面各自监听 store，
    // 套在最外层会让整棵 PageView 跟着每次记账重建一遍
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        bottom: false,
        // 四页用 PageView 铺开，左右滑就能换页。
        // 每页都套 _Keep：不加的话滑走的那页会被销毁，切回来列表回到顶部
        child: PageView(
          controller: _page,
          onPageChanged: _onSwipe,
          children: const [
            _Keep(child: DetailPage()),
            _Keep(child: StatsPage()),
            _Keep(child: PlanPage()),
            _Keep(child: MinePage()),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: store,
        builder: (context, _) => _TabBar(
          index: store.tabIndex,
          tabs: _tabs,
          onSelect: _select,
          onRecord: _openRecord,
        ),
      ),
    );
  }
}

/// 让 PageView 里的页面常驻。
///
/// PageView 默认会把滑出屏幕的页销毁（连同它的滚动位置），切回来时列表
/// 从顶部重新开始 —— 记账应用里这很致命：看了半天明细，去图表转一圈回来
/// 就得重新找位置。
class _Keep extends StatefulWidget {
  const _Keep({required this.child});

  final Widget child;

  @override
  State<_Keep> createState() => _KeepState();
}

class _KeepState extends State<_Keep> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.index,
    required this.tabs,
    required this.onSelect,
    required this.onRecord,
  });

  final int index;
  final List<({String icon, String label})> tabs;
  final ValueChanged<int> onSelect;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: C.bg,
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(children: [_tab(0), _tab(1), _fab(), _tab(2), _tab(3)]),
        ),
      ),
    );
  }

  Widget _tab(int i) {
    final on = index == i;
    final t = tabs[i];
    return Expanded(
      child: InkWell(
        key: ValueKey('tab-$i'),
        onTap: () => onSelect(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LineIcon(t.icon, size: 22, color: on ? C.ink : C.ink3),
            const SizedBox(height: 4),
            Text(
              t.label,
              style: TextStyle(
                fontSize: 10.5,
                color: on ? C.ink : C.ink3,
                fontWeight: on ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fab() {
    return Expanded(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -12),
          child: GestureDetector(
            onTap: onRecord,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: C.ink,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: C.ink.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                  // 3px 白色描边：让按钮从 tabbar 上「切」出来，不然只是浮着
                  const BoxShadow(color: C.bg, spreadRadius: 3),
                ],
              ),
              child: const Center(
                child: LineIcon(
                  'plus',
                  size: 24,
                  color: C.bg,
                  strokeWidth: 1.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
