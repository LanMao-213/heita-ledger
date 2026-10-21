import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// 记一笔的数字键盘。
///
/// 布局（4 列 × 5 行，**没有 ± 键** —— `-` 在行首就是负号，这是用户定的）：
/// ```
///   7   8   9  | ÷
///   4   5   6  | ×
///   1   2   3  | −
///   .   0  (跨两格)     确认（竖跨两行）
///   C  ⌫   +
/// ```
///
/// 键高随「详情区是否展开」在 [minKeyHeight]–[maxKeyHeight] 之间 clamp：
/// 详情区一展开就把键盘压扁，但不小于 38（再小点不准）。
class RecordKeypad extends StatelessWidget {
  const RecordKeypad({
    super.key,
    required this.onKey,
    required this.onConfirm,
    required this.canConfirm,
    this.expanded = false,
    this.confirmLabel = '确认',
  });

  final ValueChanged<String> onKey;
  final VoidCallback onConfirm;

  /// 表达式合法（已输完、非空、除零无效）时才允许确认。
  final bool canConfirm;

  /// 详情区展开时把键压到下限。
  final bool expanded;

  final String confirmLabel;

  static const double minKeyHeight = 38;
  static const double maxKeyHeight = 56;

  /// 键高（几何断言直接读它）。
  static double keyHeight({required bool expanded}) =>
      expanded ? minKeyHeight : maxKeyHeight;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final double h = keyHeight(expanded: expanded);

    Widget key(
      String label,
      String keyId, {
      int flex = 1,
      bool accent = false,
      bool muted = false,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: accent ? pal.accent : pal.surfaceAlt,
            borderRadius: R.rSm,
            child: InkWell(
              key: ValueKey<String>('key-$keyId'),
              borderRadius: R.rSm,
              onTap: () => onKey(keyId),
              child: SizedBox(
                height: h,
                child: Center(
                  child: Text(
                    label,
                    style: Ts.section.copyWith(
                      color: accent
                          ? pal.onAccent
                          : (muted ? pal.ink3 : pal.ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget opKey(String label, String keyId) => key(label, keyId, muted: true);

    // 左 3 列 × 5 行；右列 4 个运算符 + 竖跨两行的确认键。
    //
    // 两列都是**定高**的（键高 h + 上下各 3 的间隙），不用竖向 Expanded：
    // 这个键盘会被放进底部面板的 Column 里，那里高度是无界的，
    // `Expanded` 会直接撞 "non-zero flex but incoming height constraints are unbounded"。
    final Widget digits = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(children: <Widget>[key('7', '7'), key('8', '8'), key('9', '9')]),
        Row(children: <Widget>[key('4', '4'), key('5', '5'), key('6', '6')]),
        Row(children: <Widget>[key('1', '1'), key('2', '2'), key('3', '3')]),
        Row(
          children: <Widget>[
            key('.', '.'),
            key('0', '0', flex: 2),
          ],
        ),
        Row(
          children: <Widget>[
            opKey('C', 'C'),
            opKey('⌫', 'del'),
            opKey('+', '+'),
          ],
        ),
      ],
    );

    final Widget ops = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(children: <Widget>[opKey('÷', '/')]),
        Row(children: <Widget>[opKey('×', '*')]),
        Row(children: <Widget>[opKey('−', '-')]),
        // 确认键竖跨最后两行：内容高 = 两个键高 + 中间那道 6 的间隙
        Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: canConfirm ? pal.accent : pal.surfaceAlt,
            borderRadius: R.rSm,
            child: InkWell(
              key: const ValueKey<String>('key-confirm'),
              borderRadius: R.rSm,
              onTap: canConfirm ? onConfirm : null,
              child: SizedBox(
                height: 2 * h + 6,
                child: Center(
                  child: Text(
                    confirmLabel,
                    style: Ts.section.copyWith(
                      color: canConfirm ? pal.onAccent : pal.ink4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 3, child: digits),
          Expanded(flex: 1, child: ops),
        ],
      ),
    );
  }
}

/// 键盘上的键 id（测试与 UI 共用一份，避免字符串写错）。
abstract final class KeypadKeys {
  static const List<String> digits = <String>[
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  ];
  static const String dot = '.';
  static const String plus = '+';
  static const String minus = '-';
  static const String times = '*';
  static const String divide = '/';
  static const String clear = 'C';
  static const String backspace = 'del';

  /// 全部可点的键（**不含 ±**：负号靠行首 `-` 表达）。
  static const List<String> all = <String>[
    '7', '8', '9', '/', '4', '5', '6', '*', '1', '2', '3', '-',
    '.', '0', 'C', 'del', '+',
  ];
}
