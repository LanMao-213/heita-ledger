// 精简版 SVG path 解析器
//
// 为什么自己写：原型里的图标是 SVG 路径片段，直接搬进 Flutter 能保证图形
// 100% 不走样（用户明确要求「不要去动外形」）。引入 flutter_svg 会把整个
// SVG 渲染栈带进来，而这里只需要极少一部分能力。
//
// 支持命令：M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z
// ★ 圆弧 A/a 统一转换为三次贝塞尔曲线，从而避开矩阵变换（Path.transform
//   需要 Float64List，且难以按子路径旋转）——椭圆旋转直接在数学里处理。
//
// ★ 为什么用逐字符扫描器而不是正则分词：
//   SVG 允许紧凑写法 `a1.5 1.5 0 011.3-.8`，其中 `011.3` 要拆成
//   flag=0、flag=1、数值=1.3。正则会把 `011.3` 整体当成一个数，导致
//   参数个数对不上、图形解析中断。按语法逐字符读才能正确处理。
import 'dart:math' as math;
import 'dart:ui';

/// 解析 SVG path 的 `d` 属性，返回 [Path]。
///
/// 描摹品牌标志时用到 `fill-rule="evenodd"`（眼睛处嵌套 4 层轮廓），
/// 通过 [fillType] 传入，否则眼内白区会被填实。
Path parseSvgPath(String d, {PathFillType fillType = PathFillType.nonZero}) {
  final builder = _PathBuilder()..path.fillType = fillType;
  builder.run(d);
  return builder.path;
}

/// 把一段 SVG 片段（可含多个 `<path>` / `<circle>` / `<rect>`）合成一个 [Path]。
///
/// 图标库里的图形就是这种片段，例如：
/// `<path d="M5 13h14a7 7 0 0 1-14 0z"/><circle cx="9" cy="13.6" r="1"/>`
Path parseSvgFragment(String fragment) {
  final path = Path()..fillType = PathFillType.nonZero;
  final tagRe = RegExp(
    r'<(path|circle|rect|line|polyline|polygon)\b([^>]*)/?>',
  );
  final attrRe = RegExp(r'([a-zA-Z-]+)\s*=\s*"([^"]*)"');

  for (final tag in tagRe.allMatches(fragment)) {
    final name = tag.group(1)!;
    final attrs = <String, String>{};
    for (final a in attrRe.allMatches(tag.group(2)!)) {
      attrs[a.group(1)!] = a.group(2)!;
    }
    double f(String key, [double fallback = 0]) =>
        double.tryParse(attrs[key]?.trim() ?? '') ?? fallback;

    switch (name) {
      case 'path':
        path.addPath(parseSvgPath(attrs['d'] ?? ''), Offset.zero);
      case 'circle':
        path.addOval(
          Rect.fromCircle(center: Offset(f('cx'), f('cy')), radius: f('r')),
        );
      case 'rect':
        final r = Rect.fromLTWH(f('x'), f('y'), f('width'), f('height'));
        final rx = f('rx');
        path.addRRect(RRect.fromRectAndRadius(r, Radius.circular(rx)));
      case 'line':
        path.moveTo(f('x1'), f('y1'));
        path.lineTo(f('x2'), f('y2'));
      case 'polyline' || 'polygon':
        final nums = RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
            .allMatches(attrs['points'] ?? '')
            .map((m) => double.parse(m.group(0)!))
            .toList();
        for (var i = 0; i + 1 < nums.length; i += 2) {
          if (i == 0) {
            path.moveTo(nums[0], nums[1]);
          } else {
            path.lineTo(nums[i], nums[i + 1]);
          }
        }
        if (name == 'polygon' && nums.length >= 4) path.close();
    }
  }
  return path;
}

// ---------------------------------------------------------------------------

const String _commandChars = 'MmLlHhVvCcSsQqTtAaZz';

/// SVG path 逐字符扫描器，严格按语法读取，处理紧凑写法与指数。
class _SvgScanner {
  _SvgScanner(this.src);

  final String src;
  int i = 0;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  /// 跳过空白与逗号（SVG 里两者等价）
  void _skip() {
    while (i < src.length) {
      final c = src.codeUnitAt(i);
      if (c == 0x20 ||
          c == 0x09 ||
          c == 0x0A ||
          c == 0x0D ||
          c == 0x0C ||
          c == 0x2C) {
        i++;
      } else {
        break;
      }
    }
  }

  /// 若下一个非分隔字符是命令字母，消费并返回它
  String? nextCommand() {
    _skip();
    if (i >= src.length) return null;
    final c = src[i];
    if (_commandChars.contains(c)) {
      i++;
      return c;
    }
    return null;
  }

  bool get hasNumber {
    _skip();
    if (i >= src.length) return false;
    final c = src.codeUnitAt(i);
    return _isDigit(c) || c == 0x2B || c == 0x2D || c == 0x2E;
  }

  double number() {
    _skip();
    final start = i;
    if (i < src.length && (src[i] == '+' || src[i] == '-')) i++;
    while (i < src.length && _isDigit(src.codeUnitAt(i))) {
      i++;
    }
    if (i < src.length && src[i] == '.') {
      i++;
      while (i < src.length && _isDigit(src.codeUnitAt(i))) {
        i++;
      }
    }
    // 指数部分：只有确实跟着数字时才消费，否则回退（例如 `1e` 不是指数）
    if (i < src.length && (src[i] == 'e' || src[i] == 'E')) {
      final save = i;
      i++;
      if (i < src.length && (src[i] == '+' || src[i] == '-')) i++;
      if (i < src.length && _isDigit(src.codeUnitAt(i))) {
        while (i < src.length && _isDigit(src.codeUnitAt(i))) {
          i++;
        }
      } else {
        i = save;
      }
    }
    if (i == start) return 0;

    var text = src.substring(start, i);
    // Dart 的 double.parse 不接受 `.5` / `1.` 这类写法，补齐后再解析
    if (text.startsWith('.')) {
      text = '0$text';
    } else if (text.startsWith('-.') || text.startsWith('+.')) {
      text = '${text[0]}0${text.substring(1)}';
    }
    if (text.endsWith('.')) text = '${text}0';
    return double.tryParse(text) ?? 0;
  }

  /// 弧的 large-arc / sweep 标志位：按 SVG 语法**只能是一位 0 或 1**
  bool flag() {
    _skip();
    if (i < src.length && (src[i] == '0' || src[i] == '1')) {
      final v = src[i] == '1';
      i++;
      return v;
    }
    return number() != 0;
  }
}

class _PathBuilder {
  final Path path = Path();

  double cx = 0, cy = 0; // 当前点
  double sx = 0, sy = 0; // 当前子路径起点（Z 回调用）
  double lastC2x = 0, lastC2y = 0; // 上一个三次曲线的第二控制点（S 反射用）
  double lastQx = 0, lastQy = 0; // 上一个二次曲线的控制点（T 反射用）
  String prevCmd = ''; // 上一条命令（判断能否反射）

  void run(String d) {
    final sc = _SvgScanner(d);
    String? cmd;

    while (true) {
      final before = sc.i;
      final read = sc.nextCommand();
      if (read != null) {
        cmd = read;
      } else {
        // 不是新命令：必须能继续读数值，且已有上一条命令可复用
        if (cmd == null || !sc.hasNumber) break;
      }

      final lower = cmd.toLowerCase();
      // SVG 约定：小写命令 = 相对坐标，大写 = 绝对坐标。
      // 用「命令字符是否等于它自身的大写」来判断，别用 cmd != lower
      // （那样对 h/v/a 这类本身就是小写的命令会得到相反结果）。
      final rel = cmd != cmd.toUpperCase();

      switch (lower) {
        case 'm':
          final x = sc.number(), y = sc.number();
          final px = rel ? cx + x : x;
          final py = rel ? cy + y : y;
          path.moveTo(px, py);
          cx = sx = px;
          cy = sy = py;
          // moveto 之后的连续坐标对按 lineto 处理（SVG 规范）
          cmd = rel ? 'l' : 'L';

        case 'l':
          final x = sc.number(), y = sc.number();
          cx = rel ? cx + x : x;
          cy = rel ? cy + y : y;
          path.lineTo(cx, cy);

        case 'h':
          final x = sc.number();
          cx = rel ? cx + x : x;
          path.lineTo(cx, cy);

        case 'v':
          final y = sc.number();
          cy = rel ? cy + y : y;
          path.lineTo(cx, cy);

        case 'c':
          final x1 = sc.number(), y1 = sc.number();
          final x2 = sc.number(), y2 = sc.number();
          final x = sc.number(), y = sc.number();
          final c1x = rel ? cx + x1 : x1, c1y = rel ? cy + y1 : y1;
          final c2x = rel ? cx + x2 : x2, c2y = rel ? cy + y2 : y2;
          final ex = rel ? cx + x : x, ey = rel ? cy + y : y;
          path.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
          lastC2x = c2x;
          lastC2y = c2y;
          cx = ex;
          cy = ey;

        case 's':
          // 第一控制点 = 上一控制点关于当前点的反射（仅当上一条是 C/S）
          final canReflect = prevCmd == 'c' || prevCmd == 's';
          final r1x = canReflect ? 2 * cx - lastC2x : cx;
          final r1y = canReflect ? 2 * cy - lastC2y : cy;
          final x2 = sc.number(), y2 = sc.number();
          final x = sc.number(), y = sc.number();
          final c2x = rel ? cx + x2 : x2, c2y = rel ? cy + y2 : y2;
          final ex = rel ? cx + x : x, ey = rel ? cy + y : y;
          path.cubicTo(r1x, r1y, c2x, c2y, ex, ey);
          lastC2x = c2x;
          lastC2y = c2y;
          cx = ex;
          cy = ey;

        case 'q':
          final x1 = sc.number(), y1 = sc.number();
          final x = sc.number(), y = sc.number();
          final qx = rel ? cx + x1 : x1, qy = rel ? cy + y1 : y1;
          final ex = rel ? cx + x : x, ey = rel ? cy + y : y;
          path.quadraticBezierTo(qx, qy, ex, ey);
          lastQx = qx;
          lastQy = qy;
          cx = ex;
          cy = ey;

        case 't':
          final canReflect = prevCmd == 'q' || prevCmd == 't';
          final qx = canReflect ? 2 * cx - lastQx : cx;
          final qy = canReflect ? 2 * cy - lastQy : cy;
          final x = sc.number(), y = sc.number();
          final ex = rel ? cx + x : x, ey = rel ? cy + y : y;
          path.quadraticBezierTo(qx, qy, ex, ey);
          lastQx = qx;
          lastQy = qy;
          cx = ex;
          cy = ey;

        case 'a':
          final rx = sc.number(), ry = sc.number(), rot = sc.number();
          final large = sc.flag();
          final sweep = sc.flag();
          final x = sc.number(), y = sc.number();
          final ex = rel ? cx + x : x, ey = rel ? cy + y : y;
          _arcTo(rx, ry, rot, large, sweep, ex, ey);
          cx = ex;
          cy = ey;

        case 'z':
          path.close();
          cx = sx;
          cy = sy;

        default:
          return; // 未知命令：停止解析
      }
      prevCmd = lower;

      // 死循环保护：本轮没有消费任何字符就退出
      if (sc.i == before) break;
    }
  }

  /// 端点参数（SVG 写法）→ 中心参数，再按 ≤90° 切段转三次贝塞尔。
  /// 算法出自 SVG 规范附录 F.6。
  void _arcTo(
    double rx,
    double ry,
    double rotDeg,
    bool large,
    bool sweep,
    double x2,
    double y2,
  ) {
    final x1 = cx, y1 = cy;
    if (x1 == x2 && y1 == y2) return;

    rx = rx.abs();
    ry = ry.abs();
    if (rx == 0 || ry == 0) {
      path.lineTo(x2, y2);
      return;
    }

    final phi = rotDeg * math.pi / 180.0;
    final cosPhi = math.cos(phi), sinPhi = math.sin(phi);

    // 步骤 1：把椭圆转正，坐标移到以 (x1+x2)/2 为原点
    final dx2 = (x1 - x2) / 2.0, dy2 = (y1 - y2) / 2.0;
    final x1p = cosPhi * dx2 + sinPhi * dy2;
    final y1p = -sinPhi * dx2 + cosPhi * dy2;

    // 步骤 2：半径不足时等比放大
    var rx2 = rx * rx, ry2 = ry * ry;
    final lambda = x1p * x1p / rx2 + y1p * y1p / ry2;
    if (lambda > 1) {
      final s = math.sqrt(lambda);
      rx *= s;
      ry *= s;
      rx2 = rx * rx;
      ry2 = ry * ry;
    }

    // 步骤 3：求椭圆中心
    var num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p;
    if (num < 0) num = 0;
    final den = rx2 * y1p * y1p + ry2 * x1p * x1p;
    var coef = den == 0 ? 0.0 : math.sqrt(num / den);
    if (large == sweep) coef = -coef;

    final cxp = coef * rx * y1p / ry;
    final cyp = -coef * ry * x1p / rx;
    final ccx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2.0;
    final ccy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2.0;

    // 步骤 4：求起始角与扫过角
    final ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
    final vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;

    final theta1 = _angle(1, 0, ux, uy);
    var dTheta = _angle(ux, uy, vx, vy);
    if (!sweep && dTheta > 0) dTheta -= 2 * math.pi;
    if (sweep && dTheta < 0) dTheta += 2 * math.pi;

    // 步骤 5：每段 ≤90°，控制点长度取 4/3*tan(Δ/4)
    final segments = math.max(1, (dTheta.abs() / (math.pi / 2)).ceil());
    final delta = dTheta / segments;
    final k = 4.0 / 3.0 * math.tan(delta / 4.0);

    double px(double t) =>
        ccx + rx * math.cos(t) * cosPhi - ry * math.sin(t) * sinPhi;
    double py(double t) =>
        ccy + rx * math.cos(t) * sinPhi + ry * math.sin(t) * cosPhi;
    double dpx(double t) =>
        -rx * math.sin(t) * cosPhi - ry * math.cos(t) * sinPhi;
    double dpy(double t) =>
        -rx * math.sin(t) * sinPhi + ry * math.cos(t) * cosPhi;

    var t = theta1;
    for (var i = 0; i < segments; i++) {
      final t2 = t + delta;
      final p1x = px(t), p1y = py(t);
      final p2x = px(t2), p2y = py(t2);
      path.cubicTo(
        p1x + k * dpx(t),
        p1y + k * dpy(t),
        p2x - k * dpx(t2),
        p2y - k * dpy(t2),
        p2x,
        p2y,
      );
      t = t2;
    }
  }

  static double _angle(double ux, double uy, double vx, double vy) {
    final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    if (len == 0) return 0;
    final a = math.acos(((ux * vx + uy * vy) / len).clamp(-1.0, 1.0));
    return (ux * vy - uy * vx) < 0 ? -a : a;
  }
}
