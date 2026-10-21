import 'package:flutter/material.dart';

import '../../../data/db/seeds.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// 四个分类详情字段（出发地 / 目的地 / 对象 / 名称）。
///
/// 三条规则（M12-F05）：
/// 1. **只渲染 `fieldsOfSub(子分类名)` 认的字段** —— 买书不显示「出发地」；
/// 2. 换分类时按 `pruneDetails` 清理，**同组字段不丢**（公共交通 ⇄ 打车）；
/// 3. 有详情字段时**备注框排在前面**（备注常填，详情偶尔填）。
///
/// 地点两端默认折叠在「＋ 详情」里（`kFoldedSubs`），避免白占两行高度。
class DetailBlock extends StatelessWidget {
  const DetailBlock({
    super.key,
    required this.subName,
    required this.values,
    required this.onChanged,
    this.folded = false,
    this.onToggleFold,
  });

  /// 子分类名（为 null 表示「不细分」→ 没有详情字段）。
  final String? subName;

  final Map<TxnField, String> values;

  /// 某一个字段变了（已按当前分类过滤过）。
  final ValueChanged<Map<TxnField, String>> onChanged;

  /// 是否处于折叠态（地点两端默认折叠）。
  final bool folded;

  final VoidCallback? onToggleFold;

  List<TxnField> get activeFields => fieldsOfSub(subName);

  bool get canFold => activeFields.isNotEmpty && kFoldedSubs.contains(subName);

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    if (activeFields.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (canFold)
          TextButton(
            key: const ValueKey<String>('record-detail-toggle'),
            onPressed: onToggleFold,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, S.touch),
              alignment: Alignment.centerLeft,
            ),
            child: Text(
              folded ? '＋ 详情' : '收起详情',
              style: Ts.caption.copyWith(color: pal.ink2),
            ),
          ),
        if (!folded)
          for (final TxnField field in activeFields)
            Padding(
              padding: const EdgeInsets.only(bottom: S.sm),
              child: TextFormField(
                key: ValueKey<String>('record-detail-${field.name}'),
                initialValue: values[field] ?? '',
                style: Ts.body.copyWith(color: pal.ink),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: pal.surfaceAlt,
                  hintText: field.hint,
                  hintStyle: Ts.body2.copyWith(color: pal.ink4),
                  labelText: field.label,
                  labelStyle: Ts.caption.copyWith(color: pal.ink3),
                  border: OutlineInputBorder(
                    borderRadius: R.rMd,
                    borderSide: BorderSide(color: pal.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: R.rMd,
                    borderSide: BorderSide(color: pal.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: R.rMd,
                    borderSide: BorderSide(color: pal.ink3),
                  ),
                ),
                // 每次输入都把整组值回传（父层再 prune 一次，双保险）
                onChanged: (String v) {
                  final Map<TxnField, String> next = <TxnField, String>{
                    ...values,
                    field: v,
                  };
                  onChanged(pruneDetails(subName, next));
                },
              ),
            ),
      ],
    );
  }
}
