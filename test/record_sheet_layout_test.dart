// 「记一笔」面板里数字键盘的让位几何 —— 纯函数级，**不 pumpWidget**。
//
// 为什么要单独一组纯函数测试：`record_note_layout_test` 那种逐帧量 rect 的测试
// 只能扫有限的几帧（60 帧已经要 3 秒），而且一旦红了很难说清是「算错了」还是
// 「widget 树没搭对」。这里把算式单独钉住，两个层次各管一段：
//
//   - 本文件：`solveKeypadSlot` 的输出（槽高、顶边位移）必须在**任意步长**下连续；
//   - record_note_layout_test：真把面板搭起来，量「记一笔」标题的 y 坐标。
//
// ## 三条不变量（少一条都测不出「抽搐」）
//
// 1. **槽高**单调非增，相邻差 ≤ 步长 × 1.05（斜率 ≤ 1，不许硬切）；
// 2. **内容总高**（内容 + 槽高）单调非增，相邻差同样有界 —— 它必须跟着键盘
//    1:1 变化。曾经想钉「内容总高变化 ≤ 2dp」是错的：键盘走 4dp，槽高就该减
//    4dp，4 > 2。内容高度**本来就该**跟着键盘走；
// 3. **顶边**（用户唯一真正看见的东西）|Δ| ≤ 2dp —— 这条才是「抽搐」的定义。
//
// 端点也必须成立：输入法为 0 时键盘完整露出，输入法高过键盘时槽高为 0。
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/widgets/record_sheet.dart';

/// 面板里除键盘槽以外的部分。取一个实测值量级（390×844 屏、无详情字段时
/// 实测约 341.5dp）。它的绝对值不影响任何一条不变量 —— 三条都是**差分**判定，
/// 这正是它们比「钉一个魔法数」结实的地方。
const _contentH = 341.5;

const _screenH = 844.0;

/// 扫描步长。必须 ≤ 4dp：真的碎一个 24dp 的硬切步长若大于它就可能被跳过。
const _step = 4.0;

/// 键盘自然高度：56 键高（无详情）、52 键高（有详情）、38 键高（矮屏下限）。
const _naturals = <double>[
  324, // CalcKeypad.heightOf(56)
  304, // CalcKeypad.heightOf(52)
  234, // CalcKeypad.heightOf(38)：矮屏
];

/// 从 0 扫到「比自然高度还高 40dp」——输入端点的两种情况都要覆盖。
List<double> _insets(double natural) {
  final out = <double>[];
  for (var inset = 0.0; inset <= natural + 40; inset += _step) {
    out.add(inset);
  }
  return out;
}

List<KeypadSlot> _ramp(double natural, {KeypadYield mode = kKeypadYield}) => [
  for (final inset in _insets(natural))
    solveKeypadSlot(
      keypadNaturalHeight: natural,
      keyboardInset: inset,
      yieldMode: mode,
    ),
];

void main() {
  group('端点', () {
    test('输入法收起时，键盘完整露出', () {
      for (final natural in _naturals) {
        final slot = solveKeypadSlot(
          keypadNaturalHeight: natural,
          keyboardInset: 0,
        );
        expect(slot.slot, natural, reason: '自然高度 $natural 的键盘没有完整露出');
        expect(slot.topOffset, 0);
        expect(slot.cutHeight, 0);
        expect(slot.clipped, isFalse, reason: '满键盘不该被当成碎边');
        expect(slot.shatterFade, 0, reason: '满键盘绝不能渐隐，会溶掉真键');
      }
    });

    test('输入法高过键盘时，槽高归零（不是负数）', () {
      for (final natural in _naturals) {
        for (final inset in [natural, natural + 0.5, natural + 40, 500.0]) {
          final slot = solveKeypadSlot(
            keypadNaturalHeight: natural,
            keyboardInset: inset,
          );
          expect(slot.slot, 0, reason: '自然高度 $natural、输入法 $inset 时槽高应为 0');
          expect(slot.visible, isFalse);
          expect(slot.topOffset, 0, reason: '槽高归零是自然结论，不该带来顶边位移');
        }
      }
    });

    test('自然高度没初始化好时不崩、也不除零', () {
      final slot = solveKeypadSlot(
        keypadNaturalHeight: 0,
        keyboardInset: 0,
      );
      expect(slot.slot, 0);
      expect(slot.visible, isFalse);
    });

    test('负的输入法高度（异常值）被当成 0', () {
      final slot = solveKeypadSlot(
        keypadNaturalHeight: 324,
        keyboardInset: -50,
      );
      expect(slot.slot, 324);
    });
  });

  group('不变量（continuous，4dp 步长）', () {
    test('槽高单调非增，且斜率不超过 1', () {
      for (final natural in _naturals) {
        final ramp = _ramp(natural);
        for (var i = 1; i < ramp.length; i++) {
          final d = ramp[i].slot - ramp[i - 1].slot;
          expect(
            d,
            lessThanOrEqualTo(kEpsilon),
            reason: '自然高度 $natural、第 $i 步槽高从 ${ramp[i - 1].slot} 涨到 '
                '${ramp[i].slot} —— 槽高必须随输入法升高而单调缩小',
          );
          expect(
            d.abs(),
            lessThanOrEqualTo(_step * 1.05),
            reason: '自然高度 $natural、第 $i 步槽高跳了 ${d.abs()}dp（步长只有 '
                '$_step）—— 这就是硬切',
          );
        }
      }
    });

    test('内容总高跟着键盘 1:1 变化，不突变', () {
      for (final natural in _naturals) {
        final ramp = _ramp(natural);
        for (var i = 1; i < ramp.length; i++) {
          final d = ramp[i].totalWith(_contentH) - ramp[i - 1].totalWith(_contentH);
          expect(d, lessThanOrEqualTo(kEpsilon), reason: '自然高度 $natural、第 $i 步内容总高反而变大');
          expect(
            d.abs(),
            lessThanOrEqualTo(_step * 1.05),
            reason: '自然高度 $natural、第 $i 步内容总高跳了 ${d.abs()}dp',
          );
        }
      }
    });

    test('顶边一动不动（|Δ| ≤ 2dp）—— 这条才是「抽搐」的定义', () {
      for (final natural in _naturals) {
        // 只扫到键盘自然高度为止：这一段是恒等式成立的区间。
        // 输入法比键盘还高时（少数机型的表情面板能到 400+），面板底边继续
        // 被推上去，而它已经没有可让的东西了 —— 顶边必然跟着上移。那不是
        // 「抽搐」，是「输入法比键盘高」，见下一条测试。
        final insets = <double>[
          for (var inset = 0.0; inset <= natural; inset += _step) inset,
        ];
        final tops = <double>[
          for (final inset in insets)
            solveKeypadSlot(
              keypadNaturalHeight: natural,
              keyboardInset: inset,
            ).topAt(
              screenHeight: _screenH,
              keyboardInset: inset,
              contentHeight: _contentH,
            ),
        ];
        final rest = tops.first;
        for (var i = 1; i < tops.length; i++) {
          expect(
            (tops[i] - tops[i - 1]).abs(),
            lessThanOrEqualTo(2),
            reason: '自然高度 $natural、第 $i 步（输入法 ${insets[i]}dp）顶边从 '
                '${tops[i - 1]} 跳到 ${tops[i]}',
          );
        }
        for (var i = 0; i < tops.length; i++) {
          expect(
            (tops[i] - rest).abs(),
            lessThanOrEqualTo(2),
            reason: '自然高度 $natural、第 $i 步顶边偏离静止位 '
                '${(tops[i] - rest).abs().toStringAsFixed(1)}dp',
          );
        }
      }
    });

    test('输入法比键盘还高时：面板被继续推上去，但仍然是连续的', () {
      const natural = 324.0;
      final insets = <double>[
        for (var inset = natural; inset <= natural + 40; inset += _step) inset,
      ];
      var prev = solveKeypadSlot(
        keypadNaturalHeight: natural,
        keyboardInset: insets.first,
      ).topAt(
        screenHeight: _screenH,
        keyboardInset: insets.first,
        contentHeight: _contentH,
      );
      for (var i = 1; i < insets.length; i++) {
        final slot = solveKeypadSlot(
          keypadNaturalHeight: natural,
          keyboardInset: insets[i],
        );
        expect(slot.slot, 0, reason: '键盘已经没有可让的高度了');
        final top = slot.topAt(
          screenHeight: _screenH,
          keyboardInset: insets[i],
          contentHeight: _contentH,
        );
        // 顶边只会**向上**移，且每步移动量不超过一步输入法的高度（1:1）。
        expect(top, lessThanOrEqualTo(prev + kEpsilon));
        expect(
          (top - prev).abs(),
          lessThanOrEqualTo(_step * 1.05),
          reason: '第 $i 步（输入法 ${insets[i]}dp）顶边跳了 ${(top - prev).abs()}dp',
        );
        prev = top;
      }
    });
  });

  group('碎边与渐隐', () {
    test('碎边出现时渐隐带恰好盖住碎边，且不超过 24dp', () {
      // 输入法完全升起（典型 300dp）时槽高剩 24dp —— 最典型的碎边现场。
      final slot = solveKeypadSlot(
        keypadNaturalHeight: 324,
        keyboardInset: 300,
      );
      expect(slot.slot, 24);
      expect(slot.clipped, isTrue);
      expect(slot.shatterFade, 24, reason: '24dp 的碎边应当整条溶掉');
    });

    test('碎边比渐隐带还短时，渐隐带跟着缩短（不画出槽外）', () {
      final slot = solveKeypadSlot(
        keypadNaturalHeight: 324,
        keyboardInset: 316,
      );
      expect(slot.slot, 8);
      expect(slot.shatterFade, 8);
    });

    test('剪掉得多时（剪进整排键里）渐隐带封顶在 24dp，不去溶能读的键', () {
      final slot = solveKeypadSlot(
        keypadNaturalHeight: 324,
        keyboardInset: 180,
      );
      expect(slot.slot, 144);
      expect(slot.clipped, isTrue);
      expect(slot.shatterFade, 24);
    });
  });

  group('逃生阀 hardCut', () {
    test('剩不到一条碎边就整块收掉，门限用碎边尺寸本身而不是 40', () {
      // 门限上下一格：29 → 还在，25 → 还在，24 → 收掉
      expect(
        solveKeypadSlot(
          keypadNaturalHeight: 324,
          keyboardInset: 295,
          yieldMode: KeypadYield.hardCut,
        ).slot,
        29,
      );
      expect(
        solveKeypadSlot(
          keypadNaturalHeight: 324,
          keyboardInset: 300,
          yieldMode: KeypadYield.hardCut,
        ).slot,
        0,
        reason: '24dp 的碎边在硬切档应当整块收掉',
      );
    });

    test('硬切档的顶边位移正好等于被切掉的高度（这就是它跳的量）', () {
      final slot = solveKeypadSlot(
        keypadNaturalHeight: 324,
        keyboardInset: 300,
        yieldMode: KeypadYield.hardCut,
      );
      expect(slot.topOffset, 24);
      expect(
        slot.topOffset,
        lessThanOrEqualTo(kHardCutResidual),
        reason: '硬切档的代价必须被门限封住 —— 旧的门限是 40，那一下顶边跳 40',
      );
    });

    test('硬切档不会把整排完整的键一起切掉', () {
      // 剩 60dp（还剩一整排键）时不该收
      expect(
        solveKeypadSlot(
          keypadNaturalHeight: 324,
          keyboardInset: 264,
          yieldMode: KeypadYield.hardCut,
        ).slot,
        60,
      );
    });
  });

  group('开关本身', () {
    test('默认档是 continuous（碎边交给视觉层，布局层不分段）', () {
      expect(
        kKeypadYield,
        KeypadYield.continuous,
        reason: 'hardCut 是逃生阀，默认必须是连续档；改这里要先看 '
            'note_keyboard_test 的碎边断言',
      );
    });
  });
}

/// 浮点容差：算出来的「不变」在 double 上可能是 1e-15 量级的正数。
const kEpsilon = 1e-9;
