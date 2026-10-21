import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 空态：图标圆底 + 标题 + 一句 hint，可选一个动作按钮。
///
/// 规范（架构设计 §6.6）：圆底 64、图标 28、标题 `section`、hint `body2`（`ink3`），
/// 垂直居中于可视区。空态文案一律由调用方给 —— 「还没有数据」这种话在不同页面
/// 有不同的补法（去记一笔 / 换个区间 / 去新建），统一文案等于什么也没说。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: pal.avatarBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: pal.ink3),
            ),
            const SizedBox(height: S.lg),
            Text(
              title,
              style: Ts.section.copyWith(color: pal.ink),
              textAlign: TextAlign.center,
            ),
            if (hint != null && hint!.isNotEmpty) ...<Widget>[
              const SizedBox(height: S.sm),
              Text(
                hint!,
                style: Ts.body2.copyWith(color: pal.ink3),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: S.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
