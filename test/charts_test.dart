// 两种新图型（P2）的组件级自检 + 截图。
//
// 覆盖三个最容易出错的地方：
//   1. 空数据 —— 不能崩、不能画 NaN 坐标（全域兜底）；
//   2. 颜色语义 —— 红**只**给超支那一段，正常进度不得出现红；
//   3. 断月 —— 没有数据的月份必须断开，不能画成 0。
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

List<({String name, int spentCents, int budgetCents})> _rows() => const [
  (name: '餐饮', spentCents: 150000, budgetCents: 100000), // 超支
  (name: '交通', spentCents: 20000, budgetCents: 50000),
  (name: '日用', spentCents: 0, budgetCents: 30000),
];

void main() {
  setUpAll(_loadChineseFont);

  group('预算 vs 实际', () {
    testWidgets('空数据：整块不占位，不崩', (tester) async {
      await tester.pumpWidget(_wrap(const BudgetCompareBars(rows: [])));
      expect(tester.takeException(), isNull);
      expect(find.text('餐饮'), findsNothing);
    });

    testWidgets('没设预算的分类被过滤掉（没有对比对象）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const BudgetCompareBars(
            rows: [
              (name: '餐饮', spentCents: 100, budgetCents: 0),
              (name: '交通', spentCents: 100, budgetCents: 1000),
            ],
          ),
        ),
      );
      expect(find.text('餐饮'), findsNothing);
      expect(find.text('交通'), findsOneWidget);
    });

    testWidgets('红只出现在超支那一段，且只有一段', (tester) async {
      await tester.pumpWidget(_wrap(BudgetCompareBars(rows: _rows())));
      final over = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((b) => b.color == C.over)
          .length;
      expect(over, 1, reason: '两行正常 + 一行超支 → 红色只能有 1 段');
    });

    testWidgets('超支行金额文案带「/」，且没有布局溢出', (tester) async {
      await tester.pumpWidget(_wrap(BudgetCompareBars(rows: _rows())));
      expect(tester.takeException(), isNull);
      expect(find.textContaining(' / '), findsNWidgets(3));
    });

    testWidgets('超过 maxRows 只显示前几行', (tester) async {
      await tester.pumpWidget(
        _wrap(
          BudgetCompareBars(
            maxRows: 2,
            rows: [
              for (var i = 0; i < 6; i++)
                (name: '类$i', spentCents: 1000 * (i + 1), budgetCents: 5000),
            ],
          ),
        ),
      );
      final ink = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((b) => b.color == C.ink)
          .length;
      expect(ink, 2);
    });
  });

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

  testWidgets('截图：两种图型', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BudgetCompareBars(rows: _rows()),
            const SizedBox(height: 20),
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
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _shot(tester, 'build/visual/chart_budget_trend.png');
  });
}
