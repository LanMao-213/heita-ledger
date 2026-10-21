import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/repo/stats_repo.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/ui/pages/stats/daily_bars.dart';

import '../support/pixel_probe.dart';
import '../support/ui_fixture.dart';

/// 每日柱：**区间内每一天都占一格**、零值不画柱（像素全背景色）、点某天回传那一天。
void main() {
  const Period october = Period(
    from: LocalDate(2026, 10, 1),
    to: LocalDate(2026, 10, 31),
  );

  List<DailyTotal> rows() => <DailyTotal>[
    const DailyTotal(date: '2026-10-01', expenseCents: 1000, incomeCents: 0),
    const DailyTotal(date: '2026-10-05', expenseCents: 2000, incomeCents: 0),
  ];

  test('② 区间内每一天都占一格（31 天就是 31 格，没数据的那天是 0）', () {
    final List<DailyBarCell> cells = buildDailyCells(
      fillDailyRange(period: october, rows: rows()),
    );
    expect(cells.length, 31);
    expect(cells.first.date.iso, '2026-10-01');
    expect(cells.last.date.iso, '2026-10-31');
    expect(cells[0].cents, 1000);
    expect(cells[4].cents, 2000);
    // 2 号没有账 → 0，而且它**还是占着一格**
    expect(cells[1].cents, 0);
    expect(cells[1].isZero, isTrue);
  });

  test('② 零值的格 ratio 恒为 0（不会因为最大值为 0 而除出 NaN）', () {
    final List<DailyBarCell> cells = buildDailyCells(
      fillDailyRange(
        period: const Period(
          from: LocalDate(2026, 10, 1),
          to: LocalDate(2026, 10, 3),
        ),
        rows: const <DailyTotal>[],
      ),
    );
    expect(cells.every((DailyBarCell c) => c.ratio == 0), isTrue);
    expect(cells.every((DailyBarCell c) => c.ratio.isNaN), isFalse);
  });

  test('② 比例以区间内最大值为分母（最大值那格 = 1）', () {
    final List<DailyBarCell> cells = buildDailyCells(
      fillDailyRange(period: october, rows: rows()),
    );
    expect(cells[0].ratio, closeTo(0.5, 1e-9));
    expect(cells[4].ratio, closeTo(1.0, 1e-9));
  });

  testWidgets('② 像素：零值那天全是背景色（不是 1px 的线）', (
    WidgetTester tester,
  ) async {
    final List<DailyBarCell> cells = buildDailyCells(
      fillDailyRange(period: october, rows: rows()),
    );
    final AppPalette pal = paletteInk();
    final DailyBarsPainter painter = DailyBarsPainter(
      cells: cells,
      barColor: pal.accent,
      bgColor: pal.bg,
      baselineColor: pal.line,
    );

    // 31 格、宽 310 → 每格 10；第 2 格（x≈15）完全没数据
    const Size size = Size(310, 88);
    final int zeroPixel = (await tester.runAsync(
      () => pixelOf(painter, size, const Offset(15, 40)),
    ))!;
    expect(zeroPixel, argbOf(pal.bg), reason: '零值不画柱 → 该处就是背景色');

    // 第 1 格（x≈5）有 1000 分 → accent
    final int barPixel = (await tester.runAsync(
      () => pixelOf(painter, size, const Offset(5, 80)),
    ))!;
    expect(barPixel, argbOf(pal.accent));
  });

  testWidgets('② 点某一天 → 回传那一天（不再关心点到哪一像素高）', (
    WidgetTester tester,
  ) async {
    final List<DailyBarCell> cells = buildDailyCells(
      fillDailyRange(
        period: const Period(
          from: LocalDate(2026, 10, 1),
          to: LocalDate(2026, 10, 3),
        ),
        rows: rows(),
      ),
    );
    LocalDate? picked;
    await UiHarness().pump(
      tester,
      host(
        SizedBox(
          width: 300,
          child: DailyBars(
            cells: cells,
            onPick: (LocalDate d) => picked = d,
          ),
        ),
      ),
    );

    final Rect box = tester.getRect(find.byKey(const ValueKey<String>('daily-bars')));
    // 点第 2 格（3 格宽 300 → 每格 100，第 2 格中心 150）
    await tester.tapAt(Offset(box.left + 150, box.center.dy));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.iso, '2026-10-02');
  });

  test('② 命中索引：左侧越界取第一格、右侧越界取最后一格', () {
    expect(DailyBars.indexAt(-5, 310, 31), 0);
    expect(DailyBars.indexAt(0, 310, 31), 0);
    expect(DailyBars.indexAt(309, 310, 31), 30);
    expect(DailyBars.indexAt(999, 310, 31), 30);
    expect(DailyBars.indexAt(15, 310, 31), 1);
  });

  test('② 每格宽度相等（31 格不会因为某天没账就挤在一起）', () {
    const double width = 310;
    const int count = 31;
    final double cell = width / count;
    expect(DailyBars.indexAt(cell * 0.5, width, count), 0);
    expect(DailyBars.indexAt(cell * 1.5, width, count), 1);
    expect(DailyBars.indexAt(cell * 29.5, width, count), 29);
  });

  testWidgets('横轴字只写首 / 中 / 末三天', (WidgetTester tester) async {
    final List<DailyBarCell> cells = buildDailyCells(
      fillDailyRange(period: october, rows: rows()),
    );
    await UiHarness().pump(tester, host(DailyAxisLabels(cells: cells)));
    expect(find.text('10/1'), findsOneWidget);
    expect(find.text('10/31'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
  });
}
