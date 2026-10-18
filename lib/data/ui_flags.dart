import 'repo.dart';

/// 界面实验开关。
///
/// 有两处改动是「先上、看效果再定」的，不写死：
/// - [typeChips]：明细页顶部「全部 / 支出 / 收入 / 转账」那排快捷筛选
/// - [emptyHints]：空状态里的第二行引导文案
///
/// 默认都开。想关掉不用改代码重编，往 setting 表插一条即可：
///
/// ```sql
/// INSERT OR REPLACE INTO setting(k, v) VALUES('ui.type_chips', '0');
/// ```
///
/// 下次启动 [load] 会读到。调试时也可以直接改这两个字段。
/// 真定下来了，就把这里的默认值删掉、把调用点的 if 去掉，只留一种行为。
abstract final class UiFlags {
  static bool typeChips = true;
  static bool emptyHints = true;

  static const keyTypeChips = 'ui.type_chips';
  static const keyEmptyHints = 'ui.empty_hints';

  static Future<void> load() async {
    typeChips = await _read(keyTypeChips, typeChips);
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
