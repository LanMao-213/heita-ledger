// 子分类图标总览。
//
// 2026-10 的两级分类一次加了 41 个手绘线稿图标。这个测试不校验逻辑，
// 只做一件事：把 `category_seed.dart` 里每个子分类的图标**真的渲染出来**
// 拼成一张图，方便核对「形状能不能认出来」「和原有图标是否同一种笔感」。
//
// 图标是自绘的 SVG 路径，测试抓不到「这个图形看起来像什么」——只能靠眼睛。
// 所以把它做成可重复生成的资产，每次改图标重跑一次即可。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/category_seed.dart';
import 'package:ledger/design/icons.dart';
import 'package:ledger/design/tokens.dart';

Future<void> _loadChineseFont() async {
  const candidates = [
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    for (final family in ['Roboto', 'CupertinoSystemText']) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
          ))
          .load();
    }
    return;
  }
}

Widget _subCell(SeedSub s) => SizedBox(
  width: 96,
  height: 66,
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      LineIcon(s.icon, size: 24, color: C.ink),
      const SizedBox(height: 5),
      Text(
        s.name,
        style: const TextStyle(fontSize: 11, color: C.ink2),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  ),
);

Widget _catBlock(SeedCat c) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          LineIcon(c.icon, size: 18, color: C.ink),
          const SizedBox(width: 8),
          Text(
            c.name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: C.ink,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${c.subs.length}',
            style: const TextStyle(fontSize: 11, color: C.ink3),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Wrap(
        runSpacing: 2,
        children: [for (final s in c.subs) _subCell(s)],
      ),
    ],
  ),
);

void main() {
  testWidgets('子分类图标总览截图', (tester) async {
    await _loadChineseFont();
    await tester.binding.setSurfaceSize(const Size(1000, 1720));

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: C.bg,
            body: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '支出 · 9 类 / 48 子分类',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: C.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final c in kExpenseSeed) _catBlock(c),
                  const SizedBox(height: 4),
                  const Text(
                    '收入 · 6 类 / 23 子分类',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: C.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final c in kIncomeSeed) _catBlock(c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.binding.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.4);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/visual/icons.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    });
  });
}
