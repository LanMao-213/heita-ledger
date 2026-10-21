import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/icon_map.dart';

/// 「最近 3 个模板」的取值（判据 7.4 的排序：用过次数 → 最后使用 → 次序 → id）。
///
/// 抽成纯函数：面板里的模板条、模板页的「最近」分组、以及测试都读这一份，
/// 免得「面板说最近是 A，列表说最近是 B」。
List<TxnTemplate> recentTemplates(
  List<TxnTemplate> all, {
  int limit = 3,
}) {
  final List<TxnTemplate> sorted = <TxnTemplate>[...all]
    ..sort(TxnTemplate.recentSort);
  return sorted.take(limit).toList();
}

/// 手敲的一笔能不能归到某个模板头上（判据 7.4 的最后一句）。
///
/// 只看三个字段：类型 + 分类 + 金额。备注和账户不参与 —— 用户给同一笔账
/// 写不同备注是常态，把这算成「不是同一个模板」等于永远不计数。
TxnTemplate? matchTemplateFor(List<TxnTemplate> all, Txn txn) {
  for (final TxnTemplate t in all) {
    if (t.type != txn.type) continue;
    if (t.categoryId != txn.categoryId) continue;
    if (t.amountCents != txn.amountCents) continue;
    return t;
  }
  return null;
}

/// 记账面板顶部的模板条：最多 3 个 chip，点一下填好整笔。
///
/// **编辑态不显示**（改一笔时套模板只会把用户改了一半的东西冲掉）。
class TemplateStrip extends StatelessWidget {
  const TemplateStrip({
    super.key,
    required this.templates,
    required this.selectedId,
    required this.onPick,
  });

  final List<TxnTemplate> templates;
  final int? selectedId;
  final ValueChanged<TxnTemplate> onPick;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    if (templates.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView(
        key: const ValueKey<String>('template-strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: S.page),
        children: <Widget>[
          for (final TxnTemplate t in templates)
            Padding(
              padding: const EdgeInsets.only(right: S.sm),
              child: GestureDetector(
                key: ValueKey<String>('tpl-chip-${t.id}'),
                onTap: () => onPick(t),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: S.md,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: t.id == selectedId ? pal.accent : pal.surfaceAlt,
                    borderRadius: R.rPill,
                    border: Border.all(
                      color: t.id == selectedId ? pal.accent : pal.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        IconMap.of(t.icon),
                        size: 13,
                        color: t.id == selectedId ? pal.onAccent : pal.ink3,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        t.name,
                        style: Ts.caption.copyWith(
                          color: t.id == selectedId ? pal.onAccent : pal.ink2,
                          fontWeight: t.id == selectedId
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (t.amountCents > 0) ...<Widget>[
                        const SizedBox(width: 4),
                        Text(
                          Fmt.money(t.amountCents, trimZero: true),
                          style: Ts.micro.copyWith(
                            color: t.id == selectedId
                                ? pal.onAccent
                                : pal.ink4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
