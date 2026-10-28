/// 金额表达式：只做四则运算，不含括号。
///
/// 两个职责严格分开，这样最该被钉死的部分能脱离 UI 单测：
/// - [press]：一次按键 = 对字符串做一次变换
/// - [cents]：把表达式求成「分」，非法表达式返回 null
///
/// ★ 负数规则（用户定）：**在最前面打 `-` 就是负数**，例如 `-20` 表示净流出。
///   所以 `-` 有两个身份：行首（或运算符后）是一元负号，数字之后是减号。
///   键盘上因此没有 `±` 键，这是有意为之，不是漏了。
///
/// ★ 精度：内部用 double 算，**只在最后取整一次**。每步取整会让
///   `0.1 + 0.2` 这类输入累积出分位误差。
abstract final class Calc {
  static const _ops = '+-*/';
  static const _maxIntDigits = 9;
  static const _maxDecimals = 2;

  // -------------------------------------------------------------- 按键变换

  /// 把一次按键作用到表达式上。key 取值：`0`-`9`、`.`、`+`、`-`、`*`、`/`、`C`、`del`。
  static String press(String expr, String key) {
    switch (key) {
      case 'C':
        return '';
      case 'del':
        return expr.isEmpty ? expr : expr.substring(0, expr.length - 1);
      case '.':
        return _pressDot(expr);
    }
    if (_ops.contains(key)) return _pressOp(expr, key);
    return _pressDigit(expr, key);
  }

  static String _pressDigit(String expr, String digit) {
    final cur = _currentNumber(expr);
    final dot = cur.indexOf('.');
    if (dot >= 0) {
      if (cur.length - dot - 1 >= _maxDecimals) return expr;
    } else {
      final intDigits = cur.replaceAll('-', '').length;
      // 整数位上限只在整数部分用得着；已经打了小数点就不管了
      if (intDigits >= _maxIntDigits) return expr;
    }
    // 「0」后面直接打数字要替换，别留下 012 这种前导零
    if (cur == '0') return '${expr.substring(0, expr.length - 1)}$digit';
    return '$expr$digit';
  }

  static String _pressDot(String expr) {
    final cur = _currentNumber(expr);
    if (cur.contains('.')) return expr;
    // 行首或运算符后面按小数点，自动补 0
    if (cur.isEmpty) return '${expr}0.';
    return '$expr.';
  }

  static String _pressOp(String expr, String op) {
    // 行首只允许负号：其余运算符没有左操作数
    if (expr.isEmpty) return op == '-' ? '-' : expr;
    // 只有一个负号时，后面只能接数字
    if (expr == '-') return expr;

    final last = expr[expr.length - 1];
    if (_ops.contains(last)) {
      // 连按运算符：替换上一个（计算器的习惯），别堆成 `12+-`
      return '${expr.substring(0, expr.length - 1)}$op';
    }
    if (last == '.') {
      // `12.` 后面接运算符时，把没意义的小数点丢掉
      return '${expr.substring(0, expr.length - 1)}$op';
    }
    return '$expr$op';
  }

  // ---------------------------------------------------------------- 求值

  /// 求值，返回「分」。空、未输完、除零、非法字符一律返回 null。
  static int? cents(String expr) {
    final s = expr;
    if (s.isEmpty) return null;

    var i = 0;

    double? number() {
      var sign = 1.0;
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        sign = s[i] == '-' ? -1 : 1;
        i++;
      }
      final start = i;
      while (i < s.length && (_isDigit(s[i]) || s[i] == '.')) {
        i++;
      }
      if (i == start) return null; // 运算符后面没有数字
      final token = s.substring(start, i);
      if (token.endsWith('.')) return null; // 「15.」不算输完
      if ('.'.allMatches(token).length > 1) return null;
      final v = double.tryParse(token);
      if (v == null) return null;
      return sign * v;
    }

    double? term() {
      final first = number();
      if (first == null) return null;
      var v = first;
      while (i < s.length && (s[i] == '*' || s[i] == '/')) {
        final op = s[i];
        i++;
        final r = number();
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
      final first = term();
      if (first == null) return null;
      var v = first;
      while (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final op = s[i];
        i++;
        final r = term();
        if (r == null) return null;
        v = op == '+' ? v + r : v - r;
      }
      return v;
    }

    final v = sum();
    if (v == null || i != s.length) return null;
    if (v.isNaN || v.isInfinite) return null;
    final cents = (v * 100).round();
    if (cents.abs() > 999999999999) return null;
    return cents;
  }

  // ---------------------------------------------------------------- 展示

  /// 展示口径：把「正在输入」的表达式翻译成金额区该显示的那个数。
  ///
  /// 与 [cents] 的分工是本类唯一容易搞混的地方，也是 1.5.0 那个
  /// 「按了小数点，1 变成 0」的根因：
  ///
  /// - [cents] 回答「**能不能存**」：`1.`、`12+` 都还没输完 → null → 确认键置灰。
  /// - [display] 回答「**已经敲了什么**」：`1.` 就是 1（小数点按过了），
  ///   `12+` 就是 12。把「不能存」直接当成「没有值」，用户刚按的数字就会消失。
  ///
  /// 返回值：
  /// - `null`：一个数字都没敲（空串、只有行首负号、只有运算符）。
  /// - `cents`：此刻该显示的金额（分）。
  /// - `trailingDot`：表达式停在「刚按完小数点」上（`1.`），调用方补一个点，
  ///   让用户看得见自己按到了哪儿。**只有最后一位是小数点时**才为 true。
  static ({int cents, bool trailingDot})? display(String expr) {
    // 末尾的运算符不算数：`12+` 这一屏仍然显示 12。行首负号单独出现
    // （`-`）剥完就空了，等于没输。
    var s = expr;
    while (s.isNotEmpty && _ops.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return null;

    final dot = s.endsWith('.');
    // `1.` 按 1.0 求值：小数点是「下一个数字的入口」，不是非法字符。
    final value = cents(dot ? '${s}0' : s);
    if (value == null) return null;
    return (cents: value, trailingDot: dot);
  }

  /// 显示用：把键盘符号换成数学符号。
  /// 减号保持 ASCII —— U+2212 在部分中文字体里缺字形，会显示成空白。
  static String pretty(String expr) =>
      expr.replaceAll('*', '×').replaceAll('/', '÷');

  /// 是否含运算（行首的负号不算，`-20` 只是一个数）
  static bool hasOperator(String expr) {
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if (c == '+' || c == '*' || c == '/') return true;
      if (c == '-' && i > 0) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- 内部

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  /// 正在输入的那个数（最后一个运算符之后的部分），可能带一元负号
  static String _currentNumber(String expr) {
    var i = expr.length;
    while (i > 0 && (_isDigit(expr[i - 1]) || expr[i - 1] == '.')) {
      i--;
    }
    if (i > 0 && expr[i - 1] == '-' && (i == 1 || _ops.contains(expr[i - 2]))) {
      i--;
    }
    return expr.substring(i);
  }
}
