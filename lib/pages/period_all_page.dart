import 'package:flutter/material.dart';

import '../data/cycle.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/hairline.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/detail/txn_row.dart';

/// 本期全览：这一期的**全部**记录，按天分组，懒加载。
///
/// 为什么单独一页，而不是把明细列表的上限调大：明细页是「按天分卡」的非懒加载
/// 列表（每天一个卡片一次性全建），一期几千笔会直接卡死。而 1.4.3 之前
/// 超出的部分是**静默丢弃**的 —— 概览卡写着「620 笔」，列表只有 500 条，
/// 用户既不知道少了，也没有任何入口能看到剩下的。
///
/// 所以这里换个形状：扁平列表 + [ListView.builder] + 分批查询，多少条都能画。
/// 代价是少了卡片分隔，换来的是「数字和列表终于对得上」。
class PeriodAllPage extends StatefulWidget {
  const PeriodAllPage({super.key});

  @override
  State<PeriodAllPage> createState() => _PeriodAllPageState();
}

class _PeriodAllPageState extends State<PeriodAllPage> {
  /// 每批取多少。200 条足够填满一屏还有余量，又不至于让首屏等太久。
  static const _batch = 200;

  /// 进页面时把期钉住：翻期是明细页的动作，这一页开着的时候不该跟着变
  late final int _ledgerId = Store.i.ledgerId;
  late final String _from = Store.i.cycleFrom;
  late final String _to = Store.i.cycleTo;
  late final int _total = Store.i.txnCount;

  final List<Txn> _txns = [];
  final _ctl = ScrollController();
  bool _loading = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctl.hasClients) return;
    // 提前 400px 开始取下一批，滚到底时数据已经在了
    if (_ctl.position.pixels >= _ctl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    _loading = true;
    // 游标翻页：接着上一页最后一条往后取。
    // 原先用 `offset: _txns.length`，只要用户在翻页过程中又记了一笔，
    // 第二页就会整体后移一位 —— 某条重复出现、另一条被跳过。
    final last = _txns.isEmpty ? null : _txns.last;
    final batch = await Repo.rangeListTxns(
      ledgerId: _ledgerId,
      from: _from,
      to: _to,
      limit: _batch,
      afterDate: last?.date,
      afterId: last?.id,
    );
    if (!mounted) return;
    setState(() {
      _txns.addAll(batch);
      // 取回来的不足一批，说明到底了
      _done = batch.length < _batch;
      _loading = false;
    });
    // 一屏都没填满时（比如本来就只有几条），滚动事件永远不会触发，
    // 这里补一次判断，把剩下的一次性取完
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _done || !_ctl.hasClients) return;
      if (_ctl.position.maxScrollExtent <= 0) _loadMore();
    });
  }

  /// 摊平成「日期头 + 记录」的一维列表，交给 ListView.builder
  List<Object> get _rows {
    final out = <Object>[];
    String? day;
    for (final t in _txns) {
      if (t.date != day) {
        day = t.date;
        out.add(day);
      }
      out.add(t);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    // 尾部一条状态行：还在取 / 已经到底
    final footer = 1;

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('本期全览'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: LineIcon('arrow_left', semanticLabel: '返回', size: 22, color: C.ink),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cycleLabel(_from, _to),
                    style: T.caption.copyWith(color: C.ink2),
                  ),
                ),
                Text('共 $_total 笔', style: T.caption),
              ],
            ),
          ),
          Divider(height: 1, thickness: hairlineOf(context), color: C.line),
          Expanded(
            child: rows.isEmpty
                ? const EmptyHint(
                    icon: 'doc',
                    text: '这一期还没有记账',
                    hint: '回明细页点「＋」记第一笔',
                  )
                : ListView.builder(
                    controller: _ctl,
                    itemCount: rows.length + footer,
                    itemBuilder: (c, i) {
                      if (i == rows.length) return _footer();
                      final row = rows[i];
                      if (row is String) return _dayHeader(row);
                      // 前一天的第一条上方不加线：日期就是那张「头」，
                      // 再画一条会把头和内容割开
                      final prev = i > 0 ? rows[i - 1] : null;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (prev is Txn)
                            Divider(
                              height: 1,
                              thickness: hairlineOf(context),
                              color: C.line,
                              indent: S.lg + 36 + S.md,
                            ),
                          TxnRow(txn: row as Txn),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dayHeader(String date) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, S.sm),
      child: Text(
        Fmt.friendly(date),
        style: T.caption.copyWith(color: C.ink2, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _footer() {
    final text = _done
        ? '已经是本期全部 $_total 笔'
        : '正在加载…（已显示 ${_txns.length} / $_total）';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.xl),
      child: Center(
        child: Text(text, style: T.caption.copyWith(color: C.ink3)),
      ),
    );
  }
}
