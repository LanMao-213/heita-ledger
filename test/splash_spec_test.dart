// 启动页尺寸的守卫。
//
// 为什么单独一个文件而不是并进 `splash_final_test.dart`：那个要渲染、要加载
// 系统字体、还要写 png，跑一次几百毫秒；这几条是纯算术，几十微秒。改
// `splash_spec.dart` 时先跑这个，能立刻知道有没有动到方案①的比例。
//
// 钉住的东西只有一件：**「D · 留白 88%」这个选择本身**。它不会因为任何
// 一次重构而变红，只会在有人改了比例时变红 —— 那正是需要有人停下来问
// 「设计定了吗」的时刻。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/splash_spec.dart';

void main() {
  group('启动页尺寸（方案① D · 留白 88%）', () {
    test('常量就是定稿的那两个数', () {
      // 这两个值来自 docs/设计资产/启动页.html 的 D 档（唯一打 ✓ 的那档）。
      // 要改必须同时改设计资产并在 CHANGELOG 记一笔，所以这里写死。
      expect(kSplashMarkWidthRatio, 0.88, reason: '留白 88% 是定稿，不是可调参数');
      expect(kSplashMarkHeightCap, 0.92, reason: '屏高上限 92%');
      expect(kSplashMarkHeightPerWidth, closeTo(2.0747, 0.001));
    });

    test('19.5:9 屏（390×844）：钳制不介入，宽恰好 88%、高约 84%', () {
      const screen = Size(390, 844);
      final h = splashMarkHeight(screen);

      expect(splashMarkWidthFraction(screen), closeTo(0.88, 0.001));
      expect(h, closeTo(712.0, 0.5));
      expect(h / screen.height, closeTo(0.844, 0.002));
    });

    test('16:9 矮屏（411×731）：先撞屏高上限，宽度退回约 79%', () {
      const screen = Size(411, 731);
      final h = splashMarkHeight(screen);

      // 上限接管：高度精确等于屏高 × 0.92
      expect(h, closeTo(screen.height * kSplashMarkHeightCap, 0.001));
      // 于是宽度到不了 88%，只剩约 79% —— 这是有意为之，不是 bug
      expect(splashMarkWidthFraction(screen), closeTo(0.789, 0.002));
      expect(splashMarkWidthFraction(screen), lessThan(kSplashMarkWidthRatio));
    });

    test('任何屏幕都不会超过屏高 92%', () {
      const screens = [
        Size(320, 568), // 老 iPhone SE
        Size(360, 640), // 16:9 安卓小屏
        Size(390, 844), // 主流 19.5:9
        Size(412, 915), // Pixel 7
        Size(430, 932), // iPhone Pro Max
        Size(673, 841), // 折叠屏展开（接近方形，最容易撑爆）
        Size(800, 1280), // 平板
        Size(1280, 800), // 平板横屏
      ];
      for (final s in screens) {
        final h = splashMarkHeight(s);
        expect(
          h,
          lessThanOrEqualTo(s.height * kSplashMarkHeightCap + 0.001),
          reason: '${s.width.toInt()}×${s.height.toInt()} 上高度超了屏高上限',
        );
        expect(
          h,
          lessThanOrEqualTo(s.width * kSplashMarkWidthRatio * kSplashMarkHeightPerWidth + 0.001),
          reason: '${s.width.toInt()}×${s.height.toInt()} 上宽度超了 88%',
        );
      }
    });

    test('宽高比恒为 455:944 —— 只缩放不拉伸', () {
      for (final s in [const Size(390, 844), const Size(411, 731), const Size(800, 1280)]) {
        final h = splashMarkHeight(s);
        final w = h / kSplashMarkHeightPerWidth;
        expect(w / h, closeTo(455 / 944, 1e-9));
      }
    });
  });

  // 冷启动的第一屏不是 Flutter 画的 —— Android 12+ 由系统 SplashScreen API
  // 接管：只有纯色背景 + 一个尺寸被系统锁死的图标。2026-10-27 的真机截图里，
  // 那个图标只有 159dp（屏高 18%），而 Flutter 首帧的标志是 718dp（屏高 82%），
  // 差 4.51 倍 —— 肉眼看到的是「一个小标志突然放大成一个大标志」。
  //
  // 这两条守卫钉住的是「两屏接得上」这个约束。它们读的是 android/ 下的真实
  // 文件，所以改原生资源也会被拦；这类跨语言漂移没有任何 Dart 类型能约束，
  // 只能靠测试盯着。
  group('原生闪屏与 Flutter 首帧必须接得上', () {
    // 读资源时统一剥掉 XML 注释：几个文件头都写了「不要改回 xxx」之类的警示，
    // 不剥会把警示文字当成真实配置，守卫自己先误报。
    String bodyOf(String rel) => File('android/app/src/main/res/$rel')
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    test('colors.xml 的 splash_background 与 kSplashNativeBackground 同值', () {
      final xml = bodyOf('values/colors.xml');
      final m = RegExp(
        r'<color\s+name="splash_background"\s*>\s*#([0-9A-Fa-f]{6,8})\s*</color>',
      ).firstMatch(xml);
      expect(m, isNotNull, reason: 'colors.xml 里找不到 splash_background');

      var hex = m!.group(1)!.toUpperCase();
      if (hex.length == 6) hex = 'FF$hex'; // 省略 alpha 时补 FF
      final dart = kSplashNativeBackground
          .toARGB32()
          .toRadixString(16)
          .toUpperCase()
          .padLeft(8, '0');

      expect(
        dart,
        hex,
        reason: '原生闪屏底色与 Dart 常量不一致：闪屏是 #$hex，'
            'kSplashNativeBackground 是 #$dart。冷启动会在两屏之间闪一次色差',
      );
    });

    test('Android 12+ 启动主题不画图标（画了就会出现「小标志跳大标志」）', () {
      final xml = bodyOf('values-v31/styles.xml');
      final m = RegExp(
        r'windowSplashScreenAnimatedIcon"\s*>\s*([^<]+?)\s*<',
      ).firstMatch(xml);

      expect(m, isNotNull, reason: 'v31 启动主题里没有 windowSplashScreenAnimatedIcon');
      expect(
        m!.group(1),
        '@drawable/splash_icon_none',
        reason: '系统闪屏的图标只能画到约 160dp，而 Flutter 首帧是 718dp（差 4.5 倍），'
            '所以这里必须是空图标。改回 @mipmap/… 会把那一跳重新带回来',
      );
    });

    test('splash_icon_none 确实是空的', () {
      final body = bodyOf('drawable/splash_icon_none.xml');
      expect(
        body.contains('<path'),
        isFalse,
        reason: '「空图标」里出现 path 就会真的画出东西，等于把图标加回来了',
      );
      expect(
        body.contains('@mipmap') || body.contains('@drawable/'),
        isFalse,
        reason: '空图标不该引用任何位图 / 其它 drawable',
      );
    });
  });
}
