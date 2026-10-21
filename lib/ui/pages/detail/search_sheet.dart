import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/txn_repo.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/sheet_frame.dart';

/// 搜索面板（0.7 高）。返回关键词；取消返回 `null`。
///
/// 口径（§3.9）：匹配 5 个文本列 + 分类名（含父名）+ 账户名（两端）+ 金额
/// （整体匹配且数字位 ≥2）—— 全部在数据层，这里只负责输入与结果展示。
Future<String?> showSearchSheet(
  BuildContext context, {
  required int ledgerId,
  required String Function(int?) categoryOf,
  required String Function(int?) accountOf,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _SearchBody(
      ledgerId: ledgerId,
      categoryOf: categoryOf,
      accountOf: accountOf,
    ),
  );
}

/// 结果标题：`搜索「38.5」 · 3 条`（截断时 3+）。
String searchResultTitle(String keyword, int count, {bool truncated = false}) =>
    '搜索「${keyword.trim()}」 · $count${truncated ? '+' : ''} 条';

class _SearchBody extends StatefulWidget {
  const _SearchBody({
    required this.ledgerId,
    required this.categoryOf,
    required this.accountOf,
  });

  final int ledgerId;
  final String Function(int?) categoryOf;
  final String Function(int?) accountOf;

  @override
  State<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<_SearchBody> {
  final TextEditingController _controller = TextEditingController();
  TxnSearchResult? _result;
  bool _loading = false;
  int _seq = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String keyword) async {
    final int seq = ++_seq;
    if (keyword.trim().isEmpty) {
      setState(() {
        _result = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final TxnSearchResult r = await const TxnRepo().search(
        ledgerId: widget.ledgerId,
        query: TxnQuery(keyword: keyword.trim()),
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _result = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String keyword = _controller.text.trim();
    final TxnSearchResult? result = _result;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: SheetFrame(
        title: '搜索',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('search-input'),
              controller: _controller,
              autofocus: true,
              style: Ts.body.copyWith(color: pal.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.surfaceAlt,
                hintText: '备注、分类、账户、金额',
                hintStyle: Ts.body2.copyWith(color: pal.ink4),
                prefixIcon: Icon(Icons.search, size: 18, color: pal.ink3),
                border: OutlineInputBorder(
                  borderRadius: R.rMd,
                  borderSide: BorderSide(color: pal.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: R.rMd,
                  borderSide: BorderSide(color: pal.line),
                ),
              ),
              onChanged: _run,
              onSubmitted: (String v) => Navigator.of(context).pop(v.trim()),
            ),
            const SizedBox(height: S.sm),
            Text(
              keyword.isEmpty
                  ? '支持备注、分类名、账户名与金额'
                  : searchResultTitle(
                      keyword,
                      result?.totals.count ?? 0,
                      truncated: result?.truncated ?? false,
                    ),
              key: const ValueKey<String>('search-title'),
              style: Ts.caption.copyWith(color: pal.ink3),
            ),
            const SizedBox(height: S.sm),
            Expanded(
              child: _loading
                  ? Center(
                      child: Text(
                        '正在搜索…',
                        style: Ts.caption.copyWith(color: pal.ink3),
                      ),
                    )
                  : ListView.builder(
                      itemCount: result?.items.length ?? 0,
                      itemBuilder: (BuildContext ctx, int i) {
                        final Txn t = result!.items[i];
                        // 面板外壳有底色，ListTile 的水波要落在自己的透明 Material 上
                        return Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            key: ValueKey<String>('search-hit-${t.id}'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              widget.categoryOf(t.categoryId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ts.body.copyWith(color: pal.ink),
                            ),
                            subtitle: Text(
                              '${t.date.iso}${t.note.isEmpty ? '' : ' · ${t.note}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ts.caption.copyWith(color: pal.ink3),
                            ),
                            trailing: AmountText(
                              cents: t.type.isIncome
                                  ? t.amountCents.abs()
                                  : -t.amountCents.abs(),
                              style: Ts.amountSm,
                            ),
                            onTap: () => Navigator.of(context).pop(keyword),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: S.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '点一条结果或按回车，回到明细看这批记录',
                    style: Ts.caption.copyWith(color: pal.ink3),
                  ),
                ),
                FilledButton(
                  key: const ValueKey<String>('search-apply'),
                  onPressed: keyword.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(keyword),
                  child: const Text('查看'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果里日期列的文案（`10-16`）。搜索结果的副行用它。
String searchDateLabel(LocalDate d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
