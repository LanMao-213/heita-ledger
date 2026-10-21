import 'package:flutter/material.dart';

import 'app.dart';
import 'data/db/db.dart';
import 'data/models/setting.dart';
import 'stores/shell_store.dart';

/// 入口。
///
/// 这里只做三件事：绑初始化、装全局错误钩子、造 Store 并 `runApp`。
/// **任何 IO 都不在这里做** —— 冷启动首帧必须只画开屏（≤400ms），
/// 开库与播种都在 `BootGate` 里（架构设计 §4-⑦）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 未捕获的框架异常：先按框架默认方式打印出来（debug 下红屏照旧），
  // 不要在这里吞掉 —— 吞异常会让「记账数字错了」变成「什么都没发生」。
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  runApp(HeitaApp(shell: _createShell()));
}

/// 造外壳 Store。
///
/// 配色落库的回调注在这里：UI 层不碰 SQL，Store 只交出配色 id
/// （`theme.palette`）。落库失败不影响本次使用（下次启动回落默认配色）。
ShellStore _createShell() {
  return ShellStore(
    persistPalette: (String paletteId) =>
        Db.writeSetting(SettingKeys.themePalette, paletteId),
  );
}
