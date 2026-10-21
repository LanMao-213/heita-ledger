import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 单行 toast。
///
/// **必须**先 `clearSnackBars()`：连续两次操作（例如「已补记 3 笔」紧接着
/// 「分类已升级」）如果不清理，第二条会排在前一条后面等 4 秒，用户以为没生效。
/// 启动时的一次性提示也因此被要求合并成一句（架构设计 §4-② 触发点说明）。
///
/// 颜色全部来自 [AppPalette]：底色用 `ink`（反白 toast），错误态用 `over`。
void showToast(BuildContext context, String message, {bool error = false}) {
  if (message.trim().isEmpty) return;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final AppPalette pal = context.pal;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: Ts.body2.copyWith(color: pal.onInverse),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: error ? pal.over : pal.ink,
        margin: const EdgeInsets.all(S.lg),
        padding: const EdgeInsets.symmetric(
          horizontal: S.lg,
          vertical: S.md,
        ),
        duration: const Duration(milliseconds: 2200),
        shape: const RoundedRectangleBorder(borderRadius: R.rMd),
      ),
    );
}
