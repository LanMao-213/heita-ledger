// 月度趋势折线的组件级自检 + 截图。
//
// 覆盖两个最容易出错的地方：
//   1. 空数据 —— 不能崩、不能画 NaN 坐标（全域兜底）；
//   2. 断月 —— 没有数据的月份必须断开，不能画成 0（画成 0 等于说「这个月
//      一分没花」，和「这个月没记账」是两个完全不同的事实）。
//
// 曾经这里还有一个 `BudgetCompareBars`（预算 vs 实际对比条）：统计页合并之后
// 已经没有任何页面用它了，只剩这组测试在测它 —— 只被测试使用的 widget 会
// 制造虚假覆盖率（它天天绿，但用户永远看不到它）。1.6.0 删掉它和它的 5 条用例。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/widgets/charts.dart';

final _shotKey = GlobalKey();

Future<void> _loadChineseFont() async {
  for (final path in [r'C:\Windows\Fonts\Deng.ttf', r'C:\Windows\Fonts\simhei.ttf']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer),
        ),
      );
    await loader.load();
    return;
  }
}

Future<void> _shot(WidgetTester tester, String path) async {
  await tester.binding.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('截图 $path (${image.width}x${image.height})');
  });
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    // 页面底画在 RepaintBoundary **里面**：否则截出来的是一张透明底，
    // 白/黑全看查看器，图和字的对比度也就没法判断。
    body: RepaintBoundary(
      key: _shotKey,
      child: ColoredBox(
        color: C.bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(_loadChineseFont);

  group('月度折线', () {
    testWidgets('全空：给一句人话，不画线', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MonthTrendLine(
            points: [
              (label: '5月', value: null),
              (label: '6月', value: null),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('这段时间没有记录'), findsOneWidget);
    });

    testWidgets('中间空月断开：仍然渲染，不崩', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MonthTrendLine(
            points: [
              (label: '4月', value: 100000),
              (label: '5月', value: null),
              (label: '6月', value: 300000),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('5月'), findsOneWidget);
    });

    testWidgets('单点 / 全 0 都不产生 NaN 坐标', (tester) async {
      await tester.pumpWidget(
        _wrap(const MonthTrendLine(points: [(label: '6月', value: 0)])),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('截图：月度折线', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: S.lg),
          child: MonthTrendLine(
            points: [
              (label: '1月', value: 320000),
              (label: '2月', value: 410000),
              (label: '3月', value: null),
              (label: '4月', value: 280000),
              (label: '5月', value: 520000),
              (label: '6月', value: 390000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _shot(tester, 'build/visual/chart_month_trend.png');
  });
}
