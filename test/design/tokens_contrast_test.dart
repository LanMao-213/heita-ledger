import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/tokens.dart';

/// 色板护栏：以后谁调色，只要破坏可读性或层级，这里立刻红。
///
/// 为什么单独一个文件：`theme_palette_test.dart` 钉的是「值本身」（防止色差漂移），
/// 这里钉的是「值之间的关系」（防止调色时只顾好看、把可读性调没了）。
/// 前者只要换色板就会整组报废，后者是可以长期留着的规矩。
///
/// 亮度公式与 WCAG 2.1 一致：sRGB 通道先线性化，再按 0.2126/0.7152/0.0722 加权。
double _relativeLuminance(Color c) {
  double linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(c.r) +
      0.7152 * linearize(c.g) +
      0.0722 * linearize(c.b);
}

/// 两色对比度（1.0 – 21.0）。顺序无关。
double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('层级约束：面必须按「卡浮起来、槽沉下去」排', () {
    test('bg2 比 cardBg 深，且比 bg 深（数字键帽必须沉下去）', () {
      final bg2 = _relativeLuminance(C.bg2);
      final cardBg = _relativeLuminance(C.cardBg);
      final bg = _relativeLuminance(C.bg);

      expect(
        bg2,
        lessThan(cardBg),
        reason: '卡内次级面 ≠ 卡面同色，否则「未选中」整片消失',
      );
      expect(
        bg2,
        lessThan(bg),
        reason: '键帽要比抽屉的面深，反过来会像键浮在面上',
      );
      // 反过来也要成立：卡必须比页面底亮 —— 这是「卡浮起来」的全部依据
      // （投影只有 4%，撑不起层级）。
      expect(
        cardBg,
        greaterThan(bg),
        reason: '卡比底亮，D-10 的层级靠这一条',
      );
    });

    test('heroBg 比 bg 深，且与 cardBg 不同（汇总压下、记录浮上）', () {
      final heroBg = _relativeLuminance(C.heroBg);
      final bg = _relativeLuminance(C.bg);

      expect(heroBg, lessThan(bg), reason: '概览卡是「压下去」的那一块');
      expect(C.heroBg, isNot(C.cardBg), reason: '同色的话两层就并成一层了');
      expect(
        _relativeLuminance(C.cardBg) - heroBg,
        greaterThan(0.02),
        reason: '差距太小（<2% 亮度）肉眼分不出，等于没拆',
      );
    });

    test('line 对 cardBg 的对比在 1.05–1.45 之间（看得见，但不抢眼）', () {
      final ratio = _contrast(C.line, C.cardBg);
      expect(
        ratio,
        greaterThanOrEqualTo(1.05),
        reason: '低于 1.05 描边就消失了，卡片边界全靠投影撑',
      );
      expect(
        ratio,
        lessThanOrEqualTo(1.45),
        reason: '高于 1.45 描边会抢文字，纸墨调子会变硬',
      );
    });
  });

  group('可读性约束：文字对底', () {
    test('ink 对 bg ≥ 7:1（正文 AAA）', () {
      expect(_contrast(C.ink, C.bg), greaterThanOrEqualTo(7.0));
      // 正文也会压在卡片上（明细日卡、往来卡），那里更亮，同样要过。
      expect(_contrast(C.ink, C.cardBg), greaterThanOrEqualTo(7.0));
    });

    test('ink2 对 bg ≥ 4.5:1（次要文字 AA）', () {
      expect(_contrast(C.ink2, C.bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(C.ink2, C.cardBg), greaterThanOrEqualTo(4.5));
    });

    test('ink3 对 bg ≥ 4.5:1（12.5px 的 caption 只能靠这条）', () {
      // 旧色板这里是 #9AA0A8（白底 2.6:1），小字长期不达标。
      // 这条断言就是把「以后不能再调回去」写死。
      expect(_contrast(C.ink3, C.bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(C.ink3, C.cardBg), greaterThanOrEqualTo(4.5));
    });

    test('over 对 bg ≥ 4.5:1（超支金额是正文级的字）', () {
      expect(_contrast(C.over, C.bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(C.over, C.cardBg), greaterThanOrEqualTo(4.5));
    });

    test('accent 上的字（onAccent）看得清', () {
      expect(_contrast(C.onAccent, C.accent), greaterThanOrEqualTo(4.5));
      expect(_contrast(C.onTodayMark, C.todayMark), greaterThanOrEqualTo(4.5));
    });

    test('进度条填充对轨道 ≥ 3:1（图形对象的下限）', () {
      expect(_contrast(C.accent, C.handle), greaterThanOrEqualTo(3.0));
    });
  });

  group('文字层级不能被压平', () {
    test('ink → ink2 → ink3 → ink4 逐级变浅', () {
      final luminances = [
        _relativeLuminance(C.ink),
        _relativeLuminance(C.ink2),
        _relativeLuminance(C.ink3),
        _relativeLuminance(C.ink4),
      ];
      for (var i = 1; i < luminances.length; i++) {
        expect(
          luminances[i],
          greaterThan(luminances[i - 1]),
          reason: '第 $i 档比上一档更浅，否则「次要/辅助」分不出来',
        );
      }
    });

    test('kChart 十档单调变浅（越深越主要）', () {
      for (var i = 1; i < kChart.length; i++) {
        expect(
          _relativeLuminance(kChart[i]),
          greaterThan(_relativeLuminance(kChart[i - 1])),
          reason: '第 $i 档必须比上一档浅',
        );
      }
    });
  });
}
