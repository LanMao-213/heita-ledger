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

  /// 前后台切换的监听。
  ///
  /// 用 `AppLifecycleListener` 而不是 `WidgetsBindingObserver` 混入：少一个
  /// mixin、少一个必须记得调 `super.didChangeAppLifecycleState` 的地方。
  late final AppLifecycleListener _lifecycle;

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
    // 从后台回来时补上「这段时间里该发生的事」：周期拨到今天、补记到期账单。
    // 没有它，应用常驻后台过夜后周期条会停在昨天，房租要等下次冷启动才记。
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyStartup());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    Store.i.removeListener(_syncPage);
    _page.dispose();
    super.dispose();
  }

  /// 回到前台：交给 Store 判断要不要重算，这里只管说话
  Future<void> _onResume() async {
    final added = await Store.i.onAppResumed();
    if (!mounted || added <= 0) return;
    showToast(context, '已补记 $added 笔周期账单');
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
    final outcome = await showRecordSheet(context);
    if (outcome == null || !mounted) return;
    Haptics.success();
    // 带上归属期：抬期、账单日不是 1 号这些规则会让这笔落到别的期，
    // 而界面上只看得到「记完了」—— 一句话说清它记到哪去了
    showToast(context, '已记账 · ${outcome.periodLabel}');
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
      decoration: BoxDecoration(
        // 底栏跟着卡面走：底栏用页面底就与内容糊在一起，用卡面才浮得起来
        color: C.cardBg,
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
            // 选中/未选中是「同一颗图标的两种状态」，不是两颗图标：
            // 颜色瞬切 + 尺寸跟着变一下，才看得出是它自己被点亮了
            AnimatedScale(
              scale: on ? 1.0 : 0.92,
              duration: M.fast,
              curve: M.standard,
              // 选中态除了变色再加一档线宽：颜色 + 重量同时变，才像「同一颗
              // 图标被点亮」，而不是换了一颗图标
              child: LineIcon(
                t.icon,
                size: 22,
                color: on ? C.ink : C.ink3,
                // 选中再加一档线宽：颜色 + 重量同时变，才像「同一颗图标被点亮」
                strokeWidth: on ? 2.2 : null,
              ),
            ),
            const SizedBox(height: 4),
            // 颜色和字重一起渐变：这两个是同一个「强调」信号，分开切会打架
            AnimatedDefaultTextStyle(
              style: T.overline.copyWith(
                color: on ? C.ink : C.ink3,
                fontWeight: on ? FontWeight.w500 : FontWeight.w400,
              ),
              duration: M.fast,
              curve: M.standard,
              child: Text(t.label),
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
                // 记一笔：主文字色（纸墨原则：不引入装饰色）。全屏最常用的一颗
                // 按钮靠位置和大小被看见，不靠颜色 —— 红色只留给「超支」
                color: C.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: C.accent.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                  // 3px 白色描边：让按钮从 tabbar 上「切」出来，不然只是浮着
                  BoxShadow(color: C.cardBg, spreadRadius: 3),
                ],
              ),
              child: Center(
                child: LineIcon('plus', size: 24, color: C.onAccent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
