import 'package:flutter/material.dart';

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
  bool _recurringNotified = false;

  static const _tabs = [
    (icon: 'list', label: '明细'),
    (icon: 'pie', label: '图表'),
    (icon: 'target', label: '计划'),
    (icon: 'person', label: '我的'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyRecurring());
  }

  /// 周期账单补记只提示一次，不打扰
  void _notifyRecurring() {
    if (_recurringNotified) return;
    final n = Store.i.recurringJustAdded;
    if (n > 0 && mounted) {
      _recurringNotified = true;
      showToast(context, '已补记 $n 笔周期账单');
    }
  }

  Future<void> _openRecord() async {
    final saved = await showRecordSheet(context);
    if (saved == true && mounted) {
      showToast(context, '已记账');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Store.i;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: store.tabIndex,
            children: const [
              DetailPage(),
              StatsPage(),
              PlanPage(),
              MinePage(),
            ],
          ),
        ),
        bottomNavigationBar: _TabBar(
          index: store.tabIndex,
          tabs: _tabs,
          onSelect: store.switchTab,
          onRecord: _openRecord,
        ),
      ),
    );
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
          child: Row(
            children: [
              _tab(0),
              _tab(1),
              _fab(),
              _tab(2),
              _tab(3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(int i) {
    final on = index == i;
    final t = tabs[i];
    return Expanded(
      child: InkWell(
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
                child: LineIcon('plus', size: 24, color: C.bg, strokeWidth: 1.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
