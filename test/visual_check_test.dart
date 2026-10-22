// 视觉自检：把图标库与品牌标志渲染成 PNG，人工核对图形是否正确。
//
// 为什么需要：SVG 路径解析器是手写的，圆弧、紧凑标志位（`011.3`）、
// evenodd 填充这些地方出错时，代码层面看不出来，只有真的画出来才能发现。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/brand_paths.dart';
import 'package:ledger/design/icons.dart';
import 'package:ledger/design/svg_path.dart';

const _ink = Color(0xFF14161A);
const _over = Color(0xFFA3231A);
const _ink3 = Color(0xFF9AA0A8);

Future<void> _save(ui.Image image, String path) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('已输出 $path  (${image.width}x${image.height})');
}

void _label(Canvas canvas, String text, Offset at, {double size = 10}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: size, color: _ink3),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 120);
  tp.paint(canvas, at);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('渲染全部线稿图标', () async {
    final names = kIcons.keys.toList();
    final overflow = <String>[];
    const cols = 6;
    const cell = 104.0;
    final rows = (names.length / cols).ceil();
    final w = cols * cell;
    final h = rows * cell;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    for (var i = 0; i < names.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final cx = col * cell + cell / 2;
      final cy = row * cell + cell / 2 - 8;

      // 逐个尺寸验证：解析出来的图形是否落在 24x24 视图框内
      final path = lineIconPath(names[i]);
      final b = path.getBounds();
      expect(b.isEmpty, isFalse, reason: '${names[i]} 解析为空路径');

      // 原型 svg 根元素默认 overflow:hidden，超出视图框的部分会被裁掉。
      // 这里只记录（不判错），渲染时 LineIcon 会做同样的裁剪。
      if (b.left < -0.2 || b.top < -0.2 || b.right > 24.2 || b.bottom > 24.2) {
        overflow.add('${names[i]}  $b');
      }
      // 但不应超出得离谱——超出过多说明路径解析出错
      expect(b.left, greaterThan(-9.0), reason: '${names[i]} 左越界过多 $b');
      expect(b.top, greaterThan(-9.0), reason: '${names[i]} 上越界过多 $b');
      expect(b.right, lessThan(33.0), reason: '${names[i]} 右越界过多 $b');
      expect(b.bottom, lessThan(33.0), reason: '${names[i]} 下越界过多 $b');

      // 画 48px 版本
      const iconSize = 48.0;
      canvas.save();
      canvas.translate(cx - iconSize / 2, cy - iconSize / 2);
      canvas.scale(iconSize / 24.0);
      // 与 LineIcon 一致：裁到 24×24 视图框
      canvas.clipRect(const Rect.fromLTWH(0, 0, 24, 24));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _ink
          ..isAntiAlias = true,
      );
      canvas.restore();

      _label(canvas, names[i], Offset(col * cell + 8, row * cell + cell - 20));
    }

    final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    await _save(image, 'build/visual/icon_check.png');

    // ignore: avoid_print
    print('共 ${names.length} 个图标；超出 24×24 视图框（原型同样会裁剪）的有：');
    if (overflow.isEmpty) {
      // ignore: avoid_print
      print('  （无）');
    } else {
      for (final line in overflow) {
        // ignore: avoid_print
        print('  $line');
      }
    }
  });

  test('渲染品牌标志（原尺寸 + 小尺寸）', () async {
    final body = parseSvgPath(kMarkPath, fillType: PathFillType.evenOdd);
    final flame = parseSvgPath(kFlamePath, fillType: PathFillType.evenOdd);

    // 自检：路径长度必须与源文件一致，防止被误改
    expect(kMarkPath.length, kMarkPathLength);
    expect(kFlamePath.length, kFlamePathLength);

    const bigH = 420.0;
    final bigW = bigH * kMarkViewBoxW / kMarkViewBoxH;
    const smallH = 96.0;
    final smallW = smallH * kMarkViewBoxW / kMarkViewBoxH;
    const gap = 40.0;

    final w = bigW + gap + smallW + gap * 2;
    final h = bigH + gap * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // 大图
    canvas.save();
    canvas.translate(gap, gap);
    canvas.scale(bigW / kMarkViewBoxW, bigH / kMarkViewBoxH);
    canvas.translate(-kMarkViewBoxX, -kMarkViewBoxY);
    canvas.drawPath(
      body,
      Paint()
        ..color = _ink
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      flame,
      Paint()
        ..color = _over
        ..isAntiAlias = true,
    );
    canvas.restore();

    // 小图（验证缩小后眼睛的白区是否仍然可见 = evenodd 生效）
    final sx = gap + bigW + gap;
    canvas.save();
    canvas.translate(sx, gap);
    canvas.scale(smallW / kMarkViewBoxW, smallH / kMarkViewBoxH);
    canvas.translate(-kMarkViewBoxX, -kMarkViewBoxY);
    canvas.drawPath(
      body,
      Paint()
        ..color = _ink
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      flame,
      Paint()
        ..color = _over
        ..isAntiAlias = true,
    );
    canvas.restore();

    final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    await _save(image, 'build/visual/brand_check.png');
  });
}
