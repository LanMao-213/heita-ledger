import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 键的类型 —— 只决定长相，不决定行为。
///
/// 视觉分工（这一版重做的核心）：
/// - **数字不铺底色**：12 个灰块排在一起，视觉重量全压在「键」上，金额反而被
///   埋掉；去掉底色后字号能放大，读数更快。
/// - **运算符保留淡底**：÷ × − + 是四个「动作」，需要被一眼定位。
/// - **C / ⌫ 退成浅字**：低频，按错了代价也小，不该和数字抢注意力。
/// - **确认键是唯一的重色块**：它是这一步的终点，竖跨两行做视觉锚点。
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

  Widget _row(
    List<CalcKeySpec> specs,
    double keyW, {
    bool gapAfter = true,
  }) {
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
              child: _KeyCap(
                spec: specs[i],
                onTap: () => onKey(specs[i].key),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个键。样式全部由 [CalcKeySpec.kind] 决定，按压反馈统一在这里做。
///
/// 为什么必须自己做按压态：数字键现在没有底色，不给反馈的话按下去像没反应。
/// 统一点一下「浮出一层淡底」（90ms 淡入淡出）—— 不引入新颜色，也不会像涟漪
/// 那样扩散到隔壁键上。
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

  @override
  Widget build(BuildContext context) {
    final kind = widget.spec.kind;
    final Color bg = switch (kind) {
      // 全键盘统一一条规则：按下 = line（#E8EAEC）。
      // 无底色的键必须「长出」一块看得见的底，否则按了像没反应；
      // 运算符从 bg2 压到 line，是同一条规则的另一半。
      CalcKeyKind.digit => _down ? C.line : Colors.transparent,
      CalcKeyKind.operator => _down ? C.line : C.bg2,
      CalcKeyKind.utility => _down ? C.line : Colors.transparent,
      // 重色块不能靠「变淡」表达按下，会看起来像禁用；往白里提 16%
      CalcKeyKind.confirm => !_enabled
          ? C.bg2
          : (_down ? Color.lerp(C.ink, C.bg, 0.16)! : C.ink),
    };
    final Color fg = switch (kind) {
      CalcKeyKind.digit || CalcKeyKind.operator => C.ink,
      CalcKeyKind.utility => C.ink2,
      CalcKeyKind.confirm => _enabled ? C.bg : C.ink4,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _setDown(true) : null,
      onTapUp: _enabled ? (_) => _setDown(false) : null,
      onTapCancel: _enabled ? () => _setDown(false) : null,
      onTap: widget.onTap,
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
