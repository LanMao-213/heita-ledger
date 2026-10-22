import 'package:flutter/material.dart';

/// 1 物理像素对应的逻辑宽度。
///
/// 分隔线写 `thickness: 1` 时，在 3x 屏上实际画的是 3 个物理像素，比 iOS 的
/// separator 粗三倍 —— 列表里十几条线叠起来就是「不够精致」的主要来源之一。
/// 按 `1 / devicePixelRatio` 取宽才是真正的 1 物理像素（0.33pt @3x）。
///
/// 用 [MediaQuery.maybeOf] 而不是 `MediaQuery.of`：有些 widget 测试没有
/// MediaQuery 祖先，`of` 会直接抛异常把测试打断，这里宁可退回一个默认值。
double hairlineOf(BuildContext context) =>
    1.0 /
    ((MediaQuery.maybeOf(context)?.devicePixelRatio ?? 3.0).clamp(1.0, 8.0));
