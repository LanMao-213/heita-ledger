import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 金额键盘。排列按用户指定：
///
/// ```
///  C    ÷    ×    ⌫
///  7    8    9    −
///  4    5    6    +
///  1    2    3   ┐
///  0 ───────  .  ┘ 确认
/// ```
///
/// 「0」横跨两格，「确认」竖跨两行。没有 `±` 键是刻意的 ——
/// 负数靠在最前面打 `-`（规则见 `data/calc.dart`）。
class CalcKeypad extends StatelessWidget {
  const CalcKeypad({
    super.key,
    required this.onKey,
    required this.onConfirm,
    required this.canConfirm,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onConfirm;
  final bool canConfirm;

  static const _gap = 6.0;
  static const _h = 46.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row([_key('C', weak: true), _key('/', op: true), _key('*', op: true), _key('del', weak: true)]),
          _row([_key('7'), _key('8'), _key('9'), _key('-', op: true)]),
          _row([_key('4'), _key('5'), _key('6'), _key('+', op: true)]),
          _bottomRows(),
        ],
      ),
    );
  }

  Widget _row(List<Widget> keys) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(child: keys[i]),
          ],
        ],
      ),
    );
  }

  /// 最后两行：左 3/4 是 `1 2 3` + `0(两格) .`，右侧 1/4 是竖跨两行的确认
  Widget _bottomRows() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _row([_key('1'), _key('2'), _key('3')]),
              Row(
                children: [
                  Expanded(flex: 2, child: _key('0')),
                  const SizedBox(width: _gap),
                  Expanded(child: _key('.')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(child: _confirm()),
      ],
    );
  }

  Widget _key(String label, {bool op = false, bool weak = false}) {
    final text = switch (label) {
      '*' => '×',
      '/' => '÷',
      // 连字符保持 ASCII：U+2212（−）在部分中文字体里没有字形，会渲染成空白
      'del' => '',
      _ => label,
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onKey(label),
      child: Container(
        height: _h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: op ? C.bg3 : C.bg2,
          borderRadius: BorderRadius.circular(R.md),
          border: op ? Border.all(color: C.line) : null,
        ),
        child: label == 'del'
            ? const Icon(Icons.backspace_outlined, size: 19, color: C.ink2)
            : Text(
                text,
                style: TextStyle(
                  fontSize: weak ? 16 : 20,
                  fontWeight: FontWeight.w500,
                  color: weak ? C.ink2 : C.ink,
                ),
              ),
      ),
    );
  }

  Widget _confirm() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canConfirm ? onConfirm : null,
      child: Container(
        height: _h * 2 + _gap,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: canConfirm ? C.ink : C.bg2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Text(
          '确认',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: canConfirm ? C.bg : C.ink4,
          ),
        ),
      ),
    );
  }
}
