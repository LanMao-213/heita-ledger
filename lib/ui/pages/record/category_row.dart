import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../data/db/seeds.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/icon_map.dart';

/// 分类 + 备注的一行摘要（点开双轮盘）。也用于展示详情字段已填了哪些。
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.tree,
    required this.topId,
    required this.subId,
    required this.note,
    required this.onTap,
    this.detailSummary = const <String>[],
  });

  final CategoryTree tree;
  final int? topId;
  final int? subId;
  final String note;
  final VoidCallback onTap;

  /// 详情字段的摘要（`出发地 家 → 公司` 这种），有就显示在副行。
  final List<String> detailSummary;

  String get categoryLabel {
    if (topId == null) return '选择分类';
    final String? top = tree.byId(topId)?.name;
    final String? sub = tree.byId(subId)?.name;
    if (top == null) return '选择分类';
    return sub == null ? top : '$top · $sub';
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String subtitle = <String>[
      if (detailSummary.isNotEmpty) detailSummary.join(' · '),
      if (note.trim().isNotEmpty) note.trim(),
    ].join(' · ');

    return InkWell(
      key: const ValueKey<String>('record-category'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: S.rowTwoLine),
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
        decoration: BoxDecoration(
          color: pal.surfaceAlt,
          borderRadius: R.rMd,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: pal.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                IconMap.of(tree.byId(topId)?.icon),
                size: 18,
                color: pal.ink2,
              ),
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    categoryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ts.body.copyWith(color: pal.ink),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.caption.copyWith(color: pal.ink3),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: pal.ink4),
          ],
        ),
      ),
    );
  }
}

/// 分类摘要的纯文案（测试直接断言它，不必渲染）。
String categoryLabelOf(CategoryTree tree, int? topId, int? subId) {
  if (topId == null) return '选择分类';
  final String? top = tree.byId(topId)?.name;
  if (top == null) return '选择分类';
  final String? sub = tree.byId(subId)?.name;
  return sub == null ? top : '$top · $sub';
}

/// 这四个字段当前该不该显示（只认 `fieldsOfSub` 认的，其余一律不渲染）。
List<TxnField> activeFieldsOf(String? subName) => fieldsOfSub(subName);

/// 备注框是否要排到详情字段**前面**。
///
/// 判定：这个子分类有详情字段 → 备注在前（备注是常填的，详情是偶尔填的）。
bool noteBeforeDetails(String? subName) => fieldsOfSub(subName).isNotEmpty;

/// 切换分类后的字段值：只保留新分类认的字段（同组字段不丢）。
Map<TxnField, String> detailsAfterCategoryChange(
  String? newSubName,
  Map<TxnField, String> current,
) => pruneDetails(newSubName, current);

/// 日期 → 面板上的短文案（`10-16 周五`）。
String dateChipLabel(LocalDate d) {
  const List<String> week = <String>['一', '二', '三', '四', '五', '六', '日'];
  return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} 周${week[d.weekday - 1]}';
}
