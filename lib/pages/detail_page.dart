import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/hairline.dart';
import '../design/haptics.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/detail/summary_card.dart';
import '../widgets/detail/txn_row.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/menu.dart';
import '../widgets/picker_wheels.dart';
import 'period_all_page.dart';

/// 明细页（首页）：按周期看每一笔。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with SingleTickerProviderStateMixin {
  /// 翻期之后要把列表拉回顶部，所以必须自己持有 controller
  /// （原来是隐式的 `PrimaryScrollController`，拿不到位置就没法回顶）。
  final _scroll = ScrollController();

  /// 翻期时正文淡入用。
  ///
  /// 这里没有用 `AnimatedSwitcher` 直接包 `CustomScrollView`：那样翻期会给
  /// scroll view 换 key，翻完旧的 `ScrollPosition` 就被丢掉了，回顶动画和
  /// 「翻完停在顶部」都落不到新列表上。改成同一个 view 淡入，位置也保住了。
  late final _flipFade = AnimationController(
    vsync: this,
    value: 1,
    duration: M.base,
  );

  // ------------------------------------------------------------------ 多选

  /// 是否处于多选模式。
  ///
  /// 两个入口：顶栏的「选择」按钮，以及长按某行后的「多选」菜单项。
  /// 后者会顺手把这行选中 —— 长按的目的通常就是「我要动这一笔」。
  bool _selecting = false;

  /// 已选中的交易 id。
  ///
  /// 存 id 而不是 [Txn]：翻期、改分类之后 Txn 对象会重建，
  /// 存对象会出现「勾着的行和实际数据对不上」。
  final Set<int> _selected = <int>{};

  /// 可被选中的行（当前可见的）。全选与计数都基于它。
  List<Txn> get _selectable => Store.i.visibleTxns;

  bool get _allSelected =>
      _selectable.isNotEmpty && _selected.length >= _selectable.length;

  void _startSelecting([int? firstId]) {
    Haptics.tap();
    setState(() {
      _selecting = true;
      _selected.clear();
      if (firstId != null) _selected.add(firstId);
    });
  }

  void _exitSelecting() {
    if (!_selecting) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggle(int id) {
    Haptics.tap();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  /// 全选 / 全不选。
  ///
  /// 「全选」选的是**当前可见**的行（可能已被筛选过），不是整个账本 ——
  /// 用户看不到的东西不该被悄悄选中。
  void _toggleAll() {
    final visible = _selectable;
    Haptics.tap();
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(visible.map((t) => t.id));
      }
    });
  }

  /// 选中的 Txn 对象（按当前可见顺序）
  List<Txn> get _selectedTxns =>
      _selectable.where((t) => _selected.contains(t.id)).toList();

  Future<void> _batchCategory() async {
    final picked = _selectedTxns;
    if (picked.isEmpty) return;
    final s = Store.i;

    // 一个 category_id 不可能既是支出又是收入分类（分类表里 type 是固定值）。
    // 混合选中时强行归到某一侧，会把另一侧的记录挂到语义相反的分类下，
    // 之后预算和图表都会算歪 —— 所以先挡住，让用户分开操作。
    final types = picked.map((t) => t.type).toSet();
    if (types.length > 1) {
      await showAppNotice(
        context,
        title: '选中的类型不一致',
        message: '支出、收入、转账要分开归类。\n'
            '请先只选同一类型的记录，再改分类。',
      );
      return;
    }
    final type = picked.first.type;
    if (type == TxnType.transfer) {
      await showAppNotice(
        context,
        title: '转账没有分类',
        message: '转账记录不参与分类与预算，所以不能批量改分类。\n'
            '如需修改，请在明细里点开那一笔改。',
      );
      return;
    }

    final cats = type.isIncome ? s.incomeCats : s.expenseCats;
    final pick = await showCategoryWheel(
      context,
      cats: cats,
      childrenOf: s.childrenOf,
    );
    if (pick == null || !mounted) return;

    final n = await s.setTxnsCategory(picked, pick.txnCategoryId);
    if (!mounted) return;
    Haptics.tap();
    _exitSelecting();
    showToast(context, '已把 $n 笔改为「${s.categoryOf(pick.txnCategoryId)?.name ?? '未分类'}」');
  }

  Future<void> _batchDelete() async {
    final picked = _selectedTxns;
    if (picked.isEmpty) return;
    final total = picked.fold<int>(
      0,
      (a, t) => a + t.signedCents.abs(),
    );
    final ok = await showAppConfirm(
      context,
      title: '删除这 ${picked.length} 笔？',
      // 说清两件事：删多少、余额会退回去。删完余额不动才是怪事
      message: '合计 ${Fmt.money(total)}。\n'
          '删除后这些钱会退回各自账户的余额，不能撤销。',
      confirmLabel: '删除 ${picked.length} 笔',
      danger: true,
    );
    if (!ok || !mounted) return;

    final n = await Store.i.deleteTxns(picked);
    if (!mounted) return;
    Haptics.warn();
    _exitSelecting();
    showToast(context, '已删除 $n 笔');
  }

  @override
  void dispose() {
    _flipFade.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 横滑翻一期。
  ///
  /// **方案 B**：横向手势只挂在顶部概览卡上，列表正文不接管 ——
  /// 正文横滑仍然是切 Tab（`home_shell` 的 `PageView`）。理由：
  /// 明细页是主场、翻期是高频动作，但「横滑切 Tab」是全局习惯，
  /// 把它在整页上取消掉，代价比「手指要往上挪一点」大。
  ///
  /// 翻期没有转场动画（数据是瞬间替换的），所以必须给两样反馈：
  /// 一下轻震 + 列表回顶。少任何一样，用户都会觉得「滑了没反应」。
  Future<void> _flip(int delta) async {
    final s = Store.i;
    if (s.filter.active) return; // 筛选和「哪一期」是两个维度，别互相踩
    // 右边界：今天所在的期之后不许翻。
    // 未来的期不可能有账，翻过去只会看到一片 0.00 —— 分不清是「没记账」还是
    // 「翻过头了」。想提前给下一期设预算，走计划页或日历（那两条路没封）。
    if (delta > 0 && s.isCurrentPeriod) return;
    await s.shiftCycle(delta);
    if (!mounted) return;
    Haptics.tap();
    // 不回顶的话会停在「上一期的第 3 天」这种半截位置，看起来像翻错了。
    // 原来是 `jumpTo`：列表会「瞬移」，配上瞬间替换的数据，整个翻期就是一次
    // 硬切。改成 animateTo 之后，「列表滚回顶部」本身就是翻期的解释动画。
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0, duration: M.base, curve: M.standard));
    }
    // 数据已经换完了：正文淡入一次，代替「一帧之内整屏换掉」
    unawaited(_flipFade.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.i;

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        // 分组在这里算**一次**并复用：`groupedVisibleByDay` 每次访问都会重新
        // 建一遍 map 再排序，放进 itemBuilder 就成了「每张卡算一遍」。
        final groups = s.groupedVisibleByDay;

        return Column(
          children: [
            if (_selecting)
              _SelectBar(
                count: _selected.length,
                allSelected: _allSelected,
                onExit: _exitSelecting,
                onToggleAll: _toggleAll,
                onCategory: _batchCategory,
                onDelete: _batchDelete,
              )
            else
              _TopBar(onStartSelect: _startSelecting),
            // 顶部那排「全部/支出/收入/转账」在 1.4.5 移除了，两个原因：
            // 1) 它走的是 `searchTxns`（跨全部历史），而紧跟其下的概览卡是「本期」——
            //    两个数字上下并排却不同口径，用户只会觉得对不上；
            // 2) 类型筛选在筛选面板里已经有了，两套入口并存时状态容易混。
            // 现在「只看某类型」走筛选面板（那里也补了「转账」），
            // 筛选条会把「全部历史」写明，口径不再含糊。
            if (s.filter.active) _FilterBar(),
            Expanded(
              // 翻期的淡入挂在这一层：整块正文一起淡，而不是每张日卡各自淡
              child: FadeTransition(
                opacity: _flipFade,
                // ★ 懒加载（1.4.5）：原来是 `ListView(children: [...])`，一期几百笔
                //   会一次性构建所有行 —— 1.4.4 的「明细只显示 500 条」就是为了躲它。
                //   换成 `SliverList.builder` 后只构建可视区域内的那几张日卡，
                //   滚动时才按需建下一张，摊还成本与屏高成正比，与总条数无关。
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    // 翻期的热区就是这一块。`enabled: false` 时**不注册**横向
                    // 识别器，手势落回外层 PageView —— 这正是「筛选态下横滑
                    // 仍然切 Tab」的实现方式，不是靠 return 拦。
                    // 不加 const：SummaryCard 直接读 Store.i，const 会被 Flutter
                    // 当成「同一个 widget」跳过重建，翻期后数字会停在旧口径
                    SliverToBoxAdapter(
                      child: SwipeFlip(
                        enabled: !s.filter.active,
                        onPrev: () => _flip(-1),
                        onNext: () => _flip(1),
                        child: SummaryCard(),
                      ),
                    ),
                    if (s.visibleTxns.isEmpty)
                      SliverToBoxAdapter(
                        child: s.filter.active
                            ? const EmptyHint(
                                icon: 'list',
                                text: '没有符合条件的记录',
                                hint: '试试放宽条件，或点上面的「重置」',
                              )
                            : const EmptyHint(
                                icon: 'doc',
                                text: '这一期还没有记账',
                                hint: '点下面的「＋」记第一笔',
                              ),
                      )
                    else
                      SliverList.builder(
                        // 超大批量时的兜底提示仍留在末尾（见 _MoreHint）：
                        // 上限已经从 500 提到 2000，但「说不清楚少了」这个毛病不能回来
                        itemCount: groups.length + (s.txnTruncated ? 1 : 0),
                        itemBuilder: (context, i) => i >= groups.length
                            ? const _MoreHint()
                            : _dayCard(context, s, groups[i]),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: S.xxl)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 一天的卡：日期头 + 当日小计 + 当天的每一笔。
  ///
  /// 参数是「一天」而不是整个列表 —— 懒加载要求每次只产出一张卡。
  Widget _dayCard(
    BuildContext context,
    Store s,
    (String date, List<Txn> items) group,
  ) {
    final (date, items) = group;
    // 交叉归集：支出里的负数计入收入，收入里的负数计入支出
    final dayExpense = sumBySide(items, TxnType.expense);
    final dayIncome = sumBySide(items, TxnType.income);

    return Container(
      // 与 SectionCard 同边距（左右 16 / 上下 8）：同屏两种卡必须一样宽、
      // 一样间距，否则日卡和 SectionCard 的边界会错开一条
      margin: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.sm),
      decoration: ShapeDecoration(
        color: C.cardBg,
        // 原来是「描边 + 投影 + 白底」三层叠加，紧邻的概览卡又是「异色底 +
        // 暖描边」—— 同屏两套卡片语法，边界发糊。现在只留 E.low 一种分界手段。
        shadows: E.low,
        shape: Shape.squircle(R.card),
      ),
      child: Column(
        children: [
          // 日期是这张卡的头，放在卡里 —— 挂在卡外面的话，
          // 一屏几张卡会读成一串「小标题 + 列表」，不像卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
            child: Row(
              children: [
                // 日期让出剩余宽度：某天既有收入又有支出、数字又长时，
                // 三个 Text 并排会顶出屏幕（真机上表现为右侧被裁掉一截）
                Expanded(
                  child: Text(
                    Fmt.friendly(date),
                    style: T.caption.copyWith(
                      color: C.ink2,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (dayIncome > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: S.sm),
                    child: Text(
                      '收入 ${Fmt.money(dayIncome)}',
                      style: T.caption.copyWith(color: C.ink2),
                    ),
                  ),
                if (dayExpense > 0)
                  Text('支出 ${Fmt.money(dayExpense)}', style: T.caption),
              ],
            ),
          ),
          Divider(height: 1, thickness: hairlineOf(context), color: C.line),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: hairlineOf(context),
                color: C.line,
                indent: 56,
              ),
            TxnRow(
              txn: items[i],
              selecting: _selecting,
              selected: _selected.contains(items[i].id),
              onToggle: () => _toggle(items[i].id),
              // 长按进多选，并把这行顺手选中：长按的意图通常是「我要动这一笔」
              onEnterSelection: () => _startSelecting(items[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onStartSelect});

  /// 进入多选。顶栏按钮和长按菜单都走这一个入口，行为一致。
  final VoidCallback onStartSelect;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Padding(
      padding: const EdgeInsets.only(top: S.sm),
      child: PageHeader(
        title: s.currentLedger?.name ?? '账本',
        // 侧拉栏的把手固定在最左，四页一致
        leading: const MenuButton(),
        // 账本名右侧的切换箭头：它不是「更多动作」，是标题的一部分
        titleSuffix: s.ledgers.length > 1
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickLedger(context),
                child: Padding(
                  padding: EdgeInsets.only(left: S.sm),
                  child: LineIcon('chevron_down', size: 18, color: C.ink3),
                ),
              )
            : null,
        actions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _openFilter(context),
              tooltip: '筛选',
              icon: LineIcon(
                'filter',
                size: 20,
                color: s.filter.active ? C.ink : C.ink2,
              ),
              splashRadius: 20,
            ),
            IconButton(
              onPressed: () => _search(context),
              icon: LineIcon(
                'search',
                semanticLabel: '搜索',
                size: 20,
                color: C.ink2,
              ),
              splashRadius: 20,
            ),
            IconButton(
              // 放在最右：它是最「重」的一个动作，进来就离开当前浏览状态
              onPressed: onStartSelect,
              tooltip: '多选',
              icon: LineIcon(
                'check',
                semanticLabel: '多选',
                size: 20,
                color: C.ink2,
              ),
              splashRadius: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilter(BuildContext context) async {
    final s = Store.i;
    final f = await showFilterSheet(context, s.filter.current);
    if (f == null) return;
    try {
      await s.applyFilter(f);
    } catch (_) {
      if (context.mounted) showToast(context, '筛选失败，请重试');
    }
  }

  Future<void> _pickLedger(BuildContext context) async {
    final s = Store.i;
    await showMenuSheet<void>(
      context: context,
      title: '切换账本',
      groups: [
        MenuGroup(
          actions: [
            for (final l in s.ledgers)
              MenuAction(
                icon: l.icon,
                title: l.name,
                checked: l.id == s.ledgerId,
                onTap: () async {
                  // 切过去的账本可能欠着好几期周期账单，补记是 switchLedger 做的，
                  // 这里只负责说出来
                  final added = await s.switchLedger(l.id);
                  if (added > 0 && context.mounted) {
                    showToast(context, '已补记 $added 笔周期账单');
                  }
                },
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _search(BuildContext context) async {
    final s = Store.i;
    final keyword = await showSearch<String>(
      context: context,
      delegate: _SearchDelegate(),
    );
    if (keyword == null || keyword.trim().isEmpty) return;
    final (hits, truncated) = await Repo.searchTxns(
      ledgerId: s.ledgerId,
      keyword: keyword,
    );
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx2, controller) => SheetShell(
          title: '搜索「$keyword」',
          subtitle: '${hits.length}${truncated ? '+' : ''} 条',
          child: Expanded(
            child: hits.isEmpty
                ? const EmptyHint(text: '没有找到匹配的记录')
                : ListView.builder(
                    controller: controller,
                    itemCount: hits.length,
                    itemBuilder: (c, i) => TxnRow(txn: hits[i], showDate: true),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 多选态的顶栏 + 操作条。
///
/// 做成上下一条，而不是「顶栏换掉、操作放在屏幕底部」：底部会被「记一笔」
/// 的 FAB 压住，而且手指刚在顶部点完全选，接下来要去屏幕另一头按删除 ——
/// 动线是折的。放一起，选中与操作在同一个视线区域内。
class _SelectBar extends StatelessWidget {
  const _SelectBar({
    required this.count,
    required this.allSelected,
    required this.onExit,
    required this.onToggleAll,
    required this.onCategory,
    required this.onDelete,
  });

  final int count;
  final bool allSelected;
  final VoidCallback onExit;
  final VoidCallback onToggleAll;
  final VoidCallback onCategory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;
    return Column(
      children: [
        PageHeader(
          // 一条都没选时说「选择记录」，不说「已选 0 条」——后者像个错误提示
          title: enabled ? '已选 $count 条' : '选择记录',
          leading: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExit,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: S.sm,
                horizontal: S.xs,
              ),
              child: Text('取消', style: T.body2.copyWith(color: C.ink2)),
            ),
          ),
          actions: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: S.lg,
                vertical: S.sm,
              ),
              child: Text(
                allSelected ? '全不选' : '全选',
                style: T.body2.copyWith(color: C.ink),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.sm),
          child: Row(
            children: [
              Expanded(
                child: _BatchButton(
                  icon: 'tag',
                  label: '改分类',
                  enabled: enabled,
                  onTap: onCategory,
                ),
              ),
              const SizedBox(width: S.sm),
              Expanded(
                child: _BatchButton(
                  icon: 'trash',
                  label: '删除',
                  enabled: enabled,
                  danger: true,
                  onTap: onDelete,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 批量操作按钮。禁用态用最浅的文字色，但**仍然占位** ——
/// 一进来按钮就消失，用户不知道这里本来有东西。
class _BatchButton extends StatelessWidget {
  const _BatchButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  final String icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled ? C.ink3 : (danger ? C.over : C.ink);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LineIcon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(label, style: T.body2.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _SearchDelegate extends SearchDelegate<String> {
  /// 搜索范围 1.4.4 起扩到分类名、账户名、金额 —— 输入框里得先说清，
  /// 否则用户还是只会往备注上试
  @override
  String get searchFieldLabel => '备注、分类、账户、金额';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        onPressed: () => query = '',
        icon: LineIcon('close', size: 22, color: C.ink2, semanticLabel: '关闭'),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, ''),
    icon: LineIcon('arrow_left', size: 22, color: C.ink, semanticLabel: '返回'),
  );

  @override
  Widget buildResults(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox.shrink();

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: InputBorder.none,
      hintStyle: TextStyle(color: C.ink3),
    ),
  );
}

/// 明细被上限截断时，列表末尾的说明 + 「看全部」入口。
///
/// 做成整条可点，而不是只在文字里放个链接：这一行的唯一用途就是跳转，
/// 手指点哪儿都该管用。
class _MoreHint extends StatelessWidget {
  const _MoreHint();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.card),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PeriodAllPage()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 14),
          decoration: BoxDecoration(
            color: C.bg2,
            borderRadius: BorderRadius.circular(R.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '仅显示最近 ${Store.txnPageLimit} 条'
                  '${s.txnCount > Store.txnPageLimit ? ' · 本期共 ${s.txnCount} 笔' : ''}',
                  style: T.caption.copyWith(color: C.ink2),
                ),
              ),
              Text(
                '查看本期全部',
                style: T.caption.copyWith(
                  color: C.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              LineIcon('chevron_right', size: 18, color: C.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选条件条：常驻在顶部，随时能看清当前条件并一键清空
class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final f = s.filter.current;
    final chips = <String>[
      // 口径写在脸上：明细的筛选一律跨**全部历史**，而上面的概览卡只算本期。
      // 不写明的话，筛完就会看到「上面本期 5,061、下面列出去年的收入」——
      // 1.4.5 撤掉顶部快捷筛选之后，这里是唯一需要解释范围的地方。
      if (f.dateFrom == null && f.dateTo == null) '全部历史',
      if (f.type != null) f.type!.label,
      if (f.categoryId != null) s.categoryOf(f.categoryId)?.name ?? '已删除分类',
      if (f.accountId != null) s.accountOf(f.accountId)?.name ?? '已删除账户',
      if (f.amountLabel != null) f.amountLabel!,
      if (f.dateLabel != null) f.dateLabel!,
      if (s.filter.truncated) '仅显示前 ${Repo.searchLimit} 条',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(S.xl, 0, S.sm, S.sm),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: S.sm),
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        // 左右 10 是筛选 chip（高 28 固定）的内缩，不是节奏间距
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: C.bg2,
                          borderRadius: BorderRadius.circular(R.sm),
                        ),
                        child: Text(
                          c,
                          style: T.caption.copyWith(color: C.ink2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => s.clearFilter(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: S.sm,
                vertical: 4,
              ),
              child: Text(
                '重置',
                style: T.caption.copyWith(
                  color: C.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
