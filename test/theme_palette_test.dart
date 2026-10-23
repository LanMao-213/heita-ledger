import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/tokens.dart';

/// WCAG 相对亮度对比度
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) {
      return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final l1 = lum(a);
  final l2 = lum(b);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('配色可用性（纸墨单套色板）', () {
    test('ThemeData 是亮色的 —— 纸墨不是深色模式', () {
      // 这一条是需求本身：「我们现在做的不是深色模式」。
      // 之前按黑塔阵营基调（暗石底 + 骨白）做过一版，是深色的，已废弃。
      expect(buildAppTheme().brightness, Brightness.light);
      expect(
        C.bg.computeLuminance(),
        greaterThan(0.5),
        reason: '底必须是亮的（纸白），深色模式这条会挂',
      );
      expect(
        C.ink.computeLuminance(),
        lessThan(0.2),
        reason: '主文字必须是暗的',
      );
    });

    test('主文字 / 超支 / 次要 / 辅助文字在底上都看得清', () {
      expect(_contrast(C.ink, C.bg), greaterThan(7), reason: '主文字 AAA');
      expect(_contrast(C.ink2, C.bg), greaterThan(4.5), reason: '次要文字 AA');
      expect(_contrast(C.over, C.bg), greaterThan(4.5), reason: '超支 AA');
      // 辅助文字是 12.5px 的 caption 在用，必须过 AA —— 旧色板这里是 2.6:1，
      // 这一轮已经提到 5.2:1，所以下限写死 4.5（不再是当年的 2.5）。
      expect(_contrast(C.ink3, C.bg), greaterThanOrEqualTo(4.5), reason: '辅助文字 AA');
      expect(_contrast(C.ink3, C.cardBg), greaterThanOrEqualTo(4.5), reason: '卡片上的辅助文字 AA');
    });

    test('进度条填充与轨道的对比度 ≥ 3（图形对象的下限）', () {
      // Bar / LinearProgressIndicator：填充 accent、轨道 handle
      expect(_contrast(C.accent, C.handle), greaterThanOrEqualTo(3));
    });

    test('面与面之间分得开，层级不塌', () {
      // 概览卡「压下去」、明细卡「浮上来」、卡里的胶囊再降一档（D-09）。
      // 任意两档同色，那一层就消失了。
      expect(C.heroBg, isNot(C.cardBg), reason: '概览卡 ≠ 明细卡');
      expect(C.bg2, isNot(C.cardBg), reason: '卡内次级面 ≠ 卡面');
      expect(C.bg2, isNot(C.bg), reason: '输入底 ≠ 页面底');
      // 概览卡与卡内次级面是两个值（几乎同亮度，但不同族，便于各自微调）：
      // 概览卡要读起来是「压下去的纸」，次级面要读起来是「沉下去的槽」。
      expect(C.heroBg, isNot(C.bg2), reason: '概览卡 ≠ 卡内次级面');
      expect(C.heroEdge, isNot(C.line), reason: '概览卡描边与普通描边不同族就没必要拆');
    });
  });

  group('色板的值被钉死', () {
    test('24 个颜色 token 与十档色阶', () {
      // 这组断言的作用是「改色必须是有意识的」：值被顺手改掉时先在这里红。
      //
      // 2026-10-23 整体换板（暖米「纸墨」→ 中性冷灰，对齐 iOS grouped）：
      // 底色 #F5F2EA→#F3F4F7、墨 #1C1A17→#14161A、圆角 20/24/30→14/18/22、
      // 投影全部归零。下面这组期望值是那次换板后的新基线。
      expect(C.ink, const Color(0xFF14161A));
      expect(C.ink2, const Color(0xFF5C626B));
      expect(C.ink3, const Color(0xFF656A75));
      expect(C.ink4, const Color(0xFFBFC4CC));
      expect(C.inkWash, const Color(0x0F14161A));
      expect(C.bg, const Color(0xFFF3F4F7));
      expect(C.bg2, const Color(0xFFE8EAF0));
      expect(C.bg3, const Color(0xFFF6F7FA));
      expect(C.line, const Color(0xFFE2E5EA));
      expect(C.line2, const Color(0xFFCFD4DB));
      expect(C.over, const Color(0xFFB0302A));
      expect(C.overD, const Color(0xFFC0625A));
      expect(C.stage, const Color(0xFFD8DBE1));
      // 强调色 === 主文字色（纸墨原则：不引入装饰色）
      expect(C.accent, C.ink, reason: '强调色 = 主文字色');
      // 压在深色块上的字必须是纯白：纸白 #F5F2EA 压上去会脏，且对比度略低
      expect(C.onAccent, const Color(0xFFFFFFFF));
      // 旧色板里 accentSoft / accentWash / bg2 三个都是 #EFEBE3，互相钉死会掩盖
      // 单值漂移（改一个等于改三个）；这一版三者互不相同，各自钉自己的值。
      expect(C.accentSoft, const Color(0xFFEEF0F4));
      expect(C.accentWash, const Color(0xFFF0F2F5));
      expect(C.todayMark, C.ink);
      expect(C.onTodayMark, const Color(0xFFFFFFFF));
      expect(C.cardShadow, const Color(0x0D14161A));
      expect(C.handle, const Color(0xFFE7EAF0));
      expect(C.heroEdge, const Color(0xFFD8DDE5));
      // 白卡压浅灰底（约 1.13:1），靠明度差分开 —— 不再用投影
      expect(C.cardBg, const Color(0xFFFFFFFF));
      expect(C.heroBg, const Color(0xFFE8EBF1));
      // 图表色阶：中性灰十档，越靠前越主要
      expect(kChart, const [
        Color(0xFF14161A),
        Color(0xFF2E3238),
        Color(0xFF454A52),
        Color(0xFF5C626B),
        Color(0xFF737A84),
        Color(0xFF8B929C),
        Color(0xFFA3AAB4),
        Color(0xFFBBC2CB),
        Color(0xFFD2D8E0),
        Color(0xFFE8ECF2),
      ]);
      expect(kChart.length, 10, reason: '饼图切片按十档循环');
    });
  });
}
