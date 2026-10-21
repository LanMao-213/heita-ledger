import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// 开屏（M01-F06）。
///
/// 渐变参数**必须与 `android/app/src/main/res/drawable*/launch_background.xml` 一致**，
/// 否则冷启动会看到「Android 开屏 → Flutter 开屏」两种底色接不上的跳位：
///
/// | 参数 | 值 |
/// | --- | --- |
/// | 起点色 | `pal.surfaceSunk`（ink 套 `#FAFAFB`） |
/// | 终点色 | `pal.bg`（ink 套 `#FFFFFF`） |
/// | 方向 | 自上而下（`Alignment.topCenter` → `Alignment.bottomCenter`） |
/// | 类型 | linear |
///
/// 首帧必须在**没有任何数据库查询**的情况下画出来（性能预算：冷启动 → 首帧 ≤ 400ms），
/// 所以这里不许读 Store 以外的任何东西，也不许 `await`。
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[pal.surfaceSunk, pal.bg],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('黑塔账本', style: Ts.title.copyWith(color: pal.ink)),
            const SizedBox(height: S.sm),
            Container(width: 24, height: 1, color: pal.lineStrong),
            const SizedBox(height: S.sm),
            Text(
              '本地记账 · 数据不出手机',
              style: Ts.caption.copyWith(color: pal.ink3),
            ),
          ],
        ),
      ),
    );
  }
}
