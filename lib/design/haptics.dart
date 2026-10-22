import 'package:flutter/services.dart';

/// 触感反馈统一出口。
///
/// 原则：**只有一件事做完了才震**，而且分量跟着后果走 —— 删除比记账重。
/// 导航类的震动（切页、翻页）一律用最轻的 selectionClick，手指本来就在动，
/// 震动只是给一个「收到了」的确认，不该有存在感。
///
/// 全部 fire-and-forget：不 await，也不在调用方处理失败。
/// 有些机型/系统设置会关掉触感，那时这些调用只是静默无效。
///
/// ★ [enabled] 是应用级的用户开关（我的 → 偏好 → 触感反馈）。
///   用户在系统里关了触感是系统的事，这里关的是**本应用要不要震** ——
///   两者互不冲突：任一层关掉，结果都是不震。
///   开关值存在 setting 表（`ui.haptics`），由 `Store.boot` 读进来。
abstract final class Haptics {
  /// 用户是否开着触感反馈。默认开（记账类应用里，「记上了」这一下很有用）。
  static bool enabled = true;

  /// 记账保存、收藏这类「完成了一个正向动作」
  static void success() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// 删除、清空这类「不可逆」—— 比 [success] 重一档
  static void warn() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }

  /// 切 tab、翻页、选中 —— 最轻
  static void tap() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  /// 键盘确认键
  static void key() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }
}
