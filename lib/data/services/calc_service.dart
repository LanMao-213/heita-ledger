/// 键盘表达式的**状态机**与求值。
///
/// 两个职责严格分开，这样最该被钉死的部分能脱离 UI 单测：
/// - [press]：一次按键 = 对字符串做一次变换
/// - [cents]：把表达式求成「分」，非法表达式返回 `null`
///
/// ★ 负数规则（用户定）：**在最前面打 `-` 就是负数**，例如 `-20` 表示净流出。
///   所以 `-` 有两个身份：行首（或运算符后）是一元负号，数字之后是减号。
///   键盘上因此**没有 `±` 键**，这是有意为之，不是漏了。
///
/// ★ 精度：内部用 `double` 算，**只在最后 `(v*100).round()` 取整一次**。
///   每步取整会让 `0.1 + 0.2` 这类输入累积出分位误差。
library;

/// 键盘按键（字符串形式，与 UI 的按钮标签一一对应）。
abstract final class CalcKeys {
  static const String clear = 'C';
  static const String del = 'del';
  static const String dot = '.';
  static const String plus = '+';
  static const String minus = '-';
  static const String times = '*';
  static const String divide = '/';
}

/// 表达式状态机。UI 持有一个实例，每次按键调 [tap] 并读 [expr] 显示。
class CalcService {
  CalcService([this.expr = '']);

  static const int maxIntDigits = 9;
  static const int maxDecimals = 2;

  /// 上限 ≈ ¥99.99 亿，与 `Money.maxAbsCents` 同一个数。
  static const int maxAbsCents = 999999999999;

  /// 当前表达式（键盘用 `*` `/`，不是 `×` `÷`）。UI 可直接改它（粘贴/预填模板）。
  String expr;

  bool get isEmpty => expr.isEmpty;

  /// 显示用：运算符换成数学符号（减号保持 ASCII，U+2212 在部分中文字体缺字形）。
  String get display => pretty(expr);

  /// 求值结果；`null` 表示「还不能保存」。
  int? get cents => evaluate(expr);

  /// 是否含运算（行首的负号不算，`-20` 只是一个数）。
  bool get isCompound => hasOperator(expr);

  /// 一次按键（实例方法，避开与静态 [press] 重名）。
  void tap(String key) => expr = press(expr, key);

  void clear() => expr = '';

  void backspace() => tap(CalcKeys.del);

  /// 把一次按键作用到表达式上。
  ///
  /// key 取值：`0`-`9`、`.`、`+`、`-`、`*`、`/`、`C`、`del`。
  static String press(String expr, String key) {
    switch (key) {
      case CalcKeys.clear:
        return '';
      case CalcKeys.del:
        return expr.isEmpty ? expr : expr.substring(0, expr.length - 1);
      case CalcKeys.dot:
        return _pressDot(expr);
    }
    if (_isOp(key)) return _pressOp(expr, key);
    return _pressDigit(expr, key);
  }

  static bool _isOp(String c) => c == '+' || c == '-' || c == '*' || c == '/';

  static bool _isDigit(String c) {
    final int code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static String _pressDigit(String expr, String digit) {
    final String cur = _currentNumber(expr);
    final int dot = cur.indexOf('.');
    if (dot >= 0) {
      // 小数位上限
      if (cur.length - dot - 1 >= maxDecimals) return expr;
    } else {
      final int intDigits = cur.replaceAll('-', '').length;
      // 整数位上限只在整数部分用得着；已经打了小数点就不管了
      if (intDigits >= maxIntDigits) return expr;
    }
    // 「0」后面直接打数字要替换，别留下 012 这种前导零
    if (cur == '0') return '${expr.substring(0, expr.length - 1)}$digit';
    return '$expr$digit';
  }

  static String _pressDot(String expr) {
    final String cur = _currentNumber(expr);
    if (cur.contains('.')) return expr; // 小数点唯一
    // 行首（或只有一个负号 / 运算符后面）按小数点，自动补 0：
    // `-.` 这种半截写法看起来像出错，`-0.` 才说得清「这是个数」
    if (cur.isEmpty || cur == '-') return '${expr}0.';
    return '$expr.';
  }

  static String _pressOp(String expr, String op) {
    // 行首只允许负号：其余运算符没有左操作数
    if (expr.isEmpty) return op == '-' ? '-' : expr;
    // 只有一个负号时，后面只能接数字
    if (expr == '-') return expr;

    final String last = expr[expr.length - 1];
    if (_isOp(last)) {
      // 连按运算符：替换上一个（计算器的习惯），别堆成 `12+-`
      return '${expr.substring(0, expr.length - 1)}$op';
    }
    if (last == '.') {
      // `12.` 后面接运算符时，把没意义的小数点丢掉
      return '${expr.substring(0, expr.length - 1)}$op';
    }
    return '$expr$op';
  }

  /// 正在输入的那个数（最后一个运算符之后的部分），可能带一元负号。
  static String _currentNumber(String expr) {
    int i = expr.length;
    while (i > 0 && (_isDigit(expr[i - 1]) || expr[i - 1] == '.')) {
      i--;
    }
    if (i > 0 && expr[i - 1] == '-' && (i == 1 || _isOp(expr[i - 2]))) {
      i--;
    }
    return expr.substring(i);
  }

  /// 求值，返回「分」。
  ///
  /// 空、未输完（`12.` / `12+`）、除零、非法字符、超上限一律 `null`。
  /// 递归下降：`expr := term (('+'|'-') term)*`，`term := number (('*'|'/') number)*`。
  static int? evaluate(String expr) {
    final String s = expr;
    if (s.isEmpty) return null;

    int i = 0;

    double? number() {
      double sign = 1.0;
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        sign = s[i] == '-' ? -1.0 : 1.0;
        i++;
      }
      final int start = i;
      while (i < s.length && (_isDigit(s[i]) || s[i] == '.')) {
        i++;
      }
      if (i == start) return null; // 运算符后面没有数字
      final String token = s.substring(start, i);
      if (token.endsWith('.')) return null; // 「15.」不算输完
      if ('.'.allMatches(token).length > 1) return null;
      final double? v = double.tryParse(token);
      if (v == null) return null;
      return sign * v;
    }

    double? term() {
      final double? first = number();
      if (first == null) return null;
      double v = first;
      while (i < s.length && (s[i] == '*' || s[i] == '/')) {
        final String op = s[i];
        i++;
        final double? r = number();
        if (r == null) return null;
        if (op == '*') {
          v = v * r;
        } else {
          if (r == 0) return null; // 除零按非法处理
          v = v / r;
        }
      }
      return v;
    }

    double? sum() {
      final double? first = term();
      if (first == null) return null;
      double v = first;
      while (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final String op = s[i];
        i++;
        final double? r = term();
        if (r == null) return null;
        v = op == '+' ? v + r : v - r;
      }
      return v;
    }

    final double? v = sum();
    if (v == null || i != s.length) return null;
    if (v.isNaN || v.isInfinite) return null;
    // 只在这里取整一次
    final int cents = (v * 100).round();
    if (cents.abs() > maxAbsCents) return null;
    return cents;
  }

  /// 显示用：`*` → `×`、`/` → `÷`。
  static String pretty(String expr) =>
      expr.replaceAll('*', '×').replaceAll('/', '÷');

  /// 是否含运算（行首的负号不算）。
  static bool hasOperator(String expr) {
    for (int i = 0; i < expr.length; i++) {
      final String c = expr[i];
      if (c == '+' || c == '*' || c == '/') return true;
      if (c == '-' && i > 0) return true;
    }
    return false;
  }
}
