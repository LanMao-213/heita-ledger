// 全局测试配置：`flutter test` 跑每个测试文件前先执行这里。
//
// 唯一要做的事：关掉首次使用引导的**自动**弹出。
//
// 为什么必须统一关：引导是一层全屏遮罩，在「pump 整个 App 再点界面」的用例里
// 它会盖住所有待点控件，几十条与引导毫无关系的用例会一起报「找不到 tab」。
// 而它出现的条件（全新安装）恰恰是每个测试文件 setUp 里「删掉旧库、重新建库」
// 的常态 —— 也就是说，不统一关，这条路会一直亮着红灯。
//
// 关的是「自动」，不是引导本身：`test/onboarding_test.dart` 会自己把它打开来验，
// 侧拉栏里的「使用引导」也照常走。
//
// 复用 `Onboarding.autoShow` 而不是在测试里改数据库标记：标记是持久化状态，
// 会被备份/恢复的用例带进带出，用它当开关等于让测试之间互相污染。
import 'dart:async';

import 'package:ledger/pages/onboarding_page.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Onboarding.autoShow = false;
  await testMain();
}
