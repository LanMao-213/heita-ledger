// 二级 / 三级菜单的截图自检（六套皮肤各两张）。
//
// 为什么值得写：形状约定（弹层底、圆角卡、内缩分割线、按钮配色）用断言能
// 守住**数值**，但守不住「看起来对不对」—— 比如白卡浮在灰底上到底立不立
// 得住、两个按钮的分隔线会不会太重。所以把每一层真的渲染出来存成 PNG，
// 逐张看。
//
// 副产品是布局自检：Flutter 的溢出（RenderFlex overflow）在测试里会抛异常，
// takeException() 能自动兜住「文字太长把卡片撑破」这类问题。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/widgets/menu.dart';

final _shotKey = GlobalKey();

/// 测试环境默认字体没有中文字形，会全部渲染成方块 —— 把系统字体加载成
/// 默认字族，截图才看得出真实效果。
Future<void> _loadChineseFont() async {
  const candidates = [
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ];
  const families = ['Roboto', 'CupertinoSystemText', '.SF Pro Text'];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    for (final family in families) {
      final loader = FontLoader(
        family,
      )..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
      await loader.load();
    }
    return;
  }
  // ignore: avoid_print
  print('⚠️ 未找到中文字体，截图中的文字会显示为方块');
}

Future<void> _shot(WidgetTester tester, String path) async {
  await tester.binding.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('截图 $path');
  });
}

void main() {
  setUpAll(_loadChineseFont);

  for (final p in kPalettes) {
    testWidgets('${p.name}：二级菜单 + 三级确认框', (tester) async {
      ThemeCtrl.i.loadSilently(p.id);
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(
          key: _shotKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: const _Host(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ---- 二级：账户的菜单 ----
      await tester.tap(find.text('打开二级菜单'));
      await tester.pumpAndSettle();
      await _shot(tester, 'build/visual/menu2-${p.id.name}.png');
      expect(tester.takeException(), isNull, reason: '${p.name} 二级菜单有布局溢出');

      // ---- 三级：菜单里点的「删除」带出来的确认框 ----
      await tester.tap(find.text('删除账户'));
      await tester.pumpAndSettle();
      await _shot(tester, 'build/visual/menu3-${p.id.name}.png');
      expect(tester.takeException(), isNull, reason: '${p.name} 三级确认框有布局溢出');
    });
  }
}

/// 宿主页：只有一颗按钮，按下去弹二级菜单。
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: C.ink,
            foregroundColor: C.bg,
          ),
          onPressed: () => showMenuSheet<void>(
            context: context,
            title: '招商银行',
            subtitle: '储蓄卡 · ¥12,340.00',
            groups: [
              MenuGroup(
                actions: [
                  MenuAction(
                    icon: 'tpl',
                    title: '编辑资料',
                    subtitle: '名称 · 类型 · 余额校准',
                    onTap: () {},
                  ),
                  MenuAction(
                    icon: 'download',
                    title: '取出全部',
                    subtitle: Fmt.yuan(1234000),
                    onTap: () {},
                  ),
                  MenuAction(
                    icon: 'trash',
                    title: '删除账户',
                    subtitle: '余额和记录会转到一个你指定的账户',
                    danger: true,
                    onTap: () => showAppConfirm(
                      context,
                      title: '删除「招商银行」？',
                      message: '余额和记录会并到另一个账户，32 笔记录会挂到目标账户名下，历史不丢。',
                      confirmLabel: '删除',
                      danger: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          child: const Text('打开二级菜单'),
        ),
      ),
    );
  }
}
