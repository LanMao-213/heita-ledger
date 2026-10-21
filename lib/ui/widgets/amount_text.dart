import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 金额的字号档位。**金额只有这几档**，不许各处 `fontSize:`。
///
/// - [hero]：页面主数字（净资产、可用额度）
/// - [heroSm]：卡片主数字（预算卡大数字、目标已存）
/// - [normal]：列表行金额
/// - [small]：副行/图例金额
enum AmountTier { hero, heroSm, normal, small }

/// 金额文本：**唯一的金额渲染入口**。
///
/// 三条规矩：
/// 1. 必须走 [Fmt.money]（千分位），不许各处自己拼；
/// 2. 必须用 [Ts.amount]/[Ts.amountSm]（等宽数字），否则逐行小数点会左右跳；
/// 3. 颜色由调用方给（借贷行是 `ink3` 中性灰，不是红也不是黑）。
class AmountText extends StatelessWidget {
  const AmountText({
    super.key,
    required this.cents,
    this.sign = false,
    this.color,
    this.style,
    this.tier = AmountTier.normal,
    this.yuan = false,
    this.trimZero = false,
  });

  final int cents;

  /// 正数加 `+`（收入/借入用）。
  final bool sign;

  final Color? color;
  final TextStyle? style;

  /// 字号档（见 [AmountTier]）。给了 [style] 时以 [style] 为准。
  final AmountTier tier;

  /// 前面带 `¥`。
  final bool yuan;

  /// 整数不带 `.00`（副行金额用）。
  final bool trimZero;

  /// 档位 → 字体（等宽数字都在 [Ts] 里定义）。
  static TextStyle styleOf(AmountTier tier) {
    switch (tier) {
      case AmountTier.hero:
        return Ts.hero;
      case AmountTier.heroSm:
        return Ts.heroSm;
      case AmountTier.normal:
        return Ts.amount;
      case AmountTier.small:
        return Ts.amountSm;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String text = yuan
        ? Fmt.yuan(cents, sign: sign)
        : Fmt.money(cents, sign: sign, trimZero: trimZero);
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: (style ?? styleOf(tier)).copyWith(color: color ?? pal.ink),
    );
  }
}
