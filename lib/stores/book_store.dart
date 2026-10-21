import '../../core/local_date.dart';
import '../../core/period.dart';
import '../data/models/models.dart';
import '../data/repo/budget_repo.dart';
import '../data/repo/sql_fragments.dart';
import '../data/repo/txn_repo.dart';
import 'shell_store.dart';

/// 明细页的状态：期游标 + 当前期合计 + keyset 分页 + 筛选/搜索。
///
/// 只订阅它的是明细页；记一笔之后由 [afterTxnInserted] 统一搬游标并重查
/// （**1 次通知**，见 §5.1 的通知预算表）。
class BookStore extends StoreBase {
  BookStore();

  final TxnRepo _txnRepo = const TxnRepo();

  int _ledgerId = 0;
  int _cycleStartDay = 1;
  Period _cycle = Period(
    from: LocalDate.today().firstOfMonth,
    to: LocalDate.today().lastOfMonth,
  );

  RangeTotals _totals = RangeTotals.zero;
  List<Txn> _items = <Txn>[];
  bool _hasMore = false;
  bool _loaded = false;

  TxnQuery _query = const TxnQuery();
  TxnSearchResult? _searchResult;

  int get ledgerId => _ledgerId;
  int get cycleStartDay => _cycleStartDay;

  /// 当前期（含头含尾）。
  Period get cycle => _cycle;

  /// 当前期两侧合计（概览卡）。
  RangeTotals get totals => _totals;

  /// 明细（未筛选时 = 当前期第一页）。
  List<Txn> get items => _items;

  bool get hasMore => _hasMore;

  TxnQuery get query => _query;

  /// 是否处于筛选态（筛选时列表跨全部历史，且概览卡换成筛选结果）。
  bool get isFiltering => !_query.isEmpty;

  /// 筛选结果（含截断标志与全量合计）。
  TxnSearchResult? get searchResult => _searchResult;

  /// 还没加载过 —— 首帧「骨架 vs 空态」靠它区分（I20）：
  /// 没加载过要画骨架，加载过但为空才是「本期还没有数据」。
  bool get isCold => !_loaded;

  /// 绑定账本 + 账单日，并把游标重置到今天所在期。
  Future<void> bind({required int ledgerId, required int cycleStartDay}) async {
    _ledgerId = ledgerId;
    _cycleStartDay = cycleStartDay;
    _cycle = Period.cycleRange(LocalDate.today(), cycleStartDay);
    _query = const TxnQuery();
    _searchResult = null;
    _items = <Txn>[];
    _totals = RangeTotals.zero;
    _loaded = false;
  }

  /// 游标回到「今天所在的期」。
  void resetCycleToToday() {
    _cycle = Period.cycleRange(LocalDate.today(), _cycleStartDay);
  }

  /// 翻期（`delta` 正数往后）。**不许翻到今天之后的期**。
  ///
  /// 理由：未来期只会有 0.00，用户分不清「还没记账」和「翻过头了」。
  void moveCycle(int delta) {
    final Period next = Period.shiftCycle(_cycle, delta, _cycleStartDay);
    final Period today = Period.cycleRange(LocalDate.today(), _cycleStartDay);
    if (next.from > today.from) return;
    _cycle = next;
  }

  /// 重查当前期（合计 + 第一页）。筛选态下重查筛选结果。
  Future<void> reloadCycle() async {
    await batchNotifyAsync<void>(() async {
      if (isFiltering) {
        await _reloadSearch();
      } else {
        _totals = await _txnRepo.totalsInPeriod(
          ledgerId: _ledgerId,
          period: _cycle,
        );
        _items = await _txnRepo.pageByPeriod(
          ledgerId: _ledgerId,
          period: _cycle,
        );
        _hasMore = _items.length >= SqlFragments.pageSize;
      }
      _loaded = true;
      notifyListeners();
    });
  }

  /// 加载下一页（keyset：带着上一页最后一行的 date+id）。
  Future<void> loadMore() async {
    if (!_hasMore || isFiltering || _items.isEmpty) return;
    final Txn last = _items.last;
    final List<Txn> next = await _txnRepo.pageByPeriod(
      ledgerId: _ledgerId,
      period: _cycle,
      after: TxnCursor(date: last.date, id: last.id!),
    );
    batchNotify(() {
      _items = <Txn>[..._items, ...next];
      _hasMore = next.length >= SqlFragments.pageSize;
      notifyListeners();
    });
  }

  /// 应用筛选条件（跨全部历史）。空条件等于「清筛选」。
  Future<void> applyFilter(TxnQuery query) async {
    _query = query;
    if (query.isEmpty) {
      _searchResult = null;
      await reloadCycle();
      return;
    }
    await batchNotifyAsync<void>(() async {
      await _reloadSearch();
      notifyListeners();
    });
  }

  void resetFilter() {
    if (_query.isEmpty) return;
    _query = const TxnQuery();
    _searchResult = null;
  }

  Future<void> _reloadSearch() async {
    final TxnSearchResult result = await _txnRepo.search(
      ledgerId: _ledgerId,
      query: _query,
    );
    _searchResult = result;
    _items = result.items;
    _totals = result.totals;
    _hasMore = false;
  }

  /// 记一笔之后：**清筛选 → 搬游标 → 重查**，全程 1 次通知（I12）。
  ///
  /// 原版 1.4.1 的三个「记完看不见」就是这里没做全：游标停在别的期 /
  /// 抬期把工资算进下一期 / 明细还挂着筛选 —— 用户会以为没记上，再记一遍。
  Future<void> afterTxnInserted(LocalDate periodStart) async {
    await batchNotifyAsync<void>(() async {
      _query = const TxnQuery();
      _searchResult = null;
      if (periodStart != _cycle.from) {
        // 游标对齐到这笔所在的期（`periodStart` 就是期首，直接反解整期）
        _cycle = Period.cycleRange(periodStart, _cycleStartDay);
      }
      await _reloadWithoutNotify();
      notifyListeners();
    });
  }

  /// 改一笔 / 删一笔之后：**不搬游标**（用户正看着那一行），只重查。
  Future<void> afterTxnChange() async {
    await batchNotifyAsync<void>(() async {
      await _reloadWithoutNotify();
      notifyListeners();
    });
  }

  Future<void> _reloadWithoutNotify() async {
    if (isFiltering) {
      await _reloadSearch();
      return;
    }
    _totals = await _txnRepo.totalsInPeriod(
      ledgerId: _ledgerId,
      period: _cycle,
    );
    _items = await _txnRepo.pageByPeriod(ledgerId: _ledgerId, period: _cycle);
    _hasMore = _items.length >= SqlFragments.pageSize;
    _loaded = true;
  }

  /// 预算派生值（详情页概览卡的预算条）。
  Future<BudgetStats> budgetStatsForCurrentCycle() =>
      const BudgetRepo().stats(ledgerId: _ledgerId, period: _cycle);
}
