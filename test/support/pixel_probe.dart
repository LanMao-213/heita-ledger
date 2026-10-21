import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// 把一个 `CustomPainter` 画到 `PictureRecorder` 上，再读回某个像素（ARGB）。
///
/// **为什么不走 widget 树**：图表页四张图全是自绘的，走 widget 树只能断言
/// 「有这个 widget」；「第 1 扇区是 chart[0] 那个色」「零值那天真的是背景色」
/// 这类口径只有读像素才测得出来。
///
/// 用法（必须在 `testWidgets` 里、外面裹 `tester.runAsync`）：
/// ```dart
/// final int px = (await tester.runAsync(
///   () => pixelOf(painter, const Size(200, 200), const Offset(100, 10)),
/// ))!;
/// ```
Future<int> pixelOf(CustomPainter painter, Size size, Offset at) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final ui.Picture picture = recorder.endRecording();
  final int w = size.width.round();
  final int h = size.height.round();
  final ui.Image image = await picture.toImage(w, h);
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  image.dispose();
  picture.dispose();
  if (data == null) return 0;

  final int x = at.dx.round().clamp(0, w - 1);
  final int y = at.dy.round().clamp(0, h - 1);
  final int off = (y * w + x) * 4;
  final int r = data.getUint8(off);
  final int g = data.getUint8(off + 1);
  final int b = data.getUint8(off + 2);
  final int a = data.getUint8(off + 3);
  return (a << 24) | (r << 16) | (g << 8) | b;
}

/// 颜色 → ARGB int（与 [pixelOf] 的返回同构，直接比）。
int argbOf(Color color) {
  final int a = (color.a * 255).round();
  final int r = (color.r * 255).round();
  final int g = (color.g * 255).round();
  final int b = (color.b * 255).round();
  return (a << 24) | (r << 16) | (g << 8) | b;
}

/// 极坐标取点：以 [center] 为心、半径 [radius]、角度 [angle]（0 = 3 点方向）。
Offset polar(Offset center, double radius, double angle) => Offset(
  center.dx + radius * math.cos(angle),
  center.dy + radius * math.sin(angle),
);
