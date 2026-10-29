part of '../record_sheet.dart';

// ---------------------------------------------------------------------------
// 数字键盘「让位」的几何：面板顶边为什么能不动
// ---------------------------------------------------------------------------
//
// 这一段是纯计算，**一个 Flutter 类型都不许出现**（`architecture_test` 用源码
// 探针守着）。理由不是洁癖：这条恒等式是整个「抽搐」问题的解，把它埋在三四百行
// widget 树里，改一行只能靠猜；抽成纯函数之后，可以在不 pumpWidget 的情况下
// 用 5dp 的步长逐帧扫过整段动画（见 `test/record_sheet_layout_test.dart`）。
//
// ## 恒等式
//
// 面板的三条边各有来源：
//
//   - 底边 = 屏高 − 输入法高度（`build` 里的 `Padding(bottom: reserved)`）
//   - 高度 = 内容 + 键盘槽高（`Column(mainAxisSize: min)`）
//   - 顶边 = 屏高 − 输入法 − 高度
//
// 代入高度：
//
//   **顶边 = 屏高 − 输入法 − (内容 + 槽高)**
//
// 令 `槽高 = 键盘自然高度 − 输入法`，则输入法这一项被抵掉：
//
//   顶边 = 屏高 − 输入法 − 内容 − 键盘自然高度 + 输入法 = 屏高 − 内容 − 自然高度
//
// 全是常量 → **顶边在输入法升起的整段过程中一动不动**。这就是「输入法从底下把
// 键盘顶出去」那个物理事实的算式版本。
//
// ## 为什么原来会跳
//
// 1.6.0 之前这里有一行 `left < 40 ? 0 : left`：数字键盘剩不到一排键时整块收掉。
// 它是这条恒等式上**唯一的分段点** —— 一旦分段，`槽高` 就不再跟着输入法连续变，
// 恒等式在跨过 `left = 40` 的那一帧失效，顶边当场跳 40dp（实测 177.5 → 217.5）。
//
// 那行代码的动机是**视觉**的：别留一排被切了一半的键贴在输入法上沿。但它在
// **布局**层归零来达成视觉目的，代价是把面板顶边也一起挪了。正确的分工是：
// 布局层保持连续（槽高就是 `left`），碎边交给视觉层溶掉（见 [KeypadSlot.shatterFade]）。

/// 碎边渐隐带的高度。
///
/// 输入法完全升起时槽里还剩 `自然高度 − 输入法高度`（典型 324 − 300 = 24dp）：
/// 那是第一排键被切下来的一条。把这条边溶进卡面，用的是和可滚动区底部
/// `_moreBelow` 完全一样的手法 —— 同一个问题（被裁掉的一条看起来像画坏了）
/// 就该用同一个答案，否则用户会看到两种「消失」。
///
/// 24 不是新数字：它就是典型的碎边尺寸本身。取「碎边多高就溶多高」，
/// 碎边更长时（矮屏、矮键）也只溶最靠下的这一截，不去动上面能读的键。
const kKeypadShatterFade = 24.0;

/// `hardCut` 档的门限（见 [KeypadYield.hardCut]）。
const kHardCutResidual = 24.0;

/// 数字键盘让位的两种策略。
///
/// 默认 [continuous]。另一档是**逃生阀**：真机上如果碎边溶不掉（比如某些输入法
/// 自带一条不透明的高光边，渐隐被它挡住），运营/评测说「宁可它跳过一下也别露
/// 半排键」，那么把 [kKeypadYield] 改成 [hardCut] 即可退回旧行为，**不用改任何
/// 其它代码**（连测试都跟着这个常量分支，见 `note_keyboard_test.dart`）。
///
/// 为什么不直接做成动画：`viewInsets` 是逐帧变化的，任何 150~200ms 的独立动画
/// 每一帧都会被重启一次，最后只会把「1 帧的跳」换成「150ms 的移」，而且永远追不
/// 上键盘 —— 1.4.1 和 1.5.0 各踩过一次，理由写在 `build` 里那段注释。
///
/// 为什么不按可用高度比例分配：比例系数只要不是精确的 −1，`槽高` 就不再 1:1
/// 抵消输入法，顶边照样会动，只是动得更慢。
enum KeypadYield {
  /// 槽高 = 键盘自然高度 − 输入法高度，连续变化；碎边靠渐隐溶掉。
  continuous,

  /// 剩余高度不足 [kHardCutResidual] 时整块收掉（1.6.0 之前的行为）。
  hardCut,
}

/// 当前的让位策略。**这是唯一的开关** —— 它是逃生阀，别在别处再开一个。
const kKeypadYield = KeypadYield.continuous;

/// 一次让位计算的结果。
///
/// 三个数就是面板顶边的全部输入：槽高变了、或被剪掉的高度变了，顶边就会动。
/// 所以「顶边不动」= `leftover == slot`，也就是 [topOffset] 为 0。
class KeypadSlot {
  const KeypadSlot({
    required this.slot,
    required this.topOffset,
    required this.naturalHeight,
    required this.leftover,
  });

  /// 键盘槽的高度：键盘真正露在外面的部分（含被渐隐溶掉的碎边）。
  final double slot;

  /// 面板顶边相对「键盘完全收起」时的位移。
  ///
  /// 0 = 顶边没动（这正是 [KeypadYield.continuous] 恒成立的结论）。
  /// 非 0 只可能来自一次硬切：切掉多少，顶边就往下掉多少。
  final double topOffset;

  /// 键盘的自然高度（`CalcKeypad.heightOf(keyH)`），常量。
  final double naturalHeight;

  /// 输入法吃掉之前，键盘还剩的高度（未做硬切）。
  final double leftover;

  /// 被剪掉的高度：0 表示键盘完整露出。
  double get cutHeight => naturalHeight - slot;

  /// 整块键盘是否露在外面（槽高为 0 时调用方连分隔线都不该画）。
  bool get visible => slot > 0;

  /// 是否留着一排被切了一半的键（碎边）。
  ///
  /// 0.5dp 的容差是为了浮点：`324 − 324` 在 double 上不保证正好是 0。
  bool get clipped => cutHeight > 0.5;

  /// 碎边渐隐带的高度：没有碎边时是 0（**满键盘时绝不能渐隐**，
  /// 那会把「0 / . / 确认」这排真键溶掉）。
  double get shatterFade {
    if (!clipped) return 0;
    return slot < kKeypadShatterFade ? slot : kKeypadShatterFade;
  }

  /// 面板总高 = 内容 + 槽高。给测试量「内容高度跟不跟得住键盘」用。
  double totalWith(double contentHeight) => contentHeight + slot;

  /// 面板顶边。这就是上面那条恒等式，写成函数是为了只有一份。
  ///
  /// [contentHeight] 是面板里除键盘槽以外的部分（头部、模板条、页签、金额、
  /// 信息区），[keyboardInset] 是输入法高度，[screenHeight] 是屏幕逻辑高度。
  double topAt({
    required double screenHeight,
    required double keyboardInset,
    required double contentHeight,
  }) => screenHeight - keyboardInset - totalWith(contentHeight);
}

/// 算一次让位几何。
///
/// [keypadNaturalHeight] 是键盘的**自然高度**（屏幕高度的函数，一次录入里是常量）；
/// [keyboardInset] 是输入法当前高度（逐帧变化）。
///
/// 端点必须成立（测试钉着）：`keyboardInset == 0` → `slot == 自然高度`；
/// `keyboardInset ≥ 自然高度` → `slot == 0`。
KeypadSlot solveKeypadSlot({
  required double keypadNaturalHeight,
  required double keyboardInset,
  KeypadYield yieldMode = kKeypadYield,
}) {
  // 自然高度小于等于 0 只可能是没初始化好；当成「没有键盘槽」，不要除以它。
  final full = keypadNaturalHeight > 0 ? keypadNaturalHeight : 0.0;
  final inset = keyboardInset > 0 ? keyboardInset : 0.0;
  // 输入法吃掉之后还剩多少。超出自然高度就落在 0（少数机型的输入法比键盘高）。
  final leftover = (full - inset).clamp(0.0, full).toDouble();

  final double slot;
  switch (yieldMode) {
    case KeypadYield.continuous:
      // 核心：**就是 leftover**。这里一旦出现分段，恒等式当场失效。
      slot = leftover;
    case KeypadYield.hardCut:
      // 逃生阀：剩不到一条碎边就整块收掉，门限取典型碎边尺寸本身
      // （原来是 40dp —— 那个数大到把「一排半截的键」和「三条完整的键」
      // 一起判成碎边，代价是顶边跳得更远）。
      slot = leftover <= kHardCutResidual ? 0.0 : leftover;
  }

  return KeypadSlot(
    slot: slot,
    // 顶边位移 = 「本可以露出来的」减去「实际露出来的」。continuous 档恒为 0；
    // hardCut 档切掉多少，顶边就往下掉多少。
    topOffset: leftover - slot,
    naturalHeight: full,
    leftover: leftover,
  );
}
