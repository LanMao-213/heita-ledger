import 'package:flutter/foundation.dart';

import 'palette.dart';

/// 当前主题的运行时持有者。
///
/// ## 为什么单独一个小类，而不是塞进 Store
///
/// `C.xxx` 是设计层最底层的东西，`tokens.dart` 必须能读到当前色板；
/// 而 `Store` 依赖数据层（Repo/Models），数据层又 import 了 `tokens.dart` ——
/// 让 tokens 反过来依赖 Store 会把这条环扣死。所以这里放一个**不依赖数据层**
/// 的纯通知者：只管「现在是哪套皮肤」，持久化交给 [Store.setTheme]。
///
/// ## 换肤是怎么生效的
///
/// 界面上的 `C.ink` 现在是 getter，读的是这里的 [palette]。但 Flutter 不会
/// 因为某个静态 getter 变了就重建 widget —— 所以 `app.dart` 里给主子树挂了
/// `ValueKey(ThemeCtrl.i.id)`：id 一变，整棵子树重建，所有 `C.xxx` 重新求值。
///
/// 代价：换肤会丢页面的局部状态（滚动位置、展开的输入框）。这是**刻意**的
/// —— 换肤是低频操作，而让 446 处调用点各自去监听主题不现实。
class ThemeCtrl extends ChangeNotifier {
  ThemeCtrl._();

  static final ThemeCtrl i = ThemeCtrl._();

  HeitaThemeId _id = kDefaultTheme;

  HeitaThemeId get id => _id;

  /// 当前色板
  Palette get palette => paletteOf(_id);

  /// 是否深色（决定状态栏图标明暗与 Material 组件的前景色）
  bool get dark => palette.dark;

  /// 换肤并通知全树重建。
  void apply(HeitaThemeId id) {
    if (_id == id) return;
    _id = id;
    notifyListeners();
  }

  /// 启动时载入（不通知：此时界面还没起来）
  void loadSilently(HeitaThemeId id) {
    _id = id;
  }
}
