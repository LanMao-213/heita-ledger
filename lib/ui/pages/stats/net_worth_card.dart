import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';

/// 账户资产卡：**Σ 余额（只算计入净资产的账户）**。
///
/// 与「净资产」的区别：净资产还要 + 应收 − 应付。这里只回答
/// 「我账户里躺着多少」，把往来摘出去 —— 两句话混在一张卡里最容易读错。
class NetWorthCard extends StatelessWidget {
  const NetWorthCard({
    super.key,
    required this.assetsCents,
    this.accountsCount = 0,
    this.onTap,
  });

  final int assetsCents;

  /// 计入的账户数（0 时副行改成「还没有账户」而不是「0 个账户」）。
  final int accountsCount;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.account_balance_wallet_outlined, size: 14, color: pal.ink3),
            const SizedBox(width: 6),
            Text(
              '账户资产',
              style: Ts.caption.copyWith(color: pal.ink2),
            ),
            const Spacer(),
            Text(
              accountsCount > 0 ? '$accountsCount 个账户' : '还没有账户',
              style: Ts.micro.copyWith(color: pal.ink4),
            ),
          ],
        ),
        const SizedBox(height: S.sm),
        AmountText(
          key: const ValueKey<String>('net-assets'),
          cents: assetsCents,
          yuan: true,
          tier: AmountTier.heroSm,
        ),
        const SizedBox(height: 2),
        Text(
          '只算「计入净资产」的账户，不含应收应付',
          style: Ts.micro.copyWith(color: pal.ink4),
        ),
      ],
    );
    return Material(
      color: pal.surface,
      borderRadius: R.rCard,
      child: InkWell(
        onTap: onTap,
        borderRadius: R.rCard,
        child: Padding(
          padding: const EdgeInsets.all(S.card),
          child: body,
        ),
      ),
    );
  }
}
