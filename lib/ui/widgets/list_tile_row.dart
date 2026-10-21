import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 通用列表行：左图标圆底 + 标题/副行 + 右尾随。
///
/// 明细行、账户行、模板行都用它，保证行高与留白一致（§6.6：带副行 64、
/// 不带副行 56）。**叶子组件，不订阅任何 Store**。
class ListTileRow extends StatelessWidget {
  const ListTileRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingIcon,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.showDivider = false,
    this.minHeight = S.rowMin,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final IconData? leadingIcon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showDivider;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;

    final Widget left =
        leading ??
        (leadingIcon == null
            ? const SizedBox.shrink()
            : Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: pal.avatarBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(leadingIcon, size: 18, color: pal.ink2),
              ));

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: S.lg,
          vertical: S.sm,
        ),
        decoration: showDivider
            ? BoxDecoration(
                border: Border(bottom: BorderSide(color: pal.line)),
              )
            : null,
        child: Row(
          children: <Widget>[
            left,
            if (left is! SizedBox) const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  title,
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    subtitle!,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: S.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 行标题（明细/账户通用）。
class RowTitle extends StatelessWidget {
  const RowTitle(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Ts.body.copyWith(color: color ?? context.pal.ink),
  );
}
