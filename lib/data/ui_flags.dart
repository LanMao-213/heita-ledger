import 'repo.dart';

/// 界面实验开关。
///
/// 现在只剩一处「先上、看效果再定」的：[emptyHints]（空状态里的第二行引导文案）。
///
/// 原先还有一个 [typeChips]（明细页顶部「全部 / 支出 / 收入 / 转账」那排快捷筛选），
/// **1.4.5 已定稿移除**，开关一并退休 —— 留一个永远是 false 的开关，
/// 比没有开关更容易误导下一个人。要看历史效果直接翻 git。
///
/// 想关掉剩下的这个不用改代码重编，往 setting 表插一条即可：
///
/// ```sql
/// INSERT OR REPLACE INTO setting(k, v) VALUES('ui.empty_hints', '0');
/// ```
///
/// 下次启动 [load] 会读到。调试时也可以直接改这两个字段。
/// 真定下来了，就把这里的默认值删掉、把调用点的 if 去掉，只留一种行为。
abstract final class UiFlags {
  static bool emptyHints = true;

  static const keyEmptyHints = 'ui.empty_hints';

  static Future<void> load() async {
    emptyHints = await _read(keyEmptyHints, emptyHints);
  }

  /// `'0'` / `'false'` 都算关；键不存在时保持默认。
  static Future<bool> _read(String key, bool fallback) async {
    try {
      final v = await Repo.getSetting(key);
      if (v == null) return fallback;
      return v != '0' && v.toLowerCase() != 'false';
    } catch (_) {
      // 读设置失败不该影响启动，退回默认值
      return fallback;
    }
  }
}
