import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'empty_state.dart';

/// 一档「即将上线」的能力说明。
class RoadmapItem {
  const RoadmapItem({
    required this.stage,
    required this.title,
    required this.detail,
  });

  /// 落在哪个任务号（`T02-2` 这种），方便对照任务列表。
  final String stage;

  final String title;
  final String detail;
}

/// **阶段 0 的占位页渲染器**：空态 + 该页后续阶段要做的事。
///
/// 它存在的唯一目的是让骨架期的四个页面「有内容可滚」——
/// 一方面 `shell_test` 要断言「切走再回来滚动位置不变」（`KeepAlive` 生效），
/// 没有可滚内容就无法断言；另一方面打开 App 的人能一眼看到这页将来是什么。
///
/// **真实页面落地后（阶段 2–5）本文件随之删除**，不要往里加业务逻辑。
class RoadmapList extends StatelessWidget {
  const RoadmapList({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.items,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String hint;
  final List<RoadmapItem> items;

  /// 空态上方的额外内容（「我的」页用它放配色切换）。
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.page, S.lg, S.page, S.xxxl),
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          const SizedBox(height: S.xl),
        ],
        SizedBox(
          height: 220,
          child: EmptyState(icon: icon, title: title, hint: hint),
        ),
        const SizedBox(height: S.xl),
        Text('后续阶段落地', style: Ts.micro.copyWith(color: pal.ink3)),
        const SizedBox(height: S.sm),
        for (final RoadmapItem item in items) _RoadmapRow(item: item),
      ],
    );
  }
}

class _RoadmapRow extends StatelessWidget {
  const _RoadmapRow({required this.item});

  final RoadmapItem item;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: S.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: S.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: pal.surfaceAlt,
              borderRadius: R.rSm,
            ),
            child: Text(
              item.stage,
              style: Ts.badge.copyWith(color: pal.ink3),
            ),
          ),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.title, style: Ts.body.copyWith(color: pal.ink)),
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  style: Ts.caption.copyWith(color: pal.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
