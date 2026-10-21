import 'package:flutter/foundation.dart';

import '../theme/palette.dart';

/// 所有 Store 的基类：**通知合并**（不是节流）。
///
/// 一次操作要改很多字段、要重查好几个查询，逐个 `notifyListeners()` 会让整棵树
/// 重建多次（原版「一次记账两遍重建」）。这里把 `notifyListeners()` 的语义改成
/// 「标记有变化」：在 [batchNotify] 体内只记一个 pending 标志，退出时发一次。
///
/// 三条纪律（架构设计 §1.2）：
/// 1. `notifyListeners()` **只允许**在 Store 内部调用；
/// 2. 页面层禁止 `setState` 后手动通知 Store；
/// 3. 订阅粒度到叶子 —— `AmountText` / `TxnRow` / `ProgressBar` 不订阅任何 Store。
abstract class StoreBase extends ChangeNotifier {
  int _suspendDepth = 0;
  bool _pending = false;
  bool _disposed = false;

  /// 同步批处理：体内的 notify 合并成一次，退出时发。
  ///
  /// 调用者只有两类：Store 自己的写方法、启动序列（`BootSequence`）。
  /// 页面层**不允许**调它 —— 页面不改 Store 状态，只发「用户操作」。
  void batchNotify(VoidCallback body) {
    _suspendDepth++;
    try {
      body();
    } finally {
      _suspendDepth--;
      _flushIfNeeded();
    }
  }

  /// 异步批处理：体内可以 `await`。用于启动序列这种「十几个查询后才 ready」的流程。
  Future<T> batchNotifyAsync<T>(Future<T> Function() body) async {
    _suspendDepth++;
    try {
      return await body();
    } finally {
      _suspendDepth--;
      _flushIfNeeded();
    }
  }

  void _flushIfNeeded() {
    if (_suspendDepth > 0 || !_pending) return;
    _pending = false;
    if (_disposed) return;
    super.notifyListeners();
  }

  /// 已被 dispose 后不再发通知（异步任务可能在页面销毁后完成）。
  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (_disposed) return;
    if (_suspendDepth > 0) {
      _pending = true;
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 应用外壳状态：底部 tab、当前配色、触感开关、启动就绪标志与启动错误。
///
/// 只有 `HomeShell` 订阅它（配色由 `MaterialApp` 通过 `ListenableBuilder` 取）。
/// 其余页面一律不订阅 —— 否则每次记账底栏都跟着重建。
class ShellStore extends StoreBase {
  ShellStore({this.persistPalette});

  /// 配色落库回调。UI 层不碰 SQL，Store 只把「哪个 id」交出去。
  final Future<void> Function(String paletteId)? persistPalette;

  /// 底部 tab 数量（**页面**数量，不含中央浮钮）。
  static const int tabCount = 4;

  static const int tabDetail = 0;
  static const int tabStats = 1;
  static const int tabPlan = 2;
  static const int tabMine = 3;

  /// 底栏有 5 个槽位：明细 / 图表 / ＋ / 计划 / 我的。
  ///
  /// 槽位 2 是中央浮钮，不承载页面。这个映射是「tab 序号 ↔ 槽位序号」的唯一换算处，
  /// 底栏与 `PageView` 都从这里取，避免两处各写一份 `index + 1`。
  static int barSlotOfTab(int tab) {
    assert(tab >= 0 && tab < tabCount, 'tab 越界：$tab');
    return tab < 2 ? tab : tab + 1;
  }

  /// 槽位序号 → tab 序号。中央浮钮（槽位 2）返回 `null`。
  static int? tabOfBarSlot(int slot) {
    if (slot == 2) return null;
    return slot < 2 ? slot : slot - 1;
  }

  int _tabIndex = tabDetail;
  AppPalette _palette = paletteInk();
  bool _hapticsEnabled = true;
  bool _ready = false;
  Object? _bootError;

  /// 当前 tab（0..3）。
  int get tabIndex => _tabIndex;

  /// 当前配色。整个 App 的取色都源自它（通过 `ThemeData.extensions`）。
  AppPalette get palette => _palette;

  /// 触感反馈是否开启。关闭后 `Haptics` 的每次调用都直接返回，**零平台通道调用**。
  bool get hapticsEnabled => _hapticsEnabled;

  /// 启动序列是否已跑完。为真时 `BootGate` **不再重复跑**（热重载安全）。
  bool get ready => _ready;

  /// 启动失败时的异常对象。非空 → `BootGate` 渲染失败页。
  Object? get bootError => _bootError;

  /// 切 tab。**切到当前 tab 不发通知、不重放动画**（否则用户点一下就抖一下）。
  void switchTab(int index) {
    if (index == _tabIndex) return;
    if (index < 0 || index >= tabCount) {
      throw ArgumentError.value(index, 'index', 'tab 必须在 0..${tabCount - 1}');
    }
    _tabIndex = index;
    notifyListeners();
  }

  /// 切配色：内存立即生效 → 落库 → 1 次通知。
  ///
  /// 内存先改是为了「切完立刻生效、无需重启」（`MaterialApp` 内部的
  /// `AnimatedTheme` 会做 200ms 插值）；落库失败不影响本次使用，
  /// 下次启动回落默认配色。
  void setPalette(AppPalette next) {
    if (next.id == _palette.id) return;
    _palette = next;
    notifyListeners();
    final Future<void> Function(String)? persist = persistPalette;
    if (persist != null) {
      persist(next.id).catchError((Object _) {});
    }
  }

  /// 按 id 切配色。认不出的 id 回落默认，不抛。
  void setPaletteById(String? id) => setPalette(AppPalette.byId(id));

  /// 触感开关。切换立即生效并落库（`ui.haptics`）。
  void setHapticsEnabled(bool enabled) {
    if (_hapticsEnabled == enabled) return;
    _hapticsEnabled = enabled;
    notifyListeners();
  }

  /// 启动序列读到的偏好一次性灌进内存（在第 5 步、**首帧之前**调用）。
  void applyBootFlags({
    required bool hapticsEnabled,
    required String? paletteId,
  }) {
    batchNotify(() {
      _hapticsEnabled = hapticsEnabled;
      _palette = AppPalette.byId(paletteId);
      notifyListeners();
    });
  }

  /// 启动完成。
  void markReady() {
    if (_ready && _bootError == null) return;
    _ready = true;
    _bootError = null;
    notifyListeners();
  }

  /// 启动失败。`ready` 保持 false，失败页据此渲染。
  void failBoot(Object error) {
    _ready = false;
    _bootError = error;
    notifyListeners();
  }

  /// 清掉失败态（点「重试」时调）。
  void clearBootError() {
    if (_bootError == null) return;
    _bootError = null;
    notifyListeners();
  }
}
