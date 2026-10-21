import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 二次确认弹窗。返回 `true` = 用户确认。
///
/// 危险操作用 `destructive`（确认键是 `over` 色）；正文支持多行
/// （删除确认要写「分类名 · ±金额」+ 备注换行）。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmText = '确定',
  String cancelText = '取消',
  bool destructive = false,
}) async {
  final AppPalette pal = context.pal;
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        backgroundColor: pal.surface,
        surfaceTintColor: pal.surface,
        shape: const RoundedRectangleBorder(borderRadius: R.rCard),
        title: Text(title, style: Ts.section.copyWith(color: pal.ink)),
        content: Text(
          body,
          style: Ts.body2.copyWith(color: pal.ink2, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('confirm-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              cancelText,
              style: Ts.body.copyWith(color: pal.ink2),
            ),
          ),
          TextButton(
            key: const ValueKey<String>('confirm-ok'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmText,
              style: Ts.body.copyWith(
                color: destructive ? pal.over : pal.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
