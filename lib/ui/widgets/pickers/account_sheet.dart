import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../list_tile_row.dart';
import '../sheet_frame.dart';

/// 选账户的底部面板。返回账户 id；取消返回 `null`。
///
/// 只在记录面板里用（转出/转入两个位置各一次）。没有账户时显示引导文案而不是
/// 空列表 —— 空列表会让用户以为「这里坏了」。
Future<int?> showAccountSheet(
  BuildContext context, {
  required List<Account> accounts,
  int? selectedId,
  String? title,
  bool allowNone = false,
}) {
  return showModalBottomSheet<int?>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      final AppPalette pal = ctx.pal;
      return SheetFrame(
        title: title ?? '选择账户',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (allowNone)
                ListTileRow(
                  title: const RowTitle('不指定账户'),
                  leadingIcon: Icons.remove_circle_outline,
                  onTap: () => Navigator.of(ctx).pop(-1),
                  showDivider: true,
                ),
              if (accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.xl),
                  child: Text(
                    '还没有账户。到「我的 → 账户管理」里加一个，记账时才能算余额。',
                    style: Ts.body2.copyWith(color: pal.ink3),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final Account a in accounts)
                ListTileRow(
                  title: RowTitle(a.name),
                  subtitle: Text(
                    '${a.kind.label} · ${Fmt.yuan(a.balanceCents)}',
                    style: Ts.caption.copyWith(color: pal.ink3),
                  ),
                  leadingIcon: Icons.account_balance_wallet_outlined,
                  onTap: () => Navigator.of(ctx).pop(a.id),
                  trailing: a.id == selectedId
                      ? Icon(Icons.check, size: 18, color: pal.navActive)
                      : null,
                  showDivider: true,
                ),
            ],
          ),
        ),
      );
    },
  );
}
