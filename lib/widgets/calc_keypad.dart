import 'package:flutter/material.dart';

import '../design/haptics.dart';
import '../design/tokens.dart';

/// 键的类型 —— 只决定长相，不决定行为。
///
/// 视觉规则只有一条：**要么全都铺底，要么全都不铺、用短线段隔开**。
/// 混着来（一半有底一半没有）会让键盘看起来像两套东西拼起来的，也不好看清
/// 哪个键到哪儿为止。这里选「全都铺底」：
/// - 数字 0–9、`.`：`bg2` 淡底 + 23px 数字，点击面一眼可见
/// - ÷ × − +：同样的底，靠字形与字号区分，不另起一套填充
/// - C / ⌫：同样的底，文字退成 `ink2`（低频，不该和数字抢注意力）
/// - 确认键：`ink` 重色块，竖跨两行；禁用态落回 `bg2` + `ink4` 文字
/// - 按下：`bg2` → `line2`（比常态深一档），全键盘同一个动作
enum CalcKeyKind { digit, operator, utility, confirm }

/// 一个键的静态描述。
///
/// 键位表就是数据：加键、换行、跨格只改下面的 `_upper` / `_lower`，
/// 不用碰布局代码。
class CalcKeySpec {
  const CalcKeySpec(this.key, this.kind, {this.span = 1});

  /// 交给 `Calc.press` 的逻辑键（`/`、`*`、`del` 也走这套）
  final String key;

  final CalcKeyKind kind;

  /// 横向占几格（「0」占两格）
  final int span;

  /// 键面文字：`*` `/` 换成真正的数学符号；`del` 画图标（见 [_KeyCap]）
  String get label => switch (key) {
    '*' => '×',
    '/' => '÷',
    _ => key,
  };
}

/// 金额键盘。排列按用户指定：
///
/// ```
///  C    ÷    ×    ⌫
///  7    8    9    -
///  4    5    6    +
///  1    2    3   ┐
///  0 ───────  .  ┘ 确认
/// ```
///
/// 「0」横跨两格，「确认」竖跨两行。没有 `±` 键是刻意的 ——
/// 负数靠在最前面打 `-`（规则见 `data/calc.dart`）。
///
/// 列宽只有一个来源：`keyW = (可用宽 - 3 个缝) / 4`。所有键（含跨格、含确认）
/// 都按它算宽度 —— 之前上下两半各用一套算法，算出 87 / 86 / 90 三种宽度，
/// 「3 / .」偏左、确认比「+」宽，肉眼就能看出来。
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
  /// 最后一排被裁掉一条。
  final double keyHeight;

  static const _gap = 6.0;

  static const _confirmSpec = CalcKeySpec('确认', CalcKeyKind.confirm);

  /// 上面三行，各 4 列
  static const _upper = <List<CalcKeySpec>>[
    [
      CalcKeySpec('C', CalcKeyKind.utility),
      CalcKeySpec('/', CalcKeyKind.operator),
      CalcKeySpec('*', CalcKeyKind.operator),
      CalcKeySpec('del', CalcKeyKind.utility),
    ],
    [
      CalcKeySpec('7', CalcKeyKind.digit),
      CalcKeySpec('8', CalcKeyKind.digit),
      CalcKeySpec('9', CalcKeyKind.digit),
      CalcKeySpec('-', CalcKeyKind.operator),
    ],
    [
      CalcKeySpec('4', CalcKeyKind.digit),
      CalcKeySpec('5', CalcKeyKind.digit),
      CalcKeySpec('6', CalcKeyKind.digit),
      CalcKeySpec('+', CalcKeyKind.operator),
    ],
  ];

  /// 最后两行的左半部分（第 4 列是竖跨两行的确认键）
  static const _lower = <List<CalcKeySpec>>[
    [
      CalcKeySpec('1', CalcKeyKind.digit),
      CalcKeySpec('2', CalcKeyKind.digit),
      CalcKeySpec('3', CalcKeyKind.digit),
    ],
    [
      CalcKeySpec('0', CalcKeyKind.digit, span: 2),
      CalcKeySpec('.', CalcKeyKind.digit),
    ],
  ];

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
              for (final row in _upper) _row(row, keyW),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左三列：宽度 = 3 个键 + 2 个缝，与上面三行严格对齐
                  SizedBox(
                    width: keyW * 3 + _gap * 2,
                    child: Column(
                      children: [
                        for (var i = 0; i < _lower.length; i++)
                          _row(
                            _lower[i],
                            keyW,
                            // 最后一行不留缝：确认键高 2h+g，正好贴齐
                            gapAfter: i < _lower.length - 1,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: _gap),
                  SizedBox(
                    width: keyW,
                    height: _h * 2 + _gap,
                    child: _KeyCap(
                      spec: _confirmSpec,
                      onTap: canConfirm ? onConfirm : null,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(List<CalcKeySpec> specs, double keyW, {bool gapAfter = true}) {
    return Padding(
      padding: EdgeInsets.only(bottom: gapAfter ? _gap : 0),
      child: Row(
        children: [
          for (var i = 0; i < specs.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            SizedBox(
              width: keyW * specs[i].span + _gap * (specs[i].span - 1),
              // 高度必须显式给：Row 里高度是无界的，只给宽度的话键会缩成
              // 一行字的高（33 而不是 46），确认块还会比左边两行高出一截
              height: _h,
              child: _KeyCap(spec: specs[i], onTap: () => onKey(specs[i].key)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个键。样式全部由 [CalcKeySpec.kind] 决定，按压反馈统一在这里做。
///
/// 填充色只有两种来源：`bg2`（所有普通键的常态）与 `ink`（确认键）。
/// 不为某个 kind 单独开一套填充 —— 半有底半没底会让键盘看起来是拼的。
class _KeyCap extends StatefulWidget {
  const _KeyCap({required this.spec, required this.onTap});

  final CalcKeySpec spec;

  /// null = 当前不可按（金额还不合法时的确认键）
  final VoidCallback? onTap;

  @override
  State<_KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<_KeyCap> {
  bool _down = false;

  bool get _enabled => widget.onTap != null;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  /// 只有确认键震：数字键一次记账要按十几下，每下都震反而吵
  void _handleTap() {
    if (widget.spec.kind == CalcKeyKind.confirm) Haptics.key();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.spec.kind;
    final Color bg = switch (kind) {
      // 普通键只有一种常态：bg2。按下统一压到 line2（深一档），
      // 不再出现「有底的按下去变深、没底的按下去才长出底」两套规则。
      CalcKeyKind.digit ||
      CalcKeyKind.operator ||
      CalcKeyKind.utility => _down ? C.line2 : C.bg2,
      // 重色块不能靠「变淡」表达按下，会看起来像禁用；往白里提 16%
      CalcKeyKind.confirm =>
        !_enabled ? C.bg2 : (_down ? Color.lerp(C.ink, C.bg, 0.16)! : C.ink),
    };
    final Color fg = switch (kind) {
      // 数字与运算符同色，靠字号区分（23 / 21）；运算符再压一档会显得「不可用」
      CalcKeyKind.digit || CalcKeyKind.operator => C.ink,
      CalcKeyKind.utility => C.ink2,
      CalcKeyKind.confirm => _enabled ? C.bg : C.ink4,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _setDown(true) : null,
      onTapUp: _enabled ? (_) => _setDown(false) : null,
      onTapCancel: _enabled ? () => _setDown(false) : null,
      onTap: _enabled ? _handleTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: _content(fg),
      ),
    );
  }

  Widget _content(Color fg) {
    final spec = widget.spec;
    if (spec.key == 'del') {
      return Icon(Icons.backspace_outlined, size: 20, color: fg);
    }
    final (size, weight) = switch (spec.kind) {
      CalcKeyKind.digit => (23.0, FontWeight.w500),
      CalcKeyKind.operator => (21.0, FontWeight.w500),
      CalcKeyKind.utility => (17.0, FontWeight.w500),
      CalcKeyKind.confirm => (16.0, FontWeight.w600),
    };
    return Text(
      spec.label,
      style: TextStyle(fontSize: size, fontWeight: weight, color: fg),
    );
  }
}
