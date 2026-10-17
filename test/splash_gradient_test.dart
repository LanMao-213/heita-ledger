// 启动页渐变方案对比渲染。
//
// 为什么单独做这个测试：渐变是靠肉眼判断的东西，代码里写 #1C2028 → #0A0C0F
// 根本看不出好不好看。这里把 4 个方案按真实屏比例渲染成一张对比图。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/brand_paths.dart';
import 'package:ledger/design/svg_path.dart';

/// 原型 `启动页.html` 的屏尺寸与「D · 留白 88%」参数
const _vW = 455.0, _vH = 944.0; // 标志 viewBox
const _vX = 9.0, _vY = 5.0;

const _screenW = 390.0;
const _screenH = 844.0;
const _markWidthRatio = 0.88; // 用户选定的 D 方案：标志宽 = 屏宽 88%

const _redDark = Color(0xFFE8493A); // 深色底上的火焰红

Future<void> _loadFont() async {
  for (final path in [r'C:\Windows\Fonts\Deng.ttf', r'C:\Windows\Fonts\simhei.ttf']) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final l = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
    await l.load();
    return;
  }
}

void _label(Canvas c, String text, Offset at, double size, Color color,
    {FontWeight w = FontWeight.w400}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      // 必须显式指定 family：flutter_test 默认用 Ahem 字体（全是方块），
      // 只有点名 'Roboto'（已被 _loadFont 换成等线）才能显示中文。
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: w,
        letterSpacing: 0.1,
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, at);
}

/// 一个方案的背景画法
class _Variant {
  const _Variant({
    required this.name,
    required this.note,
    this.linear,
    this.radial,
    this.base,
    this.glow,
  });

  final String name;
  final String note;
  final LinearGradient? linear;
  final RadialGradient? radial;
  final Color? base;
  /// 额外的红色柔光：颜色 + 中心点（相对屏坐标）+ 半径
  final (Color, Offset, double)? glow;
}

final _variants = <_Variant>[
  // 对照组：当前的纯色深底
  const _Variant(
    name: 'A · 纯深色',
    note: '现状基准，无渐变',
    base: Color(0xFF14161A),
  ),
  const _Variant(
    name: 'B · 极暗对角',
    note: '左上 #252A34 → 右下 #090A0D',
    base: Color(0xFF14161A),
    linear: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF252A34), Color(0xFF090A0D)],
    ),
  ),
  const _Variant(
    name: 'C · 中心聚光',
    note: '中心 #2C323E → 四周 #07080B',
    radial: RadialGradient(
      center: Alignment(0, -0.12),
      radius: 0.95,
      colors: [Color(0xFF2C323E), Color(0xFF07080B)],
    ),
  ),
  const _Variant(
    name: 'D · 暗红微光',
    note: '暖调深底 + 火焰色 14% 柔光',
    base: Color(0xFF0C0D11),
    radial: RadialGradient(
      center: Alignment(0, 0.02),
      radius: 1.0,
      colors: [Color(0xFF17141A), Color(0xFF070809)],
    ),
    glow: (Color(0x24E8493A), Offset(0, -0.02), 0.30),
  ),
];

void main() {
  test('渲染启动页渐变方案对比图', () async {
    await _loadFont();

    final body = parseSvgPath(kMarkPath, fillType: PathFillType.evenOdd);
    final flame = parseSvgPath(kFlamePath, fillType: PathFillType.evenOdd);

    const thumbW = 208.0;
    final k = thumbW / _screenW;
    final thumbH = _screenH * k;
    const gap = 26.0;
    const padX = 34.0;
    const top = 58.0;
    const bottomLabel = 46.0;

    final totalW = padX * 2 + thumbW * 4 + gap * 3;
    final totalH = top + thumbH + bottomLabel;

    const dpr = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);

    // 舞台底色（浅），让深色屏边界清晰
    canvas.drawRect(Rect.fromLTWH(0, 0, totalW, totalH),
        Paint()..color = const Color(0xFFECEEF1));

    _label(canvas, '启动页渐变方案 · 深色底（D 留白 88%）',
        const Offset(padX, 22), 15, const Color(0xFF14161A),
        w: FontWeight.w500);
    _label(canvas, '标志白色 #FFFFFF · 火焰 #E8493A', const Offset(padX, 42), 11.5,
        const Color(0xFF7B8390));

    for (var i = 0; i < _variants.length; i++) {
      final v = _variants[i];
      final x = padX + i * (thumbW + gap);
      const y = top;
      final screen = Rect.fromLTWH(x, y, thumbW, thumbH);

      canvas.save();
      canvas.clipRect(screen);

      // 底色
      if (v.base != null) {
        canvas.drawRect(screen, Paint()..color = v.base!);
      }
      if (v.linear != null) {
        canvas.drawRect(screen, Paint()..shader = v.linear!.createShader(screen));
      }
      if (v.radial != null) {
        canvas.drawRect(screen, Paint()..shader = v.radial!.createShader(screen));
      }
      // 红色柔光
      if (v.glow != null) {
        final (color, centerRel, radiusRel) = v.glow!;
        final center = Offset(
          x + thumbW * (0.5 + centerRel.dx / 2),
          y + thumbH * (0.5 + centerRel.dy / 2),
        );
        final radius = thumbW * radiusRel;
        canvas.drawRect(
          screen,
          Paint()
            ..shader = RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ).createShader(Rect.fromCircle(center: center, radius: radius)),
        );
      }

      // 标志：宽 = 屏宽 88%
      final markW = thumbW * _markWidthRatio;
      final markH = markW * _vH / _vW;
      canvas.save();
      canvas.translate(x + (thumbW - markW) / 2, y + (thumbH - markH) / 2);
      canvas.scale(markW / _vW, markH / _vH);
      canvas.translate(-_vX, -_vY);
      canvas.drawPath(body, Paint()..color = const Color(0xFFFFFFFF)..isAntiAlias = true);
      canvas.drawPath(flame, Paint()..color = _redDark..isAntiAlias = true);
      canvas.restore();

      canvas.restore();

      // 外框，区分屏与屏
      canvas.drawRect(
        screen,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0x22000000),
      );

      // 标签
      _label(canvas, v.name, Offset(x, y + thumbH + 12), 13,
          const Color(0xFF14161A), w: FontWeight.w500);
      _label(canvas, v.note, Offset(x, y + thumbH + 30), 11,
          const Color(0xFF7B8390));
    }

    final image =
        await recorder.endRecording().toImage((totalW * dpr).toInt(), (totalH * dpr).toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/visual')..createSync(recursive: true);
    File('${dir.path}/splash_gradients.png')
        .writeAsBytesSync(data!.buffer.asUint8List());

    // ignore: avoid_print
    print('已输出 build/visual/splash_gradients.png');
  });
}
