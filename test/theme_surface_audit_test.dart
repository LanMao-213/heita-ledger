// 「ThemeData 里每一块面都得是色板里的颜色」。
//
// 为什么值得写：`C.xxx` 是运行时 getter，我们自己的 widget 永远画当前皮肤；
// 但 Material 原生组件（Switch / PopupMenu / SnackBar / 对话框）是从
// `ThemeData.colorScheme` 派生颜色的 —— 那些派生面**不会**自动跟着色板走。
// 只覆盖 `primary` / `surface` 两项的话，剩下的会停在 Material 3 默认色：
// 亮色板下那套默认是**带紫的灰**（surfaceContainer #F3EDF7、outline #79747E、
// secondary #625B71），在中性灰/暖米/泽金/圣地四套里一眼就看得出「这块不是
// 我们家的颜色」。
//
// 已经踩过两次：
// 1. 冷启动 ThemeData 停在出厂皮肤（见 boot_theme_sync_test.dart）；
// 2. Switch 轨道是 #E6E0E9、PopupMenu 是 #F3EDF7 —— 本文件管的这一种。
//
// 做法：把 ThemeData 里**界面上真的会用到**的面全列出来，逐个断言它属于
// 当前色板。以后谁新加 Material 组件、或者色板改了值，这里会立刻红。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
import 'package:ledger/design/tokens.dart';

String hx(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// 这一套色板自己的全部颜色（用于判断某个面是不是「自家的」）
Set<String> _ownColors(Palette p) => <String>{
      hx(p.ink),
      hx(p.ink2),
      hx(p.ink3),
      hx(p.ink4),
      hx(p.bg),
      hx(p.bg2),
      hx(p.bg3),
      hx(p.line),
      hx(p.line2),
      hx(p.over),
      hx(p.accent),
      hx(p.accentSoft),
      hx(p.todayMark),
      hx(p.onAccent),
      hx(p.onTodayMark),
      hx(p.cardBg),
      hx(p.heroBg),
      for (final c in p.chart) hx(c),
    };

/// 阴影 / 蒙层本来就该是黑，surfaceTint 关掉后也是透明黑 —— 不算穿帮。
bool _naturallyBlack(Color c) => (c.toARGB32() & 0xFFFFFF) == 0x000000;

void main() {
  for (final p in kPalettes) {
    group('${p.name}：ThemeData 里没有 Material 默认色', () {
      late ThemeData t;
      late ColorScheme cs;
      late Set<String> own;

      setUp(() {
        ThemeCtrl.i.loadSilently(p.id);
        t = buildAppTheme();
        cs = t.colorScheme;
        own = _ownColors(p);
      });

      test('界面会用到的每一块面都来自色板', () {
        final surfaces = <String, Color>{
          'scaffoldBg': t.scaffoldBackgroundColor,
          'cardTheme': t.cardTheme.color ?? cs.surface,
          'dialogTheme': t.dialogTheme.backgroundColor ?? cs.surface,
          'bottomSheet': t.bottomSheetTheme.backgroundColor ?? cs.surface,
          'popupMenu': t.popupMenuTheme.color ?? cs.surfaceContainer,
          'snackBar': t.snackBarTheme.backgroundColor ?? cs.inverseSurface,
          'divider': t.dividerColor,
          'appBar': t.appBarTheme.backgroundColor ?? cs.surface,
          'cs.surface': cs.surface,
          'cs.onSurface': cs.onSurface,
          'cs.primary': cs.primary,
          'cs.secondary': cs.secondary,
          'cs.onSecondary': cs.onSecondary,
          'cs.surfaceContainer': cs.surfaceContainer,
          'cs.surfaceContainerLow': cs.surfaceContainerLow,
          'cs.surfaceContainerHigh': cs.surfaceContainerHigh,
          'cs.surfaceContainerHighest': cs.surfaceContainerHighest,
          'cs.onSurfaceVariant': cs.onSurfaceVariant,
          'cs.outline': cs.outline,
          'cs.outlineVariant': cs.outlineVariant,
          'cs.inverseSurface': cs.inverseSurface,
          'cs.onInverseSurface': cs.onInverseSurface,
        };

        final bad = <String>[];
        for (final e in surfaces.entries) {
          final v = hx(e.value);
          if (_naturallyBlack(e.value)) continue;
          if (!own.contains(v)) bad.add('${e.key}=$v');
        }

        expect(
          bad,
          isEmpty,
          reason: '${p.name} 有面停在 Material 默认色上（不是本套色板的颜色）：\n'
              '  ${bad.join('\n  ')}',
        );
      });

      test('Switch 的轨道与滑块都吃色板，且开/关两态看得出区别', () {
        final sw = t.switchTheme;

        const onStates = <WidgetState>{WidgetState.selected};
        const offStates = <WidgetState>{};

        final onThumb = sw.thumbColor?.resolve(onStates) ?? cs.primary;
        final offThumb = sw.thumbColor?.resolve(offStates) ?? cs.outline;
        final onTrack = sw.trackColor?.resolve(onStates) ?? cs.primary;
        final offTrack =
            sw.trackColor?.resolve(offStates) ?? cs.surfaceContainerHighest;

        for (final e in {
          '开·滑块': onThumb,
          '关·滑块': offThumb,
          '开·轨道': onTrack,
          '关·轨道': offTrack,
        }.entries) {
          expect(
            own.contains(hx(e.value)),
            isTrue,
            reason: '${p.name} 的 Switch ${e.key}=${hx(e.value)} 不是色板里的颜色',
          );
        }

        // 轨道和滑块必须不同色，否则开关就是一整条同色、看不出状态。
        // （真踩过：周期账单页曾经显式给了 activeThumbColor = C.ink，
        //  而轨道在主题里也是墨色 —— 开启状态变成一坨实心色块。）
        expect(
          hx(onTrack),
          isNot(hx(onThumb)),
          reason: '${p.name} 的 Switch 开启时轨道和滑块同色，看不出开关状态',
        );
        expect(
          hx(offTrack),
          isNot(hx(offThumb)),
          reason: '${p.name} 的 Switch 关闭时轨道和滑块同色，看不出开关状态',
        );
      });

      test('弹层/对话框的面与色板的卡面同源', () {
        expect(
          hx(t.bottomSheetTheme.backgroundColor ?? cs.surface),
          hx(p.cardBg),
          reason: '${p.name} 的弹层底色不是色板的 cardBg',
        );
        expect(
          hx(t.dialogTheme.backgroundColor ?? cs.surface),
          hx(p.cardBg),
          reason: '${p.name} 的对话框底色不是色板的 cardBg',
        );
        expect(
          hx(t.popupMenuTheme.color ?? cs.surfaceContainer),
          hx(p.cardBg),
          reason: '${p.name} 的弹出菜单底色不是色板的 cardBg',
        );
      });
    });
  }
}
