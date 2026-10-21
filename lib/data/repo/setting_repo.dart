import '../db/db.dart';
import '../db/schema.dart';
import '../models/models.dart';
import '../models/setting.dart';

/// `setting` 表的读写 + 类型安全取值。
///
/// 只放**机器状态与用户偏好**（当前账本、账单日、触感、配色、一次性提示）。
/// 业务数据一律进各自的表 —— 原版把「账本名」也塞进 setting（`app_name`），
/// 结果改名要改两处。
class SettingRepo {
  const SettingRepo();

  /// 读原始字符串；缺失返回 `null`（**与空串区分**）。
  Future<String?> read(String key) => Db.readSetting(key);

  Future<void> write(String key, String value) =>
      Db.writeSetting(key, value);

  /// 读整数；缺失或非法返回 [fallback]（导入路径要能容忍脏值）。
  Future<int> readInt(String key, {required int fallback}) async {
    final String? raw = await Db.readSetting(key);
    if (raw == null) return fallback;
    return int.tryParse(raw.trim()) ?? fallback;
  }

  /// 读布尔：`'1'` / `'true'` 为真，缺失按 [fallback]。
  Future<bool> readBool(String key, {required bool fallback}) async {
    final String? raw = await Db.readSetting(key);
    if (raw == null) return fallback;
    final String v = raw.trim().toLowerCase();
    if (v == '1' || v == 'true') return true;
    if (v == '0' || v == 'false') return false;
    return fallback;
  }

  Future<void> writeBool(String key, bool value) =>
      Db.writeSetting(key, value ? '1' : '0');

  /// 账单日（1–31）。缺省 1，越界也回落 1。
  Future<int> cycleStartDay() async {
    final int day = await readInt(SettingKeys.cycleStartDay, fallback: 1);
    return day >= 1 && day <= 31 ? day : 1;
  }

  Future<void> setCycleStartDay(int day) =>
      Db.writeSetting(SettingKeys.cycleStartDay, '${day.clamp(1, 31)}');

  /// 触感开关，缺省开。
  Future<bool> hapticsEnabled() =>
      readBool(SettingKeys.uiHaptics, fallback: true);

  Future<void> setHapticsEnabled(bool enabled) =>
      writeBool(SettingKeys.uiHaptics, enabled);

  /// 分类升级一次性提示标记。
  Future<bool> catsNoticeShown() =>
      readBool(SettingKeys.uiNoticeCats, fallback: false);

  Future<void> markCatsNoticeShown() =>
      writeBool(SettingKeys.uiNoticeCats, true);

  /// 配色 id，缺省 `ink`。
  Future<String> paletteId() async =>
      await Db.readSetting(SettingKeys.themePalette) ?? 'ink';

  Future<void> setPaletteId(String id) =>
      Db.writeSetting(SettingKeys.themePalette, id);

  /// 当前账本指针（原始值，可能指向已删除的账本 —— 自愈在 `LedgerRepo`）。
  Future<int?> currentLedgerIdRaw() async {
    final String? raw = await Db.readSetting(SettingKeys.currentLedgerId);
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  Future<void> setCurrentLedgerId(int id) =>
      Db.writeSetting(SettingKeys.currentLedgerId, '$id');

  /// 表行数（体检/测试用）。
  Future<int> count() => Db.rowCount(Tables.setting);

  /// 可搬的设置键（恢复备份时只搬这些，机器状态留在本机）。
  static const List<String> portableKeys = <String>[
    SettingKeys.cycleStartDay,
    SettingKeys.uiHaptics,
    SettingKeys.uiNoticeCats,
    SettingKeys.themePalette,
  ];
}
