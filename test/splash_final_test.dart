// 启动页最终效果渲染。
//
// 与 splash_gradient_test.dart 的区别：那个是手绘的「方案对比」，
// 这个是**真实 Widget 树**按真机尺寸渲染，能反映实际布局、动画终态和配色。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart' show kAppName;
import 'package:ledger/design/icons.dart';
import 'package:ledger/design/splash_spec.dart';
import 'package:ledger/design/tokens.dart';

final _key = GlobalKey();

Future<void> _loadFont() async {
  for (final p in [
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ]) {
    final f = File(p);
    if (!f.existsSync()) continue;
    final l = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer),
        ),
      );
    await l.load();
    return;
  }
}

Widget _splash(double markH) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: RepaintBoundary(
    key: _key,
    child: Scaffold(
      backgroundColor: kSplashEdge,
      body: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: kSplashGradient),
          child: Center(
            child: BrandMark(
              height: markH,
              fg: const Color(0xFFFFFFFF),
              flameColor: C.overD,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('渲染启动页最终效果（390×844 @2x）', (tester) async {
    await _loadFont();
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const screen = Size(390, 844);
    // 尺寸从 design/splash_spec.dart 取，不再抄一遍公式 ——
    // 抄公式的版本漏掉了屏高钳制，改实现它不会红。
    final markH = splashMarkHeight(screen);

    await tester.pumpWidget(_splash(markH));
    // 等淡入 + 缩放动画走完，截到的是终态
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(BrandMark), findsOneWidget);
    // 布局不该溢出
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final boundary =
          _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/visual')..createSync(recursive: true);
      File('${dir.path}/splash_final.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });

    // 方案①「D · 留白 88%」：19.5:9 的屏上钳制不介入，宽度应恰好是 88%
    final size = tester.getSize(find.byType(BrandMark));
    expect(size.width / screen.width, closeTo(kSplashMarkWidthRatio, 0.005));
    expect(size.height, closeTo(markH, 0.5));
    // ignore: avoid_print
    print(
      '$kAppName 启动页 —— 标志 ${size.width.toStringAsFixed(1)} × '
      '${size.height.toStringAsFixed(1)}，占屏宽 '
      '${(size.width / screen.width * 100).toStringAsFixed(1)}%',
    );
  });
}
