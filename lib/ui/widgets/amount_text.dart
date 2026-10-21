import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

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
    this.yuan = false,
    this.trimZero = false,
  });

  final int cents;

  /// 正数加 `+`（收入/借入用）。
  final bool sign;

  final Color? color;
  final TextStyle? style;

  /// 前面带 `¥`。
  final bool yuan;

  /// 整数不带 `.00`（副行金额用）。
  final bool trimZero;

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
      style: (style ?? Ts.amount).copyWith(color: color ?? pal.ink),
    );
  }
}
