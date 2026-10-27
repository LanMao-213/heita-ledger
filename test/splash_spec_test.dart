// 启动页尺寸的守卫。
//
// 为什么单独一个文件而不是并进 `splash_final_test.dart`：那个要渲染、要加载
// 系统字体、还要写 png，跑一次几百毫秒；这几条是纯算术，几十微秒。改
// `splash_spec.dart` 时先跑这个，能立刻知道有没有动到方案①的比例。
//
// 钉住的东西只有一件：**「D · 留白 88%」这个选择本身**。它不会因为任何
// 一次重构而变红，只会在有人改了比例时变红 —— 那正是需要有人停下来问
// 「设计定了吗」的时刻。
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
}
