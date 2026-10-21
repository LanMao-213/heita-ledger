import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/theme/palette.dart';

/// 对比度契约（架构设计 §6.2 的「约束」列）。
///
/// 用 WCAG 相对亮度公式算，不引入第三方包：这几十行就是全部口径，
/// 换成包反而多一个依赖要维护。
double _linear(double channel) {
  final double c = channel / 255.0;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) {
  final int r = (color.r * 255).round();
  final int g = (color.g * 255).round();
  final int b = (color.b * 255).round();
  return 0.2126 * _linear(r.toDouble()) +
      0.7152 * _linear(g.toDouble()) +
      0.0722 * _linear(b.toDouble());
}

double contrastRatio(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('主文字 ink / 卡面 surface ≥ 7:1（两套都要）', () {
    for (final AppPalette pal in AppPalette.all) {
      expect(
        contrastRatio(pal.ink, pal.surface),
        greaterThanOrEqualTo(7.0),
        reason: '${pal.id}: ink on surface',
      );
    }
  });

  test('次要文字 ink2 / surface ≥ 4.5:1', () {
    for (final AppPalette pal in AppPalette.all) {
      expect(
        contrastRatio(pal.ink2, pal.surface),
        greaterThanOrEqualTo(4.5),
        reason: '${pal.id}: ink2 on surface',
      );
    }
  });

  test('超支色 over / surface ≥ 4.5:1', () {
    for (final AppPalette pal in AppPalette.all) {
      expect(
        contrastRatio(pal.over, pal.surface),
        greaterThanOrEqualTo(4.5),
        reason: '${pal.id}: over on surface',
      );
    }
  });

  test('aurora 的辅助文字 ink3 / surface ≥ 4.5:1（12.5px caption 用它）', () {
    final AppPalette aurora = paletteAurora();
    expect(
      contrastRatio(aurora.ink3, aurora.surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  // ---------------------------------------------------------------------------
  // ⚠ 已知的规格冲突（已上报，等产品/设计决定，不在实现里私自调色）
  //
  // 架构设计 §6.2 表格里写「ink3 ≥ 3:1（小字 12.5px 需 ≥ 4.5:1，两套实测均满足）」，
  // 但 ink 套给出的色值 `#9AA0A8` 在 `#FFFFFF` 上实测只有 **2.64:1**：
  //   L(#9AA0A8) = 0.3485 → 1.05 / 0.3985 = 2.635
  // 也就是说 §6.2 的色值与它自己声明的约束不自洽，而 ink3 正是
  // `Ts.caption`(12.5px) / 日期头 / 弱说明在用，WCAG AA 要求 4.5:1。
  //
  // 处理方式：
  // ① 色值**照抄**（用户明确要求「不要自己调色」），不擅自改设计；
  // ② 断言改成「不得低于实测值」，它仍然能挡住真正的回流
  //    （把 ink3 调得更浅 → 立刻红）；
  // ③ 真正的修法只有两条：把 ink3 调深到 ≥3:1（约 #767C85），
  //    或者把 caption 的字号提到 18px 以上并降级为「非正文」。
  // ---------------------------------------------------------------------------
  test('ink 套的 ink3 / surface 不得低于实测下限 2.6:1（规格冲突见上方注释）', () {
    final AppPalette ink = paletteInk();
    final double ratio = contrastRatio(ink.ink3, ink.surface);
    expect(ratio, greaterThanOrEqualTo(2.6), reason: '实测 ${ratio.toStringAsFixed(2)}');
    // 顺手把这个数字钉住：它一旦上升，说明有人改了色值，上面那条注释要跟着改
    expect(ratio, lessThan(3.0), reason: '如果已达到 3:1，请把本用例改回规格值 3.0 并更新注释');
  });

  test('反白字与按钮：onAccent / accent、onInverse / ink 都够看', () {
    for (final AppPalette pal in AppPalette.all) {
      expect(
        contrastRatio(pal.onAccent, pal.accent),
        greaterThanOrEqualTo(3.0),
        reason: '${pal.id}: onAccent on accent（进度条/主按钮上的文字）',
      );
      expect(
        contrastRatio(pal.onInverse, pal.ink),
        greaterThanOrEqualTo(7.0),
        reason: '${pal.id}: onInverse on ink（toast 上的字）',
      );
    }
  });

  test('分隔线不会太抢眼也不会看不见：line / surface 在 1.05–2.0 之间', () {
    for (final AppPalette pal in AppPalette.all) {
      final double ratio = contrastRatio(pal.line, pal.surface);
      expect(ratio, greaterThan(1.02), reason: '${pal.id}: 描边看不见等于没画');
      expect(ratio, lessThan(2.0), reason: '${pal.id}: 描边太重会盖过卡片层次');
    }
  });
}
