part of '../models.dart';

// ---------------------------------------------------------------------------
// 金额与日期的格式化（`Fmt`）
// ---------------------------------------------------------------------------

/// 金额与日期的统一格式约定。
///
/// ★ 金额全程用**整数存「分」**，杜绝浮点误差（0.1+0.2≠0.3 这类问题
///   在记账软件里会累积成真金白银的差错）。
/// ★ 日期用 **TEXT `YYYY-MM-DD`**：可直接字典序排序、`LIKE '2026-10%'`
///   按月筛选、`substr(date,1,7)` 做月分组，比时间戳更好读也更好查。
abstract final class Fmt {
  /// 分 → 「1,234.56」
  static String money(int cents, {bool sign = false, bool trimZero = false}) {
    final neg = cents < 0;
    final v = cents.abs();
    final yuan = v ~/ 100;
    final fen = v % 100;

    final buf = StringBuffer();
    final s = yuan.toString();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }

    var out = '$buf.${fen.toString().padLeft(2, '0')}';
    if (trimZero && fen == 0) out = buf.toString();

    if (neg) return '-$out';
    if (sign && cents > 0) return '+$out';
    return out;
  }

  /// 分 → 「¥1,234.56」
  ///
  /// 负数写成「-¥1,234.56」——符号在货币符号**之前**。旧实现是直接拼接，
  /// 会产出「¥-134.50」，等于把负号放在了货币单位后面。
  static String yuan(int cents, {bool sign = false}) {
    final body = money(cents.abs());
    if (cents < 0) return '-¥$body';
    if (sign && cents > 0) return '+¥$body';
    return '¥$body';
  }

  /// 分 → **无千分位**的纯数字串（固定小数位），用于输入框与可编辑字段。
  ///
  /// 为什么不能直接用 [money]：那里带 `,` 千分位，回填到 `TextField` 之后用户
  /// 再编辑会得到「1,2」这种非法输入；而 `Fmt.parseCents` 又会把逗号剔掉，
  /// 于是「显示」与「提交」两套规则悄悄不一致。输入框需要的是「能原样再解析
  /// 回去」的字符串，所以这里另开一个口子。
  static String plain(int cents, {int decimals = 2}) =>
      (cents / 100).toStringAsFixed(decimals);

  /// 分 → 输入框里的元，去掉多余的 `.00`：`1200` → `12`，`1250` → `12.50`。
  ///
  /// 记账面板的金额、还款金额都用它 —— 一进来就顶着一串 `.00`，用户要按三下
  /// 退格才能开始输入。**这是唯一实现**：以前 `debts_page` 与 `record_sheet`
  /// 各写了一份一模一样的 `_yuan` / `_amountText`。
  static String input(int cents) {
    final s = plain(cents);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  /// 比例 → 百分比文案：`0.348` → `35%`，`decimals: 1` → `34.8%`。
  ///
  /// 全仓所有「xx%」都从这里出，避免各处各写 `(x * 100).toStringAsFixed(n)`：
  /// 那样一旦有人写成 `x.toStringAsFixed` 就会得到「0%」而不报错。
  static String percent(double ratio, {int decimals = 0}) =>
      '${(ratio * 100).toStringAsFixed(decimals)}%';

  /// 分 → 紧凑写法「1.2万」「3,456」，用于卡片上的大数字
  static String compact(int cents) {
    final yuan = cents / 100.0;
    if (yuan.abs() >= 10000) {
      final w = yuan / 10000.0;
      final s = w.toStringAsFixed(w.abs() >= 100 ? 0 : 1);
      return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}万';
    }
    // 不带强制符号：支出写「2,428.50」而不是「+2,428.50」。
    // 环形图中心是支出合计，一个加号会让人以为它是收入或净额。
    return money(cents, trimZero: true);
  }

  /// 「2026-10-16」→「10-16」
  static String md(String date) => date.length >= 10 ? date.substring(5) : date;

  /// 「2026-10-16」→「10月16日 周四」
  /// 「2026-10-23」→「10月23日 周五」
  ///
  /// [relative] 为 true 时，三天内改成「今天 / 昨天 / 前天」。
  /// 只在**记账弹层的日期 chip** 用：那里用户要判断的是「这一笔算哪一天」，
  /// 相对表达省掉一次心算。
  /// 列表里的日期头**不用**相对表达 —— 它是分区标签，要能定位到具体哪天；
  /// 而且回看历史时「今天」会随时间失真（三个月前的截图全是「今天」）。
  static String friendly(String date, {bool relative = false, DateTime? now}) {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    final d = DateTime.tryParse(date);
    // 解析不了就原样给出。旧写法用 `?? 0` / `?? 1` 兜底，会把 "not-a-date"
    // 编成「0月1日」—— 宁可显示原始串，也不要显示一个不存在的日期。
    if (d == null) return date;
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    final day = int.tryParse(parts[2]) ?? 1;
    final wd = ' 周${week[d.weekday - 1]}';
    if (relative) {
      final today = now ?? DateTime.now();
      // 按「日历日」比较，不按 24 小时：23:50 记的账，第二天早上看是「昨天」
      final diff = DateTime(today.year, today.month, today.day)
          .difference(DateTime(d.year, d.month, d.day))
          .inDays;
      if (diff == 0) return '今天';
      if (diff == 1) return '昨天';
      if (diff == 2) return '前天';
    }
    return '${int.tryParse(parts[1]) ?? 0}月$day日$wd';
  }

  /// 「2026-10」→「2026年10月」
  static String monthLabel(String ym) {
    final p = ym.split('-');
    if (p.length != 2) return ym;
    return '${p[0]}年${int.tryParse(p[1]) ?? 0}月';
  }

  /// 今天，`YYYY-MM-DD`
  static String today() => date(DateTime.now());

  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String month(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// 某月天数
  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// 某月第一天：`'2026-10'` → `'2026-10-01'`。
  ///
  /// 月份参数统一折成日期区间，才能吃到 `idx_txn_ledger_date` 索引；
  /// 用 `LIKE '2026-10%'` 也行但走不了索引。所以这个换算只能有一份 ——
  /// 明细、统计、图表三处都从这里取。
  static String monthStart(String ym) => '$ym-01';

  /// 某月最后一天：`'2026-02'` → `'2026-02-28'`。
  static String monthEnd(String ym) {
    final p = ym.split('-');
    final last = daysInMonth(int.parse(p[0]), int.parse(p[1]));
    return '$ym-${last.toString().padLeft(2, '0')}';
  }

  /// 月份偏移，`shiftMonth('2026-01', -1)` → `2025-12`
  static String shiftMonth(String ym, int delta) {
    final p = ym.split('-');
    final y = int.parse(p[0]);
    final m = int.parse(p[1]);
    final t = DateTime(y, m + delta);
    return month(t);
  }

  /// 元 → 分，**解析失败返回 null**。
  ///
  /// 与 [parseCents] 的区别只有一个：`parseCents` 把「解析不出来」和「就是 0」
  /// 都压成 `0`，于是在导入场景里没法把「金额栏写着 `abc`」与「用户真记了 0 元」
  /// 分开 —— 前者该报错，后者该拦下并说明原因。负数合法（退款冲正、跨侧归集）。
  static int? tryParseCents(String input) {
    final s = input.trim().replaceAll(',', '').replaceAll('¥', '').trim();
    if (s.isEmpty) return null;
    final d = double.tryParse(s);
    if (d == null || d.isNaN || d.isInfinite) return null;
    return (d * 100).round();
  }

  static int parseCents(String input) {
    return tryParseCents(input) ?? 0;
  }
}
