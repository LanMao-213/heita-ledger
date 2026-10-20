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
  group('配色可用性（两套主题共用这一组断言）', () {
    test('ThemeData 是亮色的 —— 露露缇雅版不是深色模式', () {
      // 这一条是需求本身：「我们现在做的不是深色模式」。
      // 之前按黑塔阵营基调（暗石底 + 骨白）做过一版，是深色的，已废弃。
      expect(buildAppTheme().brightness, Brightness.light);
      expect(
        C.bg.computeLuminance(),
        greaterThan(0.5),
        reason: '底必须是亮的（明亮天空），深色模式这条会挂',
      );
      expect(
        C.ink.computeLuminance(),
        lessThan(0.2),
        reason: '主文字必须是暗的',
      );
    });

    test('主文字 / 超支 / 辅助文字在底上都看得清', () {
      expect(_contrast(C.ink, C.bg), greaterThan(7), reason: '主文字 AAA');
      expect(_contrast(C.ink2, C.bg), greaterThan(4.5), reason: '次要文字 AA');
      expect(_contrast(C.over, C.bg), greaterThan(4.5), reason: '超支 AA');
      // 辅助文字只要求 2.5：默认主题的 `C.ink3` 是 #9AA0A8，在白底上只有
      // 2.6:1 —— 那是既有问题，这一轮不动（改了就不是「保留现在版本」了）。
      // 露露缇雅版的 ink3 是 5.1:1，所以这条对它是白送的。
      expect(_contrast(C.ink3, C.bg), greaterThan(2.5), reason: '辅助文字（既有下限）');
    });

    test('进度条填充与轨道的对比度 ≥ 3（图形对象的下限）', () {
      // Bar / LinearProgressIndicator：填充 accent、轨道 handle
      expect(_contrast(C.accent, C.handle), greaterThanOrEqualTo(3));
    });

    test('面与面之间分得开，层级不塌', () {
      // 概览卡「压下去」、明细卡「浮上来」、卡里的胶囊再降一档（D-09）。
      // 任意两档同色，那一层就消失了 —— 露露缇雅版最容易踩的是
      // 「卡片面用暖白、卡内的未选中态也用暖白」，整片可点区域会看不见。
      //
      // 注意：卡片面 **可以** 等于底色（默认主题就是白卡压在白底上，靠描边
      // 和 4% 投影分开，见 D-10），所以这里不比较 bg 与 cardBg。
      expect(C.heroBg, isNot(C.cardBg), reason: '概览卡 ≠ 明细卡');
      expect(C.bg2, isNot(C.cardBg), reason: '卡内次级面 ≠ 卡面');
      expect(C.bg2, isNot(C.bg), reason: '输入底 ≠ 页面底');
      // 不比较 heroBg 与 bg2：默认主题里它们本来就都是 #F4F5F6
      // （概览卡就是「浅灰底的那块」），强行拆开等于改掉现有设计。
    });
  });

  group('默认包的颜色一个都没变', () {
    test('15 个 token 还是 1.4.4 的那 15 个值', () {
      if (kHeita) return;
      // 加第二套配色时，把「写死的字面量」换成了 token。这组断言就是那句话的
      // 证据：只要有一个值被顺手改掉，`git diff` 里看不见的那点色差就会在这里爆。
      expect(C.ink, const Color(0xFF14161A));
      expect(C.ink2, const Color(0xFF5C626B));
      expect(C.ink3, const Color(0xFF9AA0A8));
      expect(C.ink4, const Color(0xFFC4C9CF));
      expect(C.inkWash, const Color(0x0F14161A));
      expect(C.bg, const Color(0xFFFFFFFF));
      expect(C.bg2, const Color(0xFFF4F5F6));
      expect(C.bg3, const Color(0xFFFAFAFB));
      expect(C.line, const Color(0xFFE8EAEC));
      expect(C.line2, const Color(0xFFDFE2E5));
      expect(C.over, const Color(0xFFA3231A));
      expect(C.overD, const Color(0xFFE8493A));
      expect(C.stage, const Color(0xFFE8EAEF));
      // 新增 token 在默认主题下必须**等于某个旧值**，否则就是新设计
      expect(C.accent, C.ink, reason: '黑白灰原则：强调色 = 主文字色');
      expect(C.onAccent, C.bg);
      expect(C.cardBg, C.bg, reason: '白卡压白底，靠描边 + 投影分开（D-10）');
      expect(C.heroBg, C.bg2);
      expect(C.heroEdge, C.line);
      expect(C.handle, const Color(0xFFEEF0F2));
      expect(C.cardShadow, const Color(0x0A14161A));
      expect(C.accentSoft, C.bg2);
      expect(C.accentWash, C.bg2);
      expect(C.todayMark, C.ink);
      expect(C.onTodayMark, C.bg);
      // 图表色阶保持十档灰
      expect(kChart, const [
        Color(0xFF14161A),
        Color(0xFF2E343C),
        Color(0xFF474E58),
        Color(0xFF616874),
        Color(0xFF7B8390),
        Color(0xFF949CA8),
        Color(0xFFAAB1BC),
        Color(0xFFBCC2CC),
        Color(0xFFCDD2D8),
        Color(0xFFDCE0E4),
      ]);
    });
  });

  group('露露缇雅·泽金版（--dart-define=HEITA=1）', () {
    test('四色原色真的用上了', () {
      if (!kHeita) {
        // 默认跑测试时不带 dart-define，这一组自动跳过。
        // 要验露露缇雅版：`flutter test --dart-define=HEITA=1`
        return;
      }
      expect(C.over, const Color(0xFF814864), reason: '绯红（绯带）→ 超支');
      expect(C.cardBg, const Color(0xFFFDFBF8), reason: '暖白（白裙）→ 卡片面');
      expect(C.ink4, const Color(0xFFBC9DB1), reason: '薰衣草 → 占位/弱分割');
      expect(C.accentSoft, const Color(0xFF9AC7D3), reason: '天青 → 徽标底');
      // 天青原色太亮，不能直接当文字色 —— 只能配深绯紫的字
      expect(_contrast(C.ink, C.accentSoft), greaterThan(4.5));
      expect(_contrast(C.accentSoft, C.bg), lessThan(3), reason: '所以天青不当文字色');
    });

    test('超支色与强调色分得开（否则「超支」看不出来）', () {
      if (!kHeita) return;
      // 明度只差 1.4 —— 绯红 #814864 与深天青 #3E7A8B 都压在中间调，
      // 这是「四色方案」的固有结果：四色里没有一档是给「亮强调」留的。
      // 所以「超支」靠**色相翻转**（青 → 绯）表达，不靠明度；
      // 真要一眼看出，得靠旁边的「超支 X」文案，颜色只是辅助。
      expect(_contrast(C.over, C.accent), greaterThan(1.3));
      expect(C.over, isNot(C.accent));
    });
  });
}
