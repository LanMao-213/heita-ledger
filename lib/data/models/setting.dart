/// 设置表（`setting`）的键常量。
///
/// **只放两类键**：① 机器状态（当前账本、账本归属期起始日）；② 用户偏好
/// （触感开关、配色、一次性提示是否出过）。
///
/// 已退休的键**不建**（原版有、新库没有，见架构设计 §3.3 末段）：
/// `app_name` / `schema_ready` / `ui.empty_hints` / `ui.type_chips`。
///
/// 键名是持久化契约：改了等于老用户配置丢失，所以每个常量都写明来源。
abstract final class SettingKeys {
  /// 当前账本 id。指向不存在的账本时启动序列会自愈到第一本。
  static const String currentLedgerId = 'current_ledger_id';

  /// 账单日（1–31），决定归属期的起止。缺省 1。
  static const String cycleStartDay = 'cycle_start_day';

  /// 触感反馈开关，`'1'` / `'0'`。缺省开（老库无此键也按开处理）。
  static const String uiHaptics = 'ui.haptics';

  /// 「分类已升级为两级」的一次性提示标记。
  static const String uiNoticeCats = 'ui.notice.cats';

  /// 配色 id：`'ink'`（默认）/ `'aurora'`。见 `AppPalette.id`。
  static const String themePalette = 'theme.palette';

  /// 全部键（`replaceAll` 恢复时要按这份名单筛出「可搬」的键）。
  static const List<String> all = <String>[
    currentLedgerId,
    cycleStartDay,
    uiHaptics,
    uiNoticeCats,
    themePalette,
  ];
}
