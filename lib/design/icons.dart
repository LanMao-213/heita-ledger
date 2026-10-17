import 'package:flutter/material.dart';

import 'brand_paths.dart';
import 'svg_path.dart';
import 'tokens.dart';

/// 一笔线稿图标库 —— 路径数据从原型 `记账App/index.html` 原样照搬，
/// 未经任何改动，保证图形与设计稿 1:1 一致。
///
/// 统一参数：24×24 视图框、1.5 线宽（视图框单位）、圆头圆角、**无填充**。
const Map<String, String> kIcons = {
  // ---- 支出分类 ----
  'food': r'<path d="M5 13h14a7 7 0 0 1-14 0z"/><path d="M9.5 9.6V6.4M12 9.6V5.4M14.5 9.6V6.4"/>',
  'transport': r'<rect x="5" y="3.6" width="14" height="13" rx="3"/><path d="M5 11h14"/><circle cx="9" cy="13.6" r="1"/><circle cx="15" cy="13.6" r="1"/><path d="M8.6 16.6L7 20.2M15.4 16.6L17 20.2"/>',
  'shopping': r'<path d="M5.6 8h12.8l-1.1 11.4a1.5 1.5 0 0 1-1.5 1.4H8.2a1.5 1.5 0 0 1-1.5-1.4z"/><path d="M9 8V6.3a3 3 0 0 1 6 0V8"/>',
  'home': r'<path d="M4 10.8L12 4.4l8 6.4"/><path d="M6.4 9.7V20h11.2V9.7"/><path d="M10.2 20v-5.2h3.6V20"/>',
  'fun': r'<path d="M9.5 17.2V5.9l8.5-1.9v10.8"/><circle cx="7" cy="17.2" r="2.5"/><circle cx="15.5" cy="14.8" r="2.5"/>',
  'medical': r'<rect x="3.5" y="7.5" width="17" height="12" rx="2.5"/><path d="M9 7.5V6a1.8 1.8 0 0 1 1.8-1.8h2.4A1.8 1.8 0 0 1 15 6v1.5"/><path d="M12 11.2v5.4M9.3 13.9h5.4"/>',
  'study': r'<path d="M12 7.4S9.8 5.2 5 5.2v11.2c4.8 0 7 2.2 7 2.2s2.2-2.2 7-2.2V5.2c-4.8 0-7 2.2-7 2.2z"/><path d="M12 7.4v11.2"/>',
  'comm': r'<rect x="7" y="2.9" width="10" height="18.2" rx="2.6"/><path d="M10.8 18.1h2.4"/>',
  'gift': r'<rect x="4" y="8.6" width="16" height="11.9" rx="1.6"/><path d="M3 8.6h18M12 8.6v11.9"/><path d="M12 8.6C11 5.9 9.3 4.4 7.8 5.3 6.3 6.2 7.6 8.6 12 8.6zM12 8.6c1-2.7 2.7-4.2 4.2-3.3 1.5.9.2 3.3-4.2 3.3z"/>',
  'more': r'<circle cx="6" cy="12" r="1.25"/><circle cx="12" cy="12" r="1.25"/><circle cx="18" cy="12" r="1.25"/>',

  // ---- 收入分类 ----
  'salary': r'<rect x="2.8" y="6.6" width="18.4" height="10.8" rx="2"/><circle cx="12" cy="12" r="2.6"/><path d="M6.4 9.9v.01M17.6 14.1v.01"/>',
  'bonus': r'<circle cx="12" cy="9.3" r="5.5"/><path d="M8.6 13.8L7 20.5l5-2.6 5 2.6-1.6-6.7"/>',
  'parttime': r'<rect x="3" y="7.2" width="18" height="12.3" rx="2"/><path d="M9 7.2V5.8a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v1.4"/><path d="M3 12.3h18"/>',
  'invest': r'<path d="M3.5 16.6l5-5 3.5 3.5 8-8"/><path d="M15 7.1h5v5"/>',
  'redpacket': r'<rect x="5" y="3.6" width="14" height="16.8" rx="2.4"/><path d="M5 3.6a7 7 0 0 1 14 0"/><circle cx="12" cy="11.2" r="1.8"/>',

  // ---- 设置 / 功能 ----
  'upload': r'<path d="M12 15.5V4.6"/><path d="M7.6 8.6L12 4.2l4.4 4.4"/><path d="M4.4 15.4v2.8a2 2 0 0 0 2 2h11.2a2 2 0 0 0 2-2v-2.8"/>',
  'download': r'<path d="M12 4.5v10.9"/><path d="M7.6 11.2L12 15.6l4.4-4.4"/><path d="M4.4 15.4v2.8a2 2 0 0 0 2 2h11.2a2 2 0 0 0 2-2v-2.8"/>',
  'lock': r'<rect x="4.6" y="10.4" width="14.8" height="9.8" rx="2.2"/><path d="M8.2 10.4V7.6a3.8 3.8 0 0 1 7.6 0v2.8"/>',
  'tag': r'<path d="M11.4 3.6H20v8.6l-8.6 8.6-8.6-8.6z"/><circle cx="16" cy="7.6" r="1.4"/>',
  'bell': r'<path d="M6.4 10.2a5.6 5.6 0 1 1 11.2 0c0 4 1.6 5.4 1.6 5.4H4.8s1.6-1.4 1.6-5.4z"/><path d="M10.2 18.6a2 2 0 0 0 3.6 0"/>',
  'coin': r'<circle cx="12" cy="12" r="8.4"/><path d="M12 7.4v9.2M14.6 9.4H10.3a1.9 1.9 0 0 0 0 3.8h3.4a1.9 1.9 0 0 1 0 3.8H9.4"/>',
  'moon': r'<path d="M20.2 14.2A8.6 8.6 0 0 1 9.8 3.8a8.8 8.8 0 1 0 10.4 10.4z"/>',
  'doc': r'<path d="M6.4 4.6a2 2 0 0 1 2-2h5.4l4.8 4.8v11.6a2 2 0 0 1-2 2H8.4a2 2 0 0 1-2-2z"/><path d="M13.6 2.6v5h5"/><path d="M9.6 12.6h6M9.6 16h4"/>',
  'info': r'<circle cx="12" cy="12" r="8.6"/><path d="M12 11.2v5.2M12 7.9v.01"/>',

  // ---- 计划页与储蓄目标 ----
  'target': r'<circle cx="12" cy="12" r="8.4"/><circle cx="12" cy="12" r="4.2"/><circle cx="12" cy="12" r=".9"/>',
  'plane': r'<path d="M20.8 3.2L2.8 10.9l6.6 2.6 2.6 6.6z"/><path d="M20.8 3.2l-11.4 10.3"/>',
  'laptop': r'<rect x="4.2" y="5.2" width="15.6" height="10.6" rx="2"/><path d="M2.6 19h18.8"/>',
  'flag': r'<path d="M6 20.6V3.6"/><path d="M6 4.3h11.4l-2.2 4 2.2 4H6"/>',
  'car': r'<rect x="3.6" y="9.6" width="16.8" height="6.8" rx="2.4"/><path d="M6.2 9.6l1.5-3a1.5 1.5 0 011.3-.8h6a1.5 1.5 0 011.3.8l1.5 3"/><circle cx="7.6" cy="16.4" r="1.2"/><circle cx="16.4" cy="16.4" r="1.2"/>',
  'wallet': r'<path d="M3.6 8.4a2 2 0 012-2h11.4a2 2 0 012 2v8.2a2 2 0 01-2 2H5.6a2 2 0 01-2-2z"/><path d="M3.6 11.6h16.8"/><circle cx="15.6" cy="15" r="1"/>',

  // ---- 设置区 ----
  'book': r'<rect x="4.5" y="3" width="15" height="18" rx="2"/><path d="M8.5 3v18"/><path d="M12 8h4M12 12h4"/>',
  'card': r'<rect x="2.8" y="5.5" width="18.4" height="13" rx="2.5"/><path d="M2.8 10h18.4"/><path d="M6.5 14.5h3"/>',
  'tpl': r'<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="M3.5 9.5h17M9.5 9.5v10"/>',
  'rec': r'<path d="M20.5 12a8.5 8.5 0 11-2.6-6.1"/><path d="M20.5 3.4v5.2h-5.2"/><path d="M12 7.6V12l3 1.9"/>',

  // ---- 底部导航（原型里是内联 SVG，不在 ICONS 表中，此处补齐）----
  'list': r'<path d="M4 6h16M4 12h16M4 18h10"/>',
  'pie': r'<path d="M12 3.2a8.8 8.8 0 108.8 8.8H12z"/><path d="M14.3 3.6a8.4 8.4 0 016.4 6.4h-6.4z"/>',
  'person': r'<circle cx="12" cy="8.5" r="3.6"/><path d="M4.8 20a7.2 7.2 0 0114.4 0"/>',
  'plus': r'<path d="M12 5.5v13M5.5 12h13"/>',
};

/// 已解析路径的缓存。图标会在列表里被反复构建，解析一次即可。
final Map<String, Path> _pathCache = {};

Path lineIconPath(String name) => _pathCache.putIfAbsent(
      name,
      () => parseSvgFragment(kIcons[name] ?? kIcons['more']!),
    );

/// 线稿图标。
///
/// [size] 是渲染尺寸；[strokeWidth] 是**视图框单位**下的线宽（默认 1.5）。
/// [scaleStroke] 为 true 时线宽随 size 等比缩放 —— 这与原型里
/// `<svg width="20" viewBox="0 0 24 24" stroke-width="1.5">` 的表现完全一致。
/// 需要「大图标但线不变粗」时传 false。
class LineIcon extends StatelessWidget {
  const LineIcon(
    this.name, {
    super.key,
    this.size = 20,
    required this.color,
    this.strokeWidth = 1.5,
    this.scaleStroke = true,
  });

  final String name;
  final double size;
  final Color color;
  final double strokeWidth;
  final bool scaleStroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LineIconPainter(
          path: lineIconPath(name),
          color: color,
          strokeWidth: scaleStroke ? strokeWidth : strokeWidth * 24.0 / size,
        ),
      ),
    );
  }
}

class _LineIconPainter extends CustomPainter {
  _LineIconPainter({
    required this.path,
    required this.color,
    required this.strokeWidth,
  });

  final Path path;
  final Color color;

  /// **视图框单位**下的线宽：画布已按 size/24 缩放，这里直接就是该值。
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    canvas.save();
    canvas.scale(s);
    // 原型里 svg 根元素默认 overflow:hidden，超出 24×24 视图框的部分会被裁掉
    // （例如 redpacket 的顶部半圆）。这里保持同样行为，保证图形不走样。
    canvas.clipRect(const Rect.fromLTWH(0, 0, 24, 24));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LineIconPainter old) =>
      old.path != path ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// 品牌标志。视图框 455×944，主体实心、火焰叠红。
///
/// ⚠️ 必须用 [PathFillType.evenOdd]：眼睛处嵌套了 4 层轮廓
/// （外杏仁 → 白区 → 眼环 → 环内白区），nonzero 会把眼内白区填实。
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    required this.height,
    this.fg = C.ink,
    this.flameColor = C.over,
  });

  final double height;
  final Color fg;
  final Color flameColor;

  @override
  Widget build(BuildContext context) {
    const w = 455.0, h = 944.0;
    return SizedBox(
      width: height * w / h,
      height: height,
      child: CustomPaint(
        painter: _BrandMarkPainter(fg: fg, flameColor: flameColor),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter({required this.fg, required this.flameColor});

  final Color fg;
  final Color flameColor;

  static final Path _body =
      parseSvgPath(kMarkPath, fillType: PathFillType.evenOdd);
  static final Path _flame =
      parseSvgPath(kFlamePath, fillType: PathFillType.evenOdd);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // 视图框 9,5,437,932 → 缩放到目标尺寸
    canvas.scale(size.width / 455.0, size.height / 944.0);
    canvas.translate(-9, -5);
    canvas.drawPath(_body, Paint()..color = fg..isAntiAlias = true);
    canvas.drawPath(_flame, Paint()..color = flameColor..isAntiAlias = true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter old) =>
      old.fg != fg || old.flameColor != flameColor;
}
