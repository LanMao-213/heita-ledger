import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 段落标题：左边一句话，右边可选动作（「全部」「管理」这种）。
///
/// 条件条（筛选态）也复用它：左边标题写「全部历史」，右边「清除」。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(S.page, S.lg, S.page, S.sm),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ts.micro.copyWith(color: pal.ink3),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
