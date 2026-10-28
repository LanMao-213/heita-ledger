// 冷启动原生配置的守卫 —— 启动页删掉之后，"四屏同色"那条约束换了内容，但没有消失。
//
// 换成了什么：原来是「原生窗口 = 系统闪屏 = Flutter 启动页 = 渐变均值」，
// 现在是「原生窗口 = 系统闪屏 = Flutter 首帧底色 = 主界面底色」。
// 这四条里前三条都在 android/ 下的 XML 里，Dart 类型管不到它们 ——
// 改错一处不会有编译错误，只会在真机上闪一下浅色/深色带，而且只有冷启动那 200ms
// 才看得见，测试跑一万遍也发现不了。所以只能读文件比对。
//
// 这份测试同时承担"死链检查"：启动页删掉后有几个资源被移除
// （launch_background.xml、splash_icon_none.xml → launch_icon_none.xml），
// 只要有一处 @drawable 还指着旧名字，构建期才会报错，而那时已经推到 CI 了。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _resDir = 'android/app/src/main/res';
const String _manifest = 'android/app/src/main/AndroidManifest.xml';

/// 读 XML 并剥掉注释。
///
/// 必须剥：这几个文件里到处是「不要改回 xxx」的警示注释，注释里也会出现
/// `@mipmap/…`、`#14161A` 这类字样。不剥的话守卫会把警示当成真实配置，
/// 自己先误报（上一版 splash_spec_test 就踩过）。
String _body(String path) =>
    File(path).readAsStringSync().replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

/// 取某个 `<style name="…">` 的内容
String _styleOf(String xml, String name) {
  final i = xml.indexOf('<style name="$name"');
  expect(i, isNonNegative, reason: '找不到 <style name="$name">');
  final j = xml.indexOf('</style>', i);
  expect(j, greaterThan(i), reason: '$name 的 style 块没有闭合');
  return xml.substring(i, j);
}

/// 取 style 的 parent 属性
String _parentOf(String styleBlock) {
  final m = RegExp(r'parent="([^"]+)"').firstMatch(styleBlock);
  expect(m, isNotNull, reason: 'style 没有 parent 属性，会退到默认主题');
  return m!.group(1)!;
}

/// 取 style 里某个 android: 项的值
String? _itemOf(String styleBlock, String name) => RegExp(
  '<item name="android:$name">\\s*([^<]+?)\\s*</item>',
).firstMatch(styleBlock)?.group(1);

/// 把 `#RRGGBB` / `#AARRGGBB` 解析成 Color
Color _parseHex(String hex) {
  var v = hex.replaceAll('#', '').trim();
  if (v.length == 6) v = 'FF$v';
  return Color(int.parse(v, radix: 16));
}

void main() {
  group('冷启动四层同色（启动页已删除）', () {
    // 三份 styles 都必须满足：LaunchTheme 与 NormalTheme 指向同一个颜色。
    // values-night 也在内 —— App 只有浅色界面，深色模式跟着系统变黑就是
    // 一次「黑窗口 → 浅色主界面」的跳变。
    for (final rel in const [
      'values/styles.xml',
      'values-night/styles.xml',
    ]) {
      test('$rel：两个主题的窗口底色都指向 @color/app_background', () {
        final xml = _body('$_resDir/$rel');
        final launch = _styleOf(xml, 'LaunchTheme');
        final normal = _styleOf(xml, 'NormalTheme');

        expect(
          _itemOf(launch, 'windowBackground'),
          '@color/app_background',
          reason: '$rel 的 LaunchTheme 没有用统一底色：首帧之前会露出别的颜色',
        );
        expect(
          _itemOf(normal, 'windowBackground'),
          '@color/app_background',
          reason: '$rel 的 NormalTheme 没和 LaunchTheme 同色：'
              'Flutter 画满之前那一层会有色差带，横滑时最明显',
        );
      });

      test('$rel：LaunchTheme 用 Light 父主题', () {
        final launch = _styleOf(_body('$_resDir/$rel'), 'LaunchTheme');
        expect(
          _parentOf(launch),
          contains('Theme.Light'),
          reason: '底色已经改成浅色，父主题若还是 Theme.Black，'
              '状态栏图标会是白色 —— 浅底上看不见时间和电量',
        );
      });
    }

    test('values-v31（Android 12+ 系统闪屏）：底色同色、不画图标', () {
      final xml = _body('$_resDir/values-v31/styles.xml');
      final launch = _styleOf(xml, 'LaunchTheme');

      expect(
        _itemOf(launch, 'windowSplashScreenBackground'),
        '@color/app_background',
        reason: '系统闪屏是 Android 12+ 冷启动的第一屏，它不同色就有分界',
      );
      expect(
        _itemOf(launch, 'windowBackground'),
        '@color/app_background',
        reason: 'v31 的 windowBackground 也要一起改，否则低版本对齐、12+ 不对齐',
      );
      expect(
        _itemOf(launch, 'windowSplashScreenAnimatedIcon'),
        '@drawable/launch_icon_none',
        reason: '不指定空图标时，系统会拿应用图标画一枚 160dp 的小标志；'
            '应用首帧现在没有任何标志，那枚图标是凭空多出来的',
      );
      expect(
        _parentOf(launch),
        contains('Theme.Light'),
        reason: '同上：浅底要深色状态栏图标',
      );
    });

    test('app_background 是浅色，别改回深色', () {
      final xml = _body('$_resDir/values/colors.xml');
      final m = RegExp(
        r'<color\s+name="app_background"\s*>\s*(#[0-9A-Fa-f]{6,8})\s*</color>',
      ).firstMatch(xml);
      expect(m, isNotNull, reason: 'colors.xml 里找不到 app_background');

      final c = _parseHex(m!.group(1)!);
      expect(
        c.computeLuminance(),
        greaterThan(0.8),
        reason: '窗口底色必须与浅色主界面接近。改深了就是「点开图标先黑一下」，'
            '比原来偶发的一帧白闪更显眼',
      );
    });
  });

  group('空图标占位', () {
    test('launch_icon_none 确实画不出东西', () {
      final body = _body('$_resDir/drawable/launch_icon_none.xml');
      expect(body.contains('<path'), isFalse, reason: '出现 path 就等于把图标加回来了');
      expect(
        body.contains('@mipmap') || body.contains('@drawable/'),
        isFalse,
        reason: '空图标不该引用位图或其它 drawable',
      );
    });
  });

  group('启动页资源已彻底移除（不留死链）', () {
    test('launch_background.xml 与 splash_icon_none.xml 都不在了', () {
      for (final rel in const [
        'drawable/launch_background.xml',
        'drawable-v21/launch_background.xml',
        'drawable/splash_icon_none.xml',
      ]) {
        expect(
          File('$_resDir/$rel').existsSync(),
          isFalse,
          reason: '$rel 还能被 old 引用找到，说明删除不彻底',
        );
      }
    });

    test('res 与清单里所有资源引用都能解析', () {
      // 收集已定义的资源 —— 文件型（drawable/mipmap）。
      //
      // 注意要收 **png/webp**：`mipmap-anydpi-v26/ic_launcher.xml` 引用的
      // `@mipmap/ic_launcher_foreground` 就只以 png 形式存在于各密度目录，
      // 只收 .xml 会把正常的图标引用误判成死链（第一版就是这么红的）。
      final defined = <String>{};
      for (final e in Directory(_resDir).listSync(recursive: true)) {
        if (e is! File) continue;
        final rel = e.path
            .replaceAll('\\', '/')
            .split('$_resDir/')
            .last; // 如 drawable/launch_icon_none.xml、mipmap-hdpi/ic_launcher.png
        final dir = rel.split('/').first; // drawable / mipmap-anydpi-v26 / values
        if (dir.startsWith('values')) continue; // 值资源在下面单独收

        final type = dir.split('-').first; // drawable-v21 → drawable
        final name = rel.split('/').last.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
        defined.add('$type/$name');
      }

      // 值资源单独收一遍（跨 values / values-night / values-v31）
      final valueNames = <String>{};
      for (final e in Directory(_resDir).listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.xml')) continue;
        if (!e.path.replaceAll('\\', '/').contains('/values')) continue;
        for (final m in RegExp(
          r'<(?:color|string|style|dimen|bool|integer)\s+name="([^"]+)"',
        ).allMatches(_body(e.path))) {
          valueNames.add(m.group(1)!);
        }
      }

      // 扫引用：清单 + 所有 res xml
      final files = <String>[_manifest];
      for (final e in Directory(_resDir).listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.xml')) files.add(e.path);
      }

      final dangling = <String>[];
      for (final f in files) {
        final body = _body(f);
        for (final m in RegExp(
          r'@(drawable|mipmap|color|string|style)/([A-Za-z0-9_.]+)',
        ).allMatches(body)) {
          final type = m.group(1)!;
          final name = m.group(2)!;
          final ok = (type == 'color' ||
                  type == 'string' ||
                  type == 'style' ||
                  type == 'dimen' ||
                  type == 'bool' ||
                  type == 'integer')
              ? valueNames.contains(name)
              : defined.contains('$type/$name');
          if (!ok) dangling.add('$f → @$type/$name');
        }
      }

      expect(
        dangling,
        isEmpty,
        reason: '存在解析不到的资源引用（构建期才会报错的死链）：\n${dangling.join('\n')}',
      );
    });
  });
}
