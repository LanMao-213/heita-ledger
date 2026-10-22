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
      // 纸墨版把概览卡和卡内次级面拆成了两个值（旧色板两者都是 #F4F5F6）：
      // 概览卡要读起来是「压下去的纸」，次级面要读起来是「沉下去的槽」。
      expect(C.heroBg, isNot(C.bg2), reason: '概览卡 ≠ 卡内次级面');
      expect(C.heroEdge, isNot(C.line), reason: '概览卡描边与普通描边不同族就没必要拆');
    });
  });

  group('纸墨色板的值被钉死', () {
    test('24 个颜色 token 与十档色阶', () {
      // 换单套色板时把「两套三元表达式」换成了字面量。这组断言是那句话的证据：
      // 只要有一个值被顺手改掉，肉眼看不见的那点色差会在这里先红。
      expect(C.ink, const Color(0xFF1C1A17));
      expect(C.ink2, const Color(0xFF5C5850));
      expect(C.ink3, const Color(0xFF6F695C));
      expect(C.ink4, const Color(0xFFB9B2A5));
      expect(C.inkWash, const Color(0x0F1C1A17));
      expect(C.bg, const Color(0xFFFBFAF7));
      expect(C.bg2, const Color(0xFFEFEBE3));
      expect(C.bg3, const Color(0xFFF7F5F0));
      expect(C.line, const Color(0xFFE6E2DA));
      expect(C.line2, const Color(0xFFDBD5C9));
      expect(C.over, const Color(0xFFA6321F));
      expect(C.overD, const Color(0xFFC4472F));
      expect(C.stage, const Color(0xFFE8E5DD));
      // 强调色 === 主文字色（纸墨原则：不引入装饰色）
      expect(C.accent, C.ink, reason: '强调色 = 主文字色');
      // 压在深色块上的字必须是纯白：纸白 #FBFAF7 压上去会脏，且对比度略低
      expect(C.onAccent, const Color(0xFFFFFFFF));
      expect(C.accentSoft, C.bg2, reason: '选中胶囊底与卡内次级面同一档');
      expect(C.accentWash, C.bg2);
      expect(C.todayMark, C.ink);
      expect(C.onTodayMark, const Color(0xFFFFFFFF));
      expect(C.cardShadow, const Color(0x0A1C1A17));
      expect(C.handle, const Color(0xFFE9E4DA));
      expect(C.heroEdge, const Color(0xFFE3DED4));
      // 白卡压纸白底，靠描边 + 投影分开（D-10）
      expect(C.cardBg, const Color(0xFFFFFFFF));
      expect(C.heroBg, const Color(0xFFF3F1EC));
      // 图表色阶：暖灰十档，越靠前越主要
      expect(kChart, const [
        Color(0xFF1C1A17),
        Color(0xFF332F29),
        Color(0xFF4A453C),
        Color(0xFF605A4F),
        Color(0xFF766F62),
        Color(0xFF8C8477),
        Color(0xFFA29A8C),
        Color(0xFFB8B0A2),
        Color(0xFFCFC7B9),
        Color(0xFFE4DED2),
      ]);
      expect(kChart.length, 10, reason: '饼图切片按十档循环');
    });
  });
}
