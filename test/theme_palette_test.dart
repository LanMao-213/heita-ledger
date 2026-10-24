import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
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
  // 这套测试自己会换主题，跑完把单例还原 —— 每个测试文件是独立 isolate，
  // 所以还原只是对本文件内部负责。
  final boot = ThemeCtrl.i.id;

  tearDownAll(() => ThemeCtrl.i.loadSilently(boot));

  // ------------------------------------------------------------ 1 逐套体检
  //
  // 遍历 `kPalettes`：新增皮肤不需要为它单独写用例，改坏任何一套都会在这里红。
  // 阈值取的是「六套里最差的那套实测值再往下留一点余量」，不是随手写的。
  group('每一套色板都可用', () {
    for (final p in kPalettes) {
      group('${p.name}（${p.dark ? '深色' : '亮色'}）', () {
        test('文字在底上、在卡上都看得清', () {
          // 主文字 AAA（7:1）：最差的是泽金 10.89
          expect(_contrast(p.ink, p.bg), greaterThan(7), reason: '${p.name} 主文字 AAA');
          expect(_contrast(p.ink, p.cardBg), greaterThan(7), reason: '${p.name} 卡上主文字 AAA');
          // 次要 / 辅助 / 超支 AA（4.5:1）：辅助文字是 12.5px 的 caption 在用
          expect(_contrast(p.ink2, p.bg), greaterThanOrEqualTo(4.5));
          expect(_contrast(p.ink3, p.bg), greaterThanOrEqualTo(4.5), reason: '${p.name} 辅助文字 AA');
          expect(_contrast(p.ink3, p.cardBg), greaterThanOrEqualTo(4.5));
          expect(_contrast(p.over, p.bg), greaterThanOrEqualTo(4.5), reason: '${p.name} 超支 AA');
          expect(_contrast(p.over, p.cardBg), greaterThanOrEqualTo(4.5));
        });

        test('进度条填充与轨道 ≥ 3（图形对象下限）', () {
          // Bar / LinearProgressIndicator：填充 accent、轨道 handle。
          // 最差的是圣地 3.60（早先 #4E8FB5 只有 2.75，因此被压深过）。
          expect(_contrast(p.accent, p.handle), greaterThanOrEqualTo(3), reason: p.name);
          // 强调色本身压在卡面上也要看得见
          expect(_contrast(p.accent, p.cardBg), greaterThanOrEqualTo(3), reason: p.name);
        });

        test('ink4 够得着图形下限 3:1，但仍明显淡于 ink3', () {
          // ink4 看着是「最弱的一档墨」，其实它承担图形岗位：图表里的收入柱、
          // 安全页的进度圈、日历的非本月日期。图形对象的门槛是 3:1，
          // 不是「比底深一点就行」—— 1.4.21 之前四套亮色板只有 1.47～2.37，
          // 柱子淡到几乎看不见。
          //
          // 按「会画到的所有面」取最严的那个：卡面与页面底都要过。
          // 深色板这两面都比卡亮，取 min 一样成立。
          for (final face in [p.cardBg, p.bg]) {
            expect(_contrast(p.ink4, face), greaterThanOrEqualTo(3.0),
                reason: '${p.name} ink4 对面 #${face.toARGB32().toRadixString(16)} '
                    '只有 ${_contrast(p.ink4, face).toStringAsFixed(3)}，图形要 3:1');
          }
          // 「弱化」这个语义不能因为提对比度就丢掉：ink3 至少要比它深 1.4 倍
          expect(
            _contrast(p.ink3, p.cardBg) / _contrast(p.ink4, p.cardBg),
            greaterThanOrEqualTo(1.4),
            reason: '${p.name} ink4 提太深了，和 ink3 分不出层级',
          );
        });

        test('压在强调色 / 今日圆点上的字看得清', () {
          // 「今天」那个圆点里是日期数字（文字），下限 4.5 不是 3。
          expect(_contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: p.name);
          expect(_contrast(p.onTodayMark, p.todayMark), greaterThanOrEqualTo(4.5), reason: p.name);
        });

        test('面与面之间分得开，层级不塌', () {
          // 概览卡「压下去」、明细卡「浮上来」、卡里的胶囊再降一档。
          // 任意两档同色，那一层就消失了 —— 深浅两族的方向相反，
          // 所以这里用对比度比值判定，不写死谁更亮。
          expect(_contrast(p.heroBg, p.cardBg), greaterThanOrEqualTo(1.10),
              reason: '${p.name} 概览卡要能看出是压下去的');
          expect(_contrast(p.cardBg, p.bg), greaterThanOrEqualTo(1.08),
              reason: '${p.name} 卡片要浮在页面底之上');
          // ⚠️ 这一条曾经漏了整整一个版本：只查了「概览卡 vs 卡面」，
          // 没查「概览卡 vs 页面底」。而概览卡真正压在上面的是页面底 ——
          // 数学上 底/概览 = (卡/概览) ÷ (卡/底)，上面两条各压着线过，
          // 除出来就只剩 1.04。深色两套（永夜 1.040 / 血族 1.036）因此
          // 一直糊着，直到 2026-10-24 逐套量像素才发现。
          expect(_contrast(p.heroBg, p.bg), greaterThanOrEqualTo(1.08),
              reason: '${p.name} 概览卡压在页面底上要能看出边界');
          expect(_contrast(p.bg2, p.cardBg), greaterThanOrEqualTo(1.08),
              reason: '${p.name} 卡内次级面 ≠ 卡面');
          expect(_contrast(p.bg2, p.bg), greaterThanOrEqualTo(1.03),
              reason: '${p.name} 输入底 ≠ 页面底');
          expect(_contrast(p.line, p.cardBg), greaterThanOrEqualTo(1.10),
              reason: '${p.name} 描边要看得见');
          // 两族的方向其实**相同**：概览卡都比页面底深（压下去），
          // 卡片都比页面底亮（浮起来）。早先这里的注释写着「方向相反」，
          // 下面两个分支却写着一模一样的不等式 —— 注释是错的，删掉分支。
          expect(p.heroBg.computeLuminance(), lessThan(p.bg.computeLuminance()),
              reason: '${p.name} 概览卡要压到页面底之下');
          expect(p.cardBg.computeLuminance(), greaterThan(p.bg.computeLuminance()),
              reason: '${p.name} 卡片要比页面底亮');
        });

        test('图表十档：最弱的一档也浮在卡面之上', () {
          expect(p.chart.length, 10, reason: '${p.name} 饼图切片按十档循环');
          // 最弱档贴到卡面 = 那一片饼图是隐形的（黑塔/血族早先都踩过：
          // 第十档直接写成了 cardBg 自己，1.00:1）。
          expect(_contrast(p.chart.last, p.cardBg), greaterThanOrEqualTo(1.12),
              reason: '${p.name} 第十档不能贴到卡面');
          // 最强档必须一眼是「主切片」
          expect(_contrast(p.chart.first, p.cardBg), greaterThanOrEqualTo(3),
              reason: '${p.name} 第一档要够重');
          // 相邻两档要分得开，否则十档退化成五档
          for (var i = 0; i < p.chart.length - 1; i++) {
            expect(_contrast(p.chart[i], p.chart[i + 1]), greaterThanOrEqualTo(1.09),
                reason: '${p.name} 第 ${i + 1} 档与第 ${i + 2} 档太接近');
          }
        });
      });
    }
  });

  // ------------------------------------------------------------ 2 钉死冷灰
  //
  // 「改色必须是有意识的」：冷灰这一套的值被顺手改掉时先在这里红。
  // 多套皮肤之后仍然保留钉值 —— 遍历测试只能证明「可用」，证明不了「没被改」。
  group('中性冷灰的值被钉死', () {
    setUp(() => ThemeCtrl.i.loadSilently(HeitaThemeId.cold));

    test('24 个颜色 token 与十档色阶', () {
      // 2026-10-23 整体换板（暖米「纸墨」→ 中性冷灰，对齐 iOS grouped）：
      // 底色 #F5F2EA→#F3F4F7、墨 #1C1A17→#14161A、投影全部归零。
      // 下面这组期望值是那次换板后的基线；2026-10-24 起它们不再是唯一一套，
      // 但冷灰自己的值仍然不许漂移。
      expect(C.ink, const Color(0xFF14161A));
      expect(C.ink2, const Color(0xFF5C626B));
      expect(C.ink3, const Color(0xFF656A75));
      // 原 #BFC4CC 对卡面只有 1.75:1，够不到图形下限 3:1（柱子/进度圈在用）。
      // 1.4.21 降明度到 #838C9C，色相（217° 蓝灰）不动。
      expect(C.ink4, const Color(0xFF838C9C));
      expect(C.inkWash, const Color(0x0F14161A));
      expect(C.bg, const Color(0xFFF3F4F7));
      expect(C.bg2, const Color(0xFFE8EAF0));
      expect(C.bg3, const Color(0xFFF6F7FA));
      expect(C.line, const Color(0xFFE2E5EA));
      expect(C.line2, const Color(0xFFCFD4DB));
      expect(C.over, const Color(0xFFB0302A));
      expect(C.overD, const Color(0xFFC0625A));
      expect(C.stage, const Color(0xFFD8DBE1));
      // 强调色 === 主文字色（冷灰原则：不引入装饰色）
      expect(C.accent, C.ink, reason: '强调色 = 主文字色');
      // 压在深色块上的字必须是纯白
      expect(C.onAccent, const Color(0xFFFFFFFF));
      expect(C.accentSoft, const Color(0xFFEEF0F4));
      expect(C.accentWash, const Color(0xFFF0F2F5));
      expect(C.todayMark, C.ink);
      expect(C.onTodayMark, const Color(0xFFFFFFFF));
      expect(C.cardShadow, const Color(0x0D14161A));
      expect(C.handle, const Color(0xFFE7EAF0));
      expect(C.heroEdge, const Color(0xFFD8DDE5));
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
      // 描边与概览卡描边是两族（同为冷灰但不同值，便于各自微调）
      expect(C.heroEdge, isNot(C.line));
    });

    test('ThemeData 跟着色板走：冷灰是亮色', () {
      expect(buildAppTheme().brightness, Brightness.light);
    });
  });

  // ------------------------------------------------------------ 3 换肤生效
  group('换肤', () {
    test('出厂默认是黑塔·永夜，且 ThemeData 是深色的', () {
      // 需求本身：App 叫「黑塔消费日记」，默认给黑塔那一套。
      expect(kDefaultTheme, HeitaThemeId.tower);
      ThemeCtrl.i.loadSilently(kDefaultTheme);
      expect(ThemeCtrl.i.dark, isTrue);
      expect(buildAppTheme().brightness, Brightness.dark);
    });

    test('C.xxx 是运行时 getter：换 id 后取到的是新色板的色', () {
      ThemeCtrl.i.loadSilently(HeitaThemeId.cold);
      final cold = C.bg;
      ThemeCtrl.i.loadSilently(HeitaThemeId.tower);
      final tower = C.bg;
      expect(cold, isNot(tower), reason: '换肤后底色必须变');
      expect(tower, paletteOf(HeitaThemeId.tower).bg);
      expect(kChart, paletteOf(HeitaThemeId.tower).chart, reason: '图表色阶也跟着换');
    });

    test('ThemeCtrl.apply 会通知监听者（换肤靠它触发整树重建）', () {
      ThemeCtrl.i.loadSilently(HeitaThemeId.cold);
      var fired = 0;
      void onFire() => fired++;
      ThemeCtrl.i.addListener(onFire);
      addTearDown(() => ThemeCtrl.i.removeListener(onFire));

      ThemeCtrl.i.apply(HeitaThemeId.tower);
      expect(fired, 1);
      // 同一个 id 再 apply 一次不该多通知一次
      ThemeCtrl.i.apply(HeitaThemeId.tower);
      expect(fired, 1);
    });

    test('持久化字符串 ↔ id 双向对得上；认不出的值回落到出厂默认', () {
      for (final t in HeitaThemeId.values) {
        expect(themeIdFromString(t.name), t);
      }
      expect(themeIdFromString(null), kDefaultTheme);
      expect(themeIdFromString(''), kDefaultTheme);
      expect(themeIdFromString('nonsense'), kDefaultTheme);
      // 老版本没有 ui.theme 这个键 → 也是出厂默认（黑塔·永夜），不是冷灰
      expect(themeIdFromString(null), HeitaThemeId.tower);
    });

    test('每套色板都有名字、副标题和完整十档（少一档就是运行时空色）', () {
      expect(kPalettes.length, HeitaThemeId.values.length,
          reason: '加皮肤时枚举和色板表要一起加');
      for (final t in HeitaThemeId.values) {
        final p = paletteOf(t);
        expect(p.id, t);
        expect(p.name, isNotEmpty);
        expect(p.subtitle, isNotEmpty);
        expect(p.chart.length, 10);
      }
    });
  });
}
