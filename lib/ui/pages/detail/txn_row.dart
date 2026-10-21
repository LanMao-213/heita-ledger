import 'package:flutter/material.dart';

import '../../../data/models/models.dart';
import '../../../data/repo/sql_fragments.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/icon_map.dart';
import '../../widgets/list_tile_row.dart';

/// 明细的一行。
///
/// 两种形态（口径 3.5）：
/// - **普通流水**：标题恒为分类名，副行按序拼接（账户 → 详情 → 备注 → 周期标签）；
/// - **借贷流水**：标题「借出 · 张三」、金额用 `ink3` 中性灰（不是支出红），
///   副行首位「应还 11-30」，点击**进往来详情**而不是编辑面板。
class TxnRow extends StatelessWidget {
  const TxnRow({
    super.key,
    required this.txn,
    required this.categoryLabel,
    required this.accountLabel,
    this.debtLabel,
    this.dueLabel,
    this.onTap,
    this.onLongPress,
  });

  final Txn txn;

  /// `餐饮 · 正餐`（借贷行为空）。
  final String categoryLabel;

  final String accountLabel;

  /// 借贷行的「借出 · 张三」。
  final String? debtLabel;

  /// 「应还 11-30」。
  final String? dueLabel;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  bool get isDebt => txn.debtId != null;

  /// 标题：借贷行是「借出 · 张三」，普通行恒为分类名。
  String get title => isDebt ? (debtLabel ?? '借贷') : categoryLabel;

  /// 副行按序拼接（单行 ellipsis）。
  ///
  /// 顺序刻意固定：借贷「应还日」在最前（最要紧），然后是账户、详情、
  /// 备注；每段之间用「·」分隔，空段自动跳过。
  String get subtitle {
    final List<String> parts = <String>[
      if (isDebt && (dueLabel ?? '').isNotEmpty) dueLabel!,
      if (!isDebt) accountLabel,
      if (txn.person != null) txn.person!,
      if (txn.placeFrom != null || txn.placeTo != null)
        '${txn.placeFrom ?? '—'} → ${txn.placeTo ?? '—'}',
      if (txn.subject != null) txn.subject!,
      if (txn.note.isNotEmpty) txn.note,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final int displayCents = txn.type.isIncome
        ? txn.amountCents.abs()
        : -txn.amountCents.abs();

    return ListTileRow(
      key: ValueKey<String>('txn-row-${txn.id}'),
      minHeight: S.rowTxn,
      showDivider: true,
      leadingIcon: IconMap.of(isDebt ? 'gift' : null),
      title: Row(
        children: <Widget>[
          Flexible(child: RowTitle(title)),
          if (txn.recurringId != null) ...<Widget>[
            const SizedBox(width: S.xs),
            Container(
              key: const ValueKey<String>('txn-badge-recurring'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: pal.surfaceAlt,
                borderRadius: R.rSm,
              ),
              child: Text(
                '周期',
                style: Ts.badge.copyWith(color: pal.ink3),
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ts.caption.copyWith(color: pal.ink3),
            ),
      trailing: AmountText(
        cents: displayCents,
        style: Ts.amount,
        // 借贷行：中性灰（不是 over 也不是 ink），它既不是收入也不是支出
        color: isDebt ? pal.ink3 : pal.ink,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// 删除确认弹窗的正文：「分类名 · ±金额」+ 备注换行。
///
/// 只写「确定删除吗」等于让用户凭记忆确认一笔钱 —— 必须把要删的东西写清楚。
String deleteConfirmBody(Txn txn, {required String categoryLabel}) {
  final int signed = txn.type.isIncome ? txn.amountCents.abs() : -txn.amountCents.abs();
  final String head = '${categoryLabel.isEmpty ? '未分类' : categoryLabel} · '
      '${signed > 0 ? '+' : '-'}¥${signed.abs() ~/ 100}.${(signed.abs() % 100).toString().padLeft(2, '0')}';
  final String note = txn.note.trim();
  return note.isEmpty ? head : '$head\n$note';
}

/// 末尾状态行：「已显示 N / 共 M」。
class ListStatusRow extends StatelessWidget {
  const ListStatusRow({
    super.key,
    required this.loaded,
    required this.total,
    required this.loading,
  });

  final int loaded;
  final int total;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String text = loading
        ? '正在加载…'
        : (loaded >= total
              ? (total == 0 ? '' : '已显示全部 $total 笔')
              : '已显示 $loaded / 共 $total');
    if (text.isEmpty) return const SizedBox(height: S.xxl);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.page, S.lg, S.page, S.xxxl),
      child: Center(
        child: Text(
          text,
          key: const ValueKey<String>('list-status'),
          style: Ts.caption.copyWith(color: pal.ink3),
        ),
      ),
    );
  }
}

/// 列表一次最多取多少（与 repo 的 `pageSize` 同一个源）。
int get kPageSize => SqlFragments.pageSize;
