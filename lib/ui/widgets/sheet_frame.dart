import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 底部面板的**统一外壳**：拖拽条 + 标题 + 关闭 + 圆角顶 + 阴影。
///
/// 所有 `showModalBottomSheet` 的内容都套它，保证圆角、描边、内边距、
/// 关闭按钮位置一致（原版每个面板各写一套，圆角有 12/16/20 三种）。
///
/// 用法：
/// ```dart
/// showModalBottomSheet(isScrollControlled: true, builder: (_) =>
///   SheetFrame(title: '筛选', child: ...));
/// ```
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.maxHeightFactor = 0.9,
    this.padding = const EdgeInsets.fromLTRB(S.page, 0, S.page, S.lg),
  });

  final String title;
  final Widget child;

  /// 标题右侧的额外按钮（「重置」「清除」这类）。
  final Widget? trailing;

  /// 面板最高占屏幕比例（键盘弹起时用 `isScrollControlled` + `AnimatedPadding`）。
  final double maxHeightFactor;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final double maxHeight =
        MediaQuery.sizeOf(context).height * maxHeightFactor;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        boxShadow: Elev.sheet(pal),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: S.sm),
            // 拖拽条：告诉用户「这个面板可以往下甩」
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: pal.lineStrong,
                borderRadius: BorderRadius.circular(R.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.page, S.md, S.sm, S.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.section.copyWith(color: pal.ink),
                    ),
                  ),
                  ?trailing,
                  IconButton(
                    key: const ValueKey<String>('sheet-close'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close, size: 20, color: pal.ink3),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Flexible(child: Padding(padding: padding, child: child)),
          ],
        ),
      ),
    );
  }
}
