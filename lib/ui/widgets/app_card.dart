import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';

/// 通用卡片：白面 + 1px 描边 + 可选轻阴影。
///
/// 阴影策略「描边优先、阴影次之」（§6.4）：卡片默认带描边，只有需要抬起来的
/// （概览卡、浮层）才加 [shadow]。同屏阴影不超过 2 层。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.card),
    this.color,
    this.radius = R.card,
    this.onTap,
    this.onLongPress,
    this.shadow = false,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool shadow;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final Color base = color ?? pal.surface;
    final BorderRadius shape = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: shape,
        border: border ? Border.all(color: pal.line) : null,
        boxShadow: shadow ? Elev.card(pal) : null,
      ),
      child: Material(
        color: base,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
