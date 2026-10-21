import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/repo/stats_repo.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/ui/pages/stats/pie_chart.dart';

import '../support/pixel_probe.dart';
import '../support/ui_fixture.dart';

/// 饼图：像素断言（第 1 扇区色）、角度口径（Σ=2π）、合计 ≤0 不参与、分母兜底。
void main() {
  final List<Color> chart = paletteInk().chart;

  CategoryStat stat(int id, String name, int cents) =>
      CategoryStat(categoryId: id, name: name, icon: 'more', cents: cents);

  List<PieSlice> threeSlices() => buildPieSlices(
    stats: <CategoryStat>[
      stat(1, '餐饮', 5000),
      stat(2, '交通', 3000),
      stat(3, '购物', 2000),
    ],
    chart: chart,
  );

  const Size size = Size(200, 200);
  const double thickness = 20;
  const Offset center = Offset(100, 100);
  const double radius = 90; // (200 - 20) / 2

  test('① 扇区角之和 == 2π（容差 1e-6）', () {
    final List<PieSlice> slices = threeSlices();
    final double sum = slices.fold<double>(
      0,
      (double a, PieSlice s) => a + s.sweepAngle,
    );
    expect(sum, closeTo(2 * math.pi, 1e-6));
    expect(slices.first.sweepAngle, closeTo(2 * math.pi * 0.5, 1e-9));
  });

  test('① 起始角在 12 点方向（-π/2），顺时针累加', () {
    final List<PieSlice> slices = threeSlices();
    expect(slices.first.startAngle, kPieStartAngle);
    expect(slices.first.startAngle, closeTo(-math.pi / 2, 1e-12));
    expect(
      slices[1].startAngle,
      closeTo(slices[0].startAngle + slices[0].sweepAngle, 1e-12),
    );
  });

  test('① 合计 ≤ 0 的分类不参与（退款退成负数的不占扇区）', () {
    final List<PieSlice> slices = buildPieSlices(
      stats: <CategoryStat>[
        stat(1, '餐饮', 1000),
        stat(2, '退款', 0),
        stat(3, '退货', -500),
      ],
      chart: chart,
    );
    expect(slices.length, 1);
    expect(slices.single.categoryId, 1);
    expect(slices.single.percent, 1);
  });

  test('① total == 0 时没有扇区、也没有 NaN（分母按 1）', () {
    expect(buildPieSlices(stats: const <CategoryStat>[], chart: chart), isEmpty);
    final List<PieSlice> allZero = buildPieSlices(
      stats: <CategoryStat>[stat(1, '餐饮', 0), stat(2, '交通', 0)],
      chart: chart,
    );
    expect(allZero, isEmpty);
    // 有数据时百分比必须有限且落在 0..1
    for (final PieSlice s in threeSlices()) {
      expect(s.percent.isFinite, isTrue);
      expect(s.percent, inInclusiveRange(0, 1));
    }
  });

  testWidgets('① 像素：第 1 扇区起始像素 == pal.chart[0]', (
    WidgetTester tester,
  ) async {
    final List<PieSlice> slices = threeSlices();
    final PiePainter painter = PiePainter(
      slices: slices,
      thickness: thickness,
      trackColor: paletteInk().surfaceAlt,
    );

    // 起始角 + 一个很小偏移（避开扇区边界上的抗锯齿）与中线各取一点
    final Offset atStart = polar(
      center,
      radius,
      slices.first.startAngle + 0.02,
    );
    final Offset atMid = polar(center, radius, slices.first.midAngle);

    final int pStart = (await tester.runAsync(
      () => pixelOf(painter, size, atStart),
    ))!;
    final int pMid = (await tester.runAsync(
      () => pixelOf(painter, size, atMid),
    ))!;

    expect(pStart, argbOf(chart[0]), reason: '第 1 扇区起始像素必须是 chart[0]');
    expect(pMid, argbOf(chart[0]));
  });

  testWidgets('① 像素：第 2 / 第 3 扇区各自取到 chart[1] / chart[2]', (
    WidgetTester tester,
  ) async {
    final List<PieSlice> slices = threeSlices();
    final PiePainter painter = PiePainter(
      slices: slices,
      thickness: thickness,
      trackColor: paletteInk().surfaceAlt,
    );

    final int second = (await tester.runAsync(
      () => pixelOf(
        painter,
        size,
        polar(center, radius, slices[1].midAngle),
      ),
    ))!;
    final int third = (await tester.runAsync(
      () => pixelOf(
        painter,
        size,
        polar(center, radius, slices[2].midAngle),
      ),
    ))!;

    expect(second, argbOf(chart[1]));
    expect(third, argbOf(chart[2]));
  });

  testWidgets('① 像素：圆心是空的（环形而不是实心饼）', (
    WidgetTester tester,
  ) async {
    final PiePainter painter = PiePainter(
      slices: threeSlices(),
      thickness: thickness,
      trackColor: paletteInk().surfaceAlt,
    );
    final int px = (await tester.runAsync(
      () => pixelOf(painter, size, center),
    ))!;
    expect(px, 0, reason: '圆心没画东西 → 完全透明');
  });

  test('颜色按顺序取 chart，超出回卷', () {
    final List<CategoryStat> many = <CategoryStat>[
      for (int i = 0; i < chart.length + 2; i++) stat(i + 1, 'c$i', 100),
    ];
    final List<PieSlice> slices = buildPieSlices(stats: many, chart: chart);
    expect(slices.length, chart.length + 2);
    expect(slices[chart.length].color, chart[0]);
    expect(slices[chart.length + 1].color, chart[1]);
  });

  test('尺寸为 0 时不抛（也不画 NaN）', () {
    final PiePainter painter = PiePainter(
      slices: threeSlices(),
      thickness: thickness,
      trackColor: paletteInk().surfaceAlt,
    );
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    expect(() => painter.paint(canvas, Size.zero), returnsNormally);
    expect(
      () => painter.paint(canvas, const Size(10, 10)),
      returnsNormally,
      reason: '厚度比直径还大时也要直接返回',
    );
    recorder.endRecording().dispose();
  });

  testWidgets('⑥ 骨架：loaded == false 时画 PieSkeleton', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(tester, host(const PieSkeleton()));
    expect(find.byKey(const ValueKey<String>('pie-skeleton')), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
  });

  testWidgets('图例：名字 + 百分比（一位小数）', (WidgetTester tester) async {
    final List<PieSlice> slices = threeSlices();
    await UiHarness().pump(tester, host(PieLegend(slices: slices)));
    expect(find.text('餐饮'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('legend-pct-1')),
      findsOneWidget,
    );
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('30.0%'), findsOneWidget);
  });

  testWidgets('PieChart 渲染 CustomPaint 且中间能放字', (
    WidgetTester tester,
  ) async {
    await UiHarness().pump(
      tester,
      host(
        PieChart(
          slices: threeSlices(),
          centerTop: '支出',
          centerBottom: '1,000.00',
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('支出'), findsOneWidget);
    expect(find.text('1,000.00'), findsOneWidget);
  });
}
