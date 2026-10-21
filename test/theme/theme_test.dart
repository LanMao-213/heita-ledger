import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/theme/app_theme.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/theme/typography.dart';

/// 主题系统：token 完整性、色阶方向、`lerp`、`ThemeData` 工厂。
///
/// 这一组挡的是 R4「双配色漏改」的两个结构性成因：
/// ① 新增 token 时忘了登记（[AppPalette.tokens] / `lerp` 漏字段）；
/// ② 某个页面没走 `context.pal`（由 `check_theme_hardcode.sh` 挡）。
void main() {
  group('配色 token 完整性', () {
    test('两套配色各 22 个 token，id 稳定、label 非空', () {
      expect(AppPalette.all.length, 2);
      for (final AppPalette pal in AppPalette.all) {
        expect(pal.tokens.length, 22, reason: '${pal.id} 的 token 数量必须是 22');
        expect(pal.id, isNotEmpty);
        expect(pal.label, isNotEmpty);
        // 全部 token 必须有 alpha（不允许透明占位，透明了就是「没上色」）
        for (final MapEntry<String, Color> entry in pal.tokens.entries) {
          expect(entry.value.a, greaterThan(0.0), reason: '${pal.id}.${entry.key} 透明');
        }
      }
      expect(AppPalette.all.map((AppPalette p) => p.id), <String>['ink', 'aurora']);
    });

    test('chart 都是 10 档，且严格由深到浅（亮度单调下降）', () {
      for (final AppPalette pal in AppPalette.all) {
        expect(pal.chart.length, AppPalette.chartSteps);
        expect(pal.chart.length, 10);
        for (int i = 1; i < pal.chart.length; i++) {
          final double prev = pal.chart[i - 1].computeLuminance();
          final double next = pal.chart[i].computeLuminance();
          expect(
            next,
            greaterThan(prev),
            reason: '${pal.id}.chart[$i] 必须比 chart[${i - 1}] 更浅（I19）',
          );
        }
        // 首档必须明显深于末档（黑白色盲也要能分出主次）
        expect(
          pal.chart.last.computeLuminance() - pal.chart.first.computeLuminance(),
          greaterThan(0.3),
        );
      }
    });

    test('surfaceAlt 必须比 surface 和 bg 都深（卡内次级面才看得出层次）', () {
      for (final AppPalette pal in AppPalette.all) {
        final double alt = pal.surfaceAlt.computeLuminance();
        expect(alt, lessThan(pal.surface.computeLuminance()), reason: pal.id);
        expect(alt, lessThan(pal.bg.computeLuminance()), reason: pal.id);
      }
    });

    test('byId 认得出两套；认不出（null / 脏值）回落 ink 且不抛', () {
      expect(AppPalette.byId('ink').id, 'ink');
      expect(AppPalette.byId('aurora').id, 'aurora');
      expect(AppPalette.byId(null).id, 'ink');
      expect(AppPalette.byId('midnight-blue').id, 'ink');
    });

    test('lerp：端点恒等、中点确实被插值、chart 长度不变', () {
      final AppPalette ink = paletteInk();
      final AppPalette aurora = paletteAurora();

      expect(identical(ink.lerp(aurora, 0), ink), isTrue);
      expect(identical(ink.lerp(aurora, 1), aurora), isTrue);

      final AppPalette mid = ink.lerp(aurora, 0.5);
      expect(mid.chart.length, 10);
      // id/label 取目标值（标识不是颜色）
      expect(mid.id, aurora.id);
      // 每个 token 都必须真的插值了（漏一个字段 → 切换时会跳变）
      for (final String key in ink.tokens.keys) {
        final Color a = ink.tokens[key]!;
        final Color b = aurora.tokens[key]!;
        final Color m = mid.tokens[key]!;
        if (a == b) {
          expect(m, a, reason: '$key 两套同色，插值应保持不变');
        } else {
          expect(m == a || m == b, isFalse, reason: '$key 没有参与插值');
        }
      }
      for (int i = 0; i < 10; i++) {
        final Color m = mid.chart[i];
        expect(m, isNot(ink.chart[i]));
        expect(m, isNot(aurora.chart[i]));
      }
    });

    test('copyWith 只改指定字段，其余保持', () {
      final AppPalette ink = paletteInk();
      final AppPalette patched = ink.copyWith(over: paletteAurora().over);
      expect(patched.over, paletteAurora().over);
      expect(patched.ink, ink.ink);
      expect(patched.id, ink.id);
    });
  });

  group('ThemeData 工厂', () {
    testWidgets('两套配色都能 pump 探针页（Scaffold + Card + Text + TextButton）且无溢出', (
      WidgetTester tester,
    ) async {
      for (final AppPalette pal in AppPalette.all) {
        String? observedPaletteId;
        AppPalette? observedInstance;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(pal, Brightness.light),
            home: Builder(
              builder: (BuildContext context) {
                // 树里取到的必须就是这一套（不是回落、不是另一套）
                observedPaletteId = context.pal.id;
                observedInstance = Theme.of(context).extension<AppPalette>();
                return Scaffold(
                  backgroundColor: context.pal.bg,
                  body: Center(
                    child: Card(
                      color: context.pal.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(S.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '探针页',
                              style: Ts.body.copyWith(color: context.pal.ink),
                            ),
                            Text(
                              '2026-10-16 · 记账',
                              style: Ts.caption.copyWith(
                                color: context.pal.ink3,
                              ),
                            ),
                            TextButton(
                              onPressed: () {},
                              child: const Text('按钮'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: '${pal.id} 渲染抛异常');
        expect(observedPaletteId, pal.id);
        expect(observedInstance, same(pal));
      }
    });

    test('主题里的颜色全部来自 palette（scaffold/canvas/divider/snackBar/AppBar）', () {
      for (final AppPalette pal in AppPalette.all) {
        final ThemeData theme = buildTheme(pal, Brightness.light);
        expect(theme.scaffoldBackgroundColor, pal.bg);
        expect(theme.canvasColor, pal.surface);
        expect(theme.dividerColor, pal.line);
        expect(theme.colorScheme.primary, pal.accent);
        expect(theme.colorScheme.surface, pal.surface);
        expect(theme.colorScheme.onSurface, pal.ink);
        expect(theme.colorScheme.error, pal.over);
        expect(theme.appBarTheme.backgroundColor, pal.bg);
        expect(theme.snackBarTheme.backgroundColor, pal.ink);
        expect(theme.extension<AppPalette>(), same(pal));
      }
    });

    test('buildTheme 吃 Brightness 参数（V1 只做浅色，结构上必须能吃深色）', () {
      final ThemeData light = buildTheme(paletteInk(), Brightness.light);
      final ThemeData dark = buildTheme(paletteInk(), Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      // 深色下仍然挂着同一份 palette（第三套配色加进来时只换 palette 即可）
      expect(dark.extension<AppPalette>()?.id, 'ink');
    });
  });

  group('字号阶梯与数值规范', () {
    test('11 档，字号严格递增，金额档带等宽数字', () {
      expect(Ts.all.length, 11);

      final List<double> sizes = <double>[
        Ts.badge.fontSize!,
        Ts.micro.fontSize!,
        Ts.caption.fontSize!,
        Ts.body2.fontSize!,
        Ts.amountSm.fontSize!,
        Ts.body.fontSize!,
        Ts.section.fontSize!,
        Ts.amount.fontSize!,
        Ts.title.fontSize!,
        Ts.heroSm.fontSize!,
        Ts.hero.fontSize!,
      ];
      for (int i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThan(sizes[i - 1]), reason: '字号阶梯必须递增');
      }

      for (final TextStyle style in <TextStyle>[Ts.amount, Ts.amountSm]) {
        expect(style.fontFeatures, isNotNull);
        expect(
          style.fontFeatures!.first.feature,
          'tnum',
          reason: '金额必须等宽数字，否则逐行金额小数点会左右跳',
        );
      }
    });

    test('间距 / 圆角 / 动效 / 阴影数值与架构设计 §6.4 一致', () {
      expect(<double>[S.xs, S.sm, S.md, S.lg, S.xl, S.xxl, S.xxxl],
          <double>[4, 8, 12, 16, 20, 24, 32]);
      expect(S.page, 16);
      expect(S.card, 14);
      expect(<double>[R.sm, R.md, R.card, R.lg, R.pill],
          <double>[8, 12, 16, 20, 999]);
      expect(Dur.instant, Duration.zero);
      expect(Dur.micro.inMilliseconds, 80);
      expect(Dur.size.inMilliseconds, 150);
      expect(Dur.theme.inMilliseconds, 200, reason: '配色插值 200ms');
      expect(Dur.sheet.inMilliseconds, 240);
      expect(Dur.page.inMilliseconds, 260);
      expect(Dur.dblTap.inMilliseconds, 300);

      // 阴影用 palette 的 shadow 基色，不是写死的黑
      final AppPalette aurora = paletteAurora();
      expect(Elev.card(aurora).single.color.r, aurora.shadow.r);
      expect(Elev.sheet(aurora).single.offset.dy, -6);
      expect(Elev.fab(aurora).single.blurRadius, 18);
    });
  });
}
