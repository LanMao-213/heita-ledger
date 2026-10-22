import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/hairline.dart';
import '../design/haptics.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/detail/summary_card.dart';
import '../widgets/detail/txn_row.dart';
import '../widgets/filter_sheet.dart';
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
    if (s.filtering) return; // 筛选和「哪一期」是两个维度，别互相踩
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
            const _TopBar(),
            // 顶部那排「全部/支出/收入/转账」在 1.4.5 移除了，两个原因：
            // 1) 它走的是 `searchTxns`（跨全部历史），而紧跟其下的概览卡是「本期」——
            //    两个数字上下并排却不同口径，用户只会觉得对不上；
            // 2) 类型筛选在筛选面板里已经有了，两套入口并存时状态容易混。
            // 现在「只看某类型」走筛选面板（那里也补了「转账」），
            // 筛选条会把「全部历史」写明，口径不再含糊。
            if (s.filtering) _FilterBar(),
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
                        enabled: !s.filtering,
                        onPrev: () => _flip(-1),
                        onNext: () => _flip(1),
                        child: SummaryCard(),
                      ),
                    ),
                    if (s.visibleTxns.isEmpty)
                      SliverToBoxAdapter(
                        child: s.filtering
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
      margin: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.sm),
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
            TxnRow(txn: items[i]),
          ],
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Padding(
      padding: const EdgeInsets.only(top: S.sm),
      child: Row(
        children: [
          const SizedBox(width: S.xl),
          Text(s.currentLedger?.name ?? '账本', style: T.title),
          const SizedBox(width: S.sm),
          if (s.ledgers.length > 1)
            GestureDetector(
              onTap: () => _pickLedger(context),
              child: const Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: C.ink3,
              ),
            ),
          const Spacer(),
          IconButton(
            onPressed: () => _openFilter(context),
            tooltip: '筛选',
            icon: Icon(
              Icons.tune_rounded,
              size: 20,
              color: s.filtering ? C.ink : C.ink2,
            ),
            splashRadius: 20,
          ),
          IconButton(
            onPressed: () => _search(context),
            icon: const Icon(Icons.search_rounded, size: 20, color: C.ink2),
            splashRadius: 20,
          ),
          const SizedBox(width: S.sm),
        ],
      ),
    );
  }

  Future<void> _openFilter(BuildContext context) async {
    final s = Store.i;
    final f = await showFilterSheet(context, s.filter);
    if (f == null) return;
    try {
      await s.applyFilter(f);
    } catch (_) {
      if (context.mounted) showToast(context, '筛选失败，请重试');
    }
  }

  Future<void> _pickLedger(BuildContext context) async {
    final s = Store.i;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(title: '切换账本'),
            for (final l in s.ledgers)
              SettingRow(
                icon: l.icon,
                title: l.name,
                trailing: l.id == s.ledgerId
                    ? const Icon(Icons.check_rounded, size: 20, color: C.ink)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  // 切过去的账本可能欠着好几期周期账单，补记是 switchLedger 做的，
                  // 这里只负责说出来
                  final added = await s.switchLedger(l.id);
                  if (added > 0 && context.mounted) {
                    showToast(context, '已补记 $added 笔周期账单');
                  }
                },
              ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
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
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx2, controller) => Column(
          children: [
            SheetHeader(
              title: '搜索「$keyword」 · ${hits.length}${truncated ? '+' : ''} 条',
            ),
            Expanded(
              child: hits.isEmpty
                  ? const EmptyHint(text: '没有找到匹配的记录')
                  : ListView.builder(
                      controller: controller,
                      itemCount: hits.length,
                      itemBuilder: (c, i) =>
                          TxnRow(txn: hits[i], showDate: true),
                    ),
            ),
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
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, ''),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox.shrink();

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: InputBorder.none,
      hintStyle: TextStyle(color: C.ink4),
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
              const Icon(Icons.chevron_right_rounded, size: 18, color: C.ink2),
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
    final f = s.filter;
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
      if (s.filterTruncated) '仅显示前 ${Repo.searchLimit} 条',
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
