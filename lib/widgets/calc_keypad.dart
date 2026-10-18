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
///
/// 整张键盘只有**一种列宽**：4 等分的 `keyW`。
/// 之前的写法是上面 4 个 `Expanded`、下面左右 `flex: 3 / 1`，两边算出来的宽度
/// 并不相等（366 的可用宽度下：键 87、底排 86、确认 90），于是「3 / .」比
/// 「9 / 6」偏左几像素、确认键比「+」宽一截 —— 一眼就能看出来。
class CalcKeypad extends StatelessWidget {
  const CalcKeypad({
    super.key,
    required this.onKey,
    required this.onConfirm,
    required this.canConfirm,
    this.keyHeight = 46,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onConfirm;
  final bool canConfirm;

  /// 单个键的高度。面板按屏幕高度算好再传进来 —— 小屏机型上固定 46 会让
  /// 最后一排（0 / . / 确认）被裁掉一条，那正是「键盘尺寸有问题」的真身。
  final double keyHeight;

  static const _gap = 6.0;

  double get _h => keyHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.md),
      child: LayoutBuilder(
        builder: (context, box) {
          final keyW = (box.maxWidth - _gap * 3) / 4;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _line(keyW, [
                _key('C', weak: true),
                _key('/', op: true),
                _key('*', op: true),
                _key('del', weak: true),
              ]),
              _line(keyW, [
                _key('7'),
                _key('8'),
                _key('9'),
                _key('-', op: true),
              ]),
              _line(keyW, [
                _key('4'),
                _key('5'),
                _key('6'),
                _key('+', op: true),
              ]),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左三列的宽度 = 3 个键 + 2 个缝，正好和上面三行对齐
                  SizedBox(
                    width: keyW * 3 + _gap * 2,
                    child: Column(
                      children: [
                        _line(keyW, [_key('1'), _key('2'), _key('3')]),
                        Row(
                          children: [
                            // 「0」占第 1–2 列：两键 + 中间那个缝
                            SizedBox(
                              width: keyW * 2 + _gap,
                              child: _key('0'),
                            ),
                            const SizedBox(width: _gap),
                            SizedBox(width: keyW, child: _key('.')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: _gap),
                  // 确认键就是第 4 列，宽度与其它键一致，竖跨最后两行
                  SizedBox(
                    width: keyW,
                    height: _h * 2 + _gap,
                    child: _confirm(),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// 一行按键，每个都是固定宽度 —— 不用 Expanded，避免和下面三列的算法打架
  Widget _line(double keyW, List<Widget> keys) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            SizedBox(width: keyW, child: keys[i]),
          ],
        ],
      ),
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
