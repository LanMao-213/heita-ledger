import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/data/repo/stats_repo.dart';
import 'package:heita_ledger/theme/palette.dart';
import 'package:heita_ledger/ui/pages/stats/trend_bars.dart';

import '../support/db_fixture.dart';
import '../support/pixel_probe.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 近 6 段双柱：零值不画柱、支出实心 accent / 收入 ink4、共用基线、
/// 逐段数据由**1 条合并查询**取得。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  List<Period> sixPeriods() => <Period>[
    for (int i = 5; i >= 0; i--)
      Period.shiftCycle(
        const Period(
          from: LocalDate(2026, 10, 1),
          to: LocalDate(2026, 10, 31),
        ),
        -i,
        1,
      ),
  ];

  List<TrendSegment> segments() => <TrendSegment>[
    const TrendSegment(
      period: Period(
        from: LocalDate(2026, 5, 1),
        to: LocalDate(2026, 5, 31),
      ),
      expenseCents: 0,
      incomeCents: 0,
    ),
    for (int i = 1; i <= 5; i++)
      TrendSegment(
        period: Period.cycleRange(LocalDate(2026, 5 + i, 1), 1),
        expenseCents: i * 1000,
        incomeCents: i * 2000,
      ),
  ];

  testWidgets('④ 像素：零值那段两根柱都不画（全是背景色）', (
    WidgetTester tester,
  ) async {
    final AppPalette pal = paletteInk();
    final TrendBarsPainter painter = TrendBarsPainter(
      segments: segments(),
      expenseColor: pal.accent,
      incomeColor: pal.ink4,
      bgColor: pal.bg,
      baselineColor: pal.line,
    );
    // 6 段、宽 300 → 每段 50；第 1 段（x 0..50）全是 0
    const Size size = Size(300, 96);
    final int px = (await tester.runAsync(
      () => pixelOf(painter, size, const Offset(10, 40)),
    ))!;
    expect(px, argbOf(pal.bg), reason: '零值不画柱');
  });

  testWidgets('④ 像素：支出实心 accent、收入 ink4', (WidgetTester tester) async {
    final AppPalette pal = paletteInk();
    final TrendBarsPainter painter = TrendBarsPainter(
      segments: segments(),
      expenseColor: pal.accent,
      incomeColor: pal.ink4,
      bgColor: pal.bg,
      baselineColor: pal.line,
    );
    const Size size = Size(300, 96);
    // 第 2 段（x 50..100）：支出 1000 / 收入 2000，最大值 2000 → 支出柱高 48
    final int expense = (await tester.runAsync(
      () => pixelOf(painter, size, const Offset(60, 90)),
    ))!;
    final int income = (await tester.runAsync(
      () => pixelOf(painter, size, const Offset(80, 90)),
    ))!;
    expect(expense, argbOf(pal.accent));
    expect(income, argbOf(pal.ink4));
  });

  testWidgets('④ 像素：共用基线（两组柱的底边都在同一行）', (
    WidgetTester tester,
  ) async {
    final AppPalette pal = paletteInk();
    final TrendBarsPainter painter = TrendBarsPainter(
      segments: segments(),
      expenseColor: pal.accent,
      incomeColor: pal.ink4,
      bgColor: pal.bg,
      baselineColor: pal.line,
    );
    const Size size = Size(300, 96);
    // 支出柱与收入柱在同一 y 上都还是各自的色（说明底边对齐，没有高低差）
    for (final Offset at in const <Offset>[
      Offset(60, 92),
      Offset(80, 92),
      Offset(110, 92),
      Offset(130, 92),
    ]) {
      final int px = (await tester.runAsync(
        () => pixelOf(painter, size, at),
      ))!;
      expect(
        px,
        isNot(argbOf(pal.bg)),
        reason: '$at 应该还落在柱子上（共用基线 = 底边在同一个 y）',
      );
    }
  });

  testWidgets('④ 段标签写期首月（近 6 段）', (WidgetTester tester) async {
    await UiHarness().pump(
      tester,
      host(SizedBox(width: 320, child: TrendBars(segments: segments()))),
    );
    expect(find.text('5月'), findsOneWidget);
    expect(find.text('10月'), findsOneWidget);
  });

  testWidgets('图例：支出 / 收入两枚色块', (WidgetTester tester) async {
    await UiHarness().pump(tester, host(const TrendLegend()));
    expect(find.text('支出'), findsOneWidget);
    expect(find.text('收入'), findsOneWidget);
  });

  test('④ 逐段数据由 1 条合并查询取得（查询次数 ≤ 1）', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    // 只有 2 段有数据，其余 4 段应为 0（不是缺失）
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 1000,
        date: const LocalDate(2026, 9, 3),
        periodStart: const LocalDate(2026, 9, 1),
        accountId: acc,
      ),
      cycleStartDay: 1,
    );
    await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        type: TxnType.income,
        amountCents: 5000,
        date: const LocalDate(2026, 10, 3),
        periodStart: const LocalDate(2026, 10, 1),
        accountId: acc,
      ),
      cycleStartDay: 1,
    );

    final List<TrendSegment> out = await Repo.stats.trendTotals(
      ledgerId: ledger,
      periods: sixPeriods(),
    );

    expect(
      StatsRepo.lastTrendQueryCount,
      1,
      reason: '6 段必须一条 GROUP BY 拿回来，不许 per-period 循环查',
    );
    expect(out.length, 6);
    expect(out.last.period.from.iso, '2026-10-01');
    expect(out.last.incomeCents, 5000);
    expect(out.last.expenseCents, 0);
    expect(out[4].expenseCents, 1000);
    expect(out[2].expenseCents, 0, reason: '没数据的段补 0，不是缺一段');
  });
}
