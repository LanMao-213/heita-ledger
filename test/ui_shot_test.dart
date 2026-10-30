// 界面截图自检。
//
// 为什么值得写：我无法上真机看效果，但可以在测试里把界面**真的渲染出来**
// 存成 PNG，然后逐张核对。更关键的是，Flutter 的布局溢出（RenderFlex
// overflow）在测试里会抛异常 —— 用 takeException() 断言就能自动兜住
// 「文字太长把卡片撑破」这类问题，比肉眼快得多。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app.dart';
import 'package:ledger/data/backup_service.dart';
import 'package:ledger/data/cycle.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/design/icons.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/pages/safety_page.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/common.dart';
import 'package:ledger/widgets/pickers.dart';
import 'package:ledger/widgets/detail/txn_row.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _shotKey = GlobalKey();

/// 测试环境默认字体没有中文字形，会全部渲染成方块。
/// 这里把系统「等线」加载成默认字体族，截图才看得出真实效果。
Future<void> _loadChineseFont() async {
  const candidates = [
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ];
  // Cupertino 的滚轮（CupertinoPicker）用的是它自己的默认字族，不是 Roboto。
  // 只注册 Roboto 的话，双轮盘截图里的中文会变成方块。
  const families = [
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    '.SF Pro Text',
  ];
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
    // ignore: avoid_print
    print('已加载中文字体：$path（$families）');
    return;
  }
  // ignore: avoid_print
  print('⚠️ 未找到中文字体，截图中的文字会显示为方块');
}

/// 图标字体在测试环境里不会自动加载，不补的话所有 Icon 都是方块。
Future<void> _loadIconFont() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer),
      ),
    );
  await loader.load();
}

/// 截图输出根目录。默认 `build/visual` —— 它在 `.gitignore` 里，
/// 所以截图永远不会进版本库（这也是本仓库不做 `matchesGoldenFile` 的原因：
/// 字体来自 `C:\Windows\Fonts`，CI 在 ubuntu 上没有，基线必然对不上）。
///
/// 它的真正用途是**改前改后对拍**：
///
/// ```bash
/// flutter test test/ui_shot_test.dart --dart-define=SHOT_DIR=build/visual/base
/// # 改代码（重构/拆 widget），不改行为
/// flutter test test/ui_shot_test.dart --dart-define=SHOT_DIR=build/visual/after
/// python tools/visual_diff.py build/visual/base build/visual/after
/// ```
///
/// 差异为 0 才说明「只是搬了代码，界面没变」。这比提交 golden 便宜：
/// 一次性用完就删，不用跟着 Flutter 版本升级维护基线。
const _shotRoot = String.fromEnvironment('SHOT_DIR', defaultValue: 'build/visual');

Future<void> _shot(WidgetTester tester, String path) async {
  // 调用点统一写 `build/visual/xxx.png`；这里只换前缀，
  // 让同一套用例能在两个目录下各出一份图。
  final out = path.replaceFirst('build/visual', _shotRoot);
  await tester.binding.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(out);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('截图 $out (${image.width}x${image.height})');
  });
}

/// 界面件换成自绘图标后，按名字找，不再绑定 Material 的 IconData。
Finder _lineIcon(String name) => find.byWidgetPredicate(
  (w) => w is LineIcon && w.name == name,
  description: 'LineIcon($name)',
);

/// 开侧拉栏并点某个入口（1.7.3 起设置类入口只在抽屉里）。
///
/// 早期用例把「我的」页当枢纽，直接点行；入口搬走后这些点法全部失效。
/// 抽屉本身是「页头把手 → 滑出 → 点行」三步，收在这里免得每处各写一遍。
Future<void> _openDrawerAndTap(WidgetTester tester, String label) async {
  // 页头在滚动区里（不是悬浮），翻页之后可能已被滚出视口，先保证把手可见
  await tester.dragUntilVisible(
    find.byType(MenuButton),
    find.byType(Scrollable).first,
    const Offset(0, 200),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(MenuButton));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadChineseFont();
    await _loadIconFont();

    // 截图测试单独用一个库，跟其它测试文件并行跑时互不干扰
    Db.fileName = 'test_shot.db';

    // 从空库开始 —— 否则上一轮留下的演示数据会一层层累积，截图不可复现
    final dir = await databaseFactory.getDatabasesPath();
    final file = File(p.join(dir, Db.fileName));
    if (file.existsSync()) file.deleteSync();
  });

  testWidgets('主界面截图与布局自检', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // ⚠️ 开库与造数据必须放在 runAsync 里。
    // testWidgets 默认在「假时钟」里跑，sqflite 的查询结果在真实事件循环上回包，
    // 假时钟里 await 这些 Future 会永远等不到 —— 直接挂在第一行，连超时都触发不了。
    await tester.runAsync(() async {
      await Store.i.boot();
      await _seedDemoData();
    });

    await tester.pumpWidget(
      RepaintBoundary(key: _shotKey, child: const HeitaApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ---- 明细页 ----
    await _shot(tester, 'build/visual/shot_1_detail.png');
    expect(tester.takeException(), isNull, reason: '明细页有布局溢出');

    // ---- 明细页 · 多选态 ----
    // 多选是这一版新增的交互，没有截图等于没验证：勾选圈的尺寸、操作条的
    // 高度、顶栏「取消 / 已选 N 条 / 全选」挤不挤，只能靠看图确认。
    // 截完必须**退出多选**，否则后面 20 多张都会带着勾选圈跑。
    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.byType(TxnRow).at(0));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(find.byType(TxnRow).at(1));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await _shot(tester, 'build/visual/shot_1b_select.png');
    expect(tester.takeException(), isNull, reason: '多选态有布局溢出');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // ---- 长按菜单 ----
    // 这次给长按加了「多选」入口。三条断言钉住一件事：
    // **多选是加进来的，不是把删除顶掉的** —— 删除一旦从长按消失，
    // 单条删除在界面上就只剩「进多选 → 勾一条 → 删」这一条三步路。
    await tester.longPress(find.byType(TxnRow).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('编辑这笔'), findsOneWidget, reason: '长按菜单丢了「编辑」');
    expect(find.text('多选'), findsOneWidget, reason: '长按菜单丢了「多选」入口');
    expect(find.text('删除这笔'), findsOneWidget, reason: '长按菜单丢了「删除」');
    await _shot(tester, 'build/visual/shot_1c_longpress.png');
    expect(tester.takeException(), isNull, reason: '长按菜单有布局溢出');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // ---- 日历卡片（上下滚动，没有左右翻月）----
    await tester.tap(
      find.text(periodLabel(Store.i.cycleFrom, Store.i.cycleTo)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    // 每日金额是一次异步查询回填的：假时钟里查库永远等不到，必须让出真实事件循环
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await _shot(tester, 'build/visual/shot_14_calendar.png');
    expect(tester.takeException(), isNull, reason: '日历卡片有布局溢出');
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();

    // ---- 图表页 ----
    await tester.tap(find.text('图表'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_2_stats.png');
    expect(tester.takeException(), isNull, reason: '图表页有布局溢出');

    // ---- 计划页 ----
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_3_plan.png');
    expect(tester.takeException(), isNull, reason: '计划页有布局溢出');

    // ---- 往来页（先造一条借出，否则只能截到空态）----
    await tester.runAsync(() async {
      final s = Store.i;
      await Repo.createDebt(
        Debt(
          id: 0,
          ledgerId: s.ledgerId,
          direction: DebtDirection.lent,
          counterparty: '张三',
          amountCents: 500000,
          date: Fmt.today(),
          accountId: s.accounts.first.id,
          dueDate: '2026-11-30',
        ),
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.expense,
          amountCents: 500000,
          date: Fmt.today(),
          accountId: s.accounts.first.id,
        ),
      );
      await s.afterTxnChange();
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('往来'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_22_debts.png');
    expect(tester.takeException(), isNull, reason: '往来页有布局溢出');
    await tester.tap(_lineIcon('arrow_left').first);
    await tester.pumpAndSettle();

    // ---- 我的 ----
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_4_mine.png');
    expect(tester.takeException(), isNull, reason: '我的页有布局溢出');

    // ---- 本地存储说明（2026-10-26 新增）----
    // 这段文案是唯一解释「数据会怎么消失」的地方，措辞改错过一次
    // （原写「卸载即清空」，而 allowBackup 默认开着）。留一张图 + 断言，
    // 免得下次改文案时又把"可能留副本"这层去掉。
    await tester.dragUntilVisible(
      find.text('本地存储'),
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地存储'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_4b_storage_note.png');
    expect(tester.takeException(), isNull, reason: '本地存储说明弹窗有布局溢出');
    expect(find.textContaining('系统备份可能给你留一份副本'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    // ---- 侧拉栏（2026-10-29 新增）----
    // 五组十九个入口挤在一列里，最容易出的事是「某一行文字换行把整列撑高」
    // 或「分组标题的折叠箭头把行高顶歪」—— 两个都只会在真图上显形。
    // 视口保持 390×844（真机尺寸）：抽屉比一屏高是**事实**，不靠拉高视口掩盖。
    // 上一段把页面滚到了「本地存储」那一带，页头（含三横把手）已被滚出视口，
    // 先滚回去 —— 页头在滚动区里，不是固定悬浮的。
    await tester.dragUntilVisible(
      find.byType(MenuButton),
      find.byType(Scrollable).first,
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MenuButton));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_26_drawer.png');
    expect(tester.takeException(), isNull, reason: '侧拉栏有布局溢出');
    expect(find.textContaining('当前账本 ·'), findsOneWidget);
    // 「我的」页自己也有「管理」「关于」这类小节标题，同名文字会撞车 ——
    // 一律限定在 Drawer 子树里找。
    Finder inDrawer(String text) => find.descendant(
      of: find.byType(Drawer),
      matching: find.text(text),
    );
    for (final group in ['账本', '数据', '帮助']) {
      expect(inDrawer(group), findsOneWidget, reason: '侧拉栏缺分组「$group」');
    }

    // 收起一组：只剩标题，入口从树上消失 —— 顺手确认箭头与标题没有错位
    await tester.tap(inDrawer('账本'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_27_drawer_collapsed.png');
    expect(tester.takeException(), isNull, reason: '侧拉栏收起态有布局溢出');
    expect(
      inDrawer('账户管理'),
      findsNothing,
      reason: '收起后组内入口应该真的不在树上',
    );
    // 展开回去：下面几张图（账户 / 分类 / 模板）都要从这一组进
    await tester.tap(inDrawer('账本'));
    await tester.pumpAndSettle();
    expect(inDrawer('账户管理'), findsOneWidget, reason: '「账本」组没展开回去');

    // ---- 首次使用引导（2026-10-29 新增）----
    // 五步整屏，最窄的一步是「侧拉栏」那页（三行说明 + 一个「一次手势可达」），
    // 小屏上最容易把主按钮挤出屏幕。这里拍两页：首页（有「跳过」）与末页
    // （文案换成「开始记账」、上一步按钮存在）。
    //
    // 「帮助」组落在首屏之外（抽屉比屏幕高），先滚到它 —— 这本身也是
    // 「入口真的够得着」的验证，比把视口拉高到 1400 更有意义。
    final drawerList = find
        .descendant(of: find.byType(Drawer), matching: find.byType(Scrollable))
        .first;
    await tester.dragUntilVisible(
      find.text('帮助与引导'),
      drawerList,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    // 「帮助说明 / 重看使用引导」1.7.3 起收在「帮助与引导」的二级菜单里
    // （两项读的是同一批文档，平铺两行反而让人以为内容不同）。
    await tester.tap(find.text('帮助与引导'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重看使用引导'));
    await tester.pump(const Duration(milliseconds: 400)); // 抽屉先收完再 push
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_28_onboarding_1.png');
    expect(tester.takeException(), isNull, reason: '引导首页有布局溢出');
    expect(find.text('跳过'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }
    await _shot(tester, 'build/visual/shot_29_onboarding_last.png');
    expect(tester.takeException(), isNull, reason: '引导末页有布局溢出');
    expect(find.text('开始记账'), findsOneWidget);
    expect(find.text('上一步'), findsOneWidget);

    // 走完退出（落库不 await，这里只等界面回来）
    await tester.tap(find.text('开始记账'));
    await tester.pumpAndSettle();

    // ---- 账户管理（二级：列表弹层，行尾还挂一颗 ⋯）----
    // 这一层是「菜单组 + 自定义行」的混排，菜单件改版后要亲眼确认行高与
    // 分割线没错位，所以单独留一张。
    await _openDrawerAndTap(tester, '账户管理');
    await _shot(tester, 'build/visual/shot_25_accounts_sheet.png');
    expect(tester.takeException(), isNull, reason: '账户管理弹层有布局溢出');
    // 点空白处关掉，回到我的页
    await tester.tapAt(const Offset(195, 80));
    await tester.pumpAndSettle();

    // ---- 分类管理（一级列表）----
    await _openDrawerAndTap(tester, '分类管理');
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_16_cats.png');
    expect(tester.takeException(), isNull, reason: '分类管理页有布局溢出');

    // ---- 分类管理（停用一个，看末尾的「已停用」段）----
    // 挑最后一个（「其他」），不影响后面点「餐饮」进子分类
    final victim = Store.i.expenseCats.last;
    await tester.runAsync(() async {
      await Repo.setCategoryArchived(victim.id, archived: true);
      await Store.i.afterCategoryChange();
    });
    await tester.pumpAndSettle();
    // 停用段在列表末尾，先滚到底，才能看到「恢复」有没有被悬浮按钮压住
    await tester.dragUntilVisible(
      find.text('恢复'),
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_23_cats_archived.png');
    expect(tester.takeException(), isNull, reason: '「已停用」段有布局溢出');
    // 拍完复原，后面的截图仍按「全部分类都在」的状态走
    await tester.runAsync(() async {
      await Repo.setCategoryArchived(victim.id, archived: false);
      await Store.i.afterCategoryChange();
    });
    await tester.pumpAndSettle();
    // 刚才滚到了底部，这里滚回顶部 —— 后面要点「餐饮」进子分类，它在第一行
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pumpAndSettle();

    // ---- 子分类列表（以餐饮为例）----
    await tester.tap(find.text('餐饮').first);
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_17_subcats.png');
    expect(tester.takeException(), isNull, reason: '子分类页有布局溢出');
    // 这两页用的是自绘返回按钮，tester.pageBack() 找不到系统返回键
    await tester.tap(_lineIcon('arrow_left').first);
    await tester.pumpAndSettle();
    await tester.tap(_lineIcon('arrow_left').first);
    await tester.pumpAndSettle();

    // ---- 模板管理 ----
    await _openDrawerAndTap(tester, '记账模板');
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_6_templates.png');
    expect(tester.takeException(), isNull, reason: '模板页有布局溢出');

    // ---- 模板编辑页 ----
    await tester.tap(find.text('早餐'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_7_template_editor.png');
    expect(tester.takeException(), isNull, reason: '模板编辑页有布局溢出');
    await tester.tap(_lineIcon('arrow_left'));
    await tester.pumpAndSettle();
    // 回到「我的」
    await tester.tap(_lineIcon('arrow_left'));
    await tester.pumpAndSettle();

    // ---- 记一笔面板 ----
    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    // 「＋」是圆形按钮，不是 Icon，用坐标点最稳（底栏 60 高，圆心在 802 附近）
    await tester.tapAt(const Offset(195, 802));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await _shot(tester, 'build/visual/shot_5_record.png');
    expect(tester.takeException(), isNull, reason: '记一笔面板有布局溢出');

    // ---- 记一笔：填了金额的样子（确认键变成可用的重色块）----
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_15_record_filled.png');
    expect(tester.takeException(), isNull, reason: '记一笔（有金额）有布局溢出');

    // ---- 分类 + 子分类双轮盘 ----
    await tester.tap(find.textContaining('未细分'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_11_note_wheel.png');
    expect(tester.takeException(), isNull, reason: '双轮盘有布局溢出');

    // ---- 详情字段（出行）：默认折叠 ----
    // 左轮滚一格（餐饮 → 出行），右轮滚一格（不细分 → 公共交通）后确定
    await tester.drag(find.byType(CupertinoPicker).at(0), const Offset(0, -52));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).at(1), const Offset(0, -52));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_18_detail_folded.png');
    expect(tester.takeException(), isNull, reason: '详情折叠态有布局溢出');

    // ---- 详情字段（出行）：展开 ----
    await tester.tap(find.text('＋ 添加详情'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_19_detail_open.png');
    expect(tester.takeException(), isNull, reason: '详情展开态有布局溢出');

    // ---- 详情字段（人情）：对象直接平铺 ----
    // 展开详情会自动滚到底（否则新字段落在键盘下方），分类行被推出可视区
    // —— 先收起，内容变短后滚动位置会自己回到顶部，才能点回分类行
    await tester.tap(find.text('收起详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('出行').first);
    await tester.pumpAndSettle();
    // 左轮从出行滚到人情（出行 → 居家 → 购物 → 健康 → 娱乐 → 人情，共 5 格）
    await tester.drag(
      find.byType(CupertinoPicker).at(0),
      const Offset(0, -52.0 * 5),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).at(1), const Offset(0, -52));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_20_detail_inline.png');
    expect(tester.takeException(), isNull, reason: '人情对象平铺有布局溢出');

    // 复位到「餐饮 / 不细分」：详情区会把面板撑高，后面的日期/账户截图要求它够短
    await tester.tap(find.textContaining('人情').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CupertinoPicker).at(0),
      const Offset(0, 52.0 * 5),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // ---- 日期选择 ----
    await tester.tap(find.byKey(const ValueKey('record_date_chip')));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await _shot(tester, 'build/visual/shot_12_date_picker.png');
    expect(tester.takeException(), isNull, reason: '日期选择有布局溢出');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // ---- 账户选择 ----
    await tester.tap(find.byKey(const ValueKey('record_account_chip')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_13_account_sheet.png');
    expect(tester.takeException(), isNull, reason: '账户选择有布局溢出');
    await tester.tapAt(const Offset(195, 80));
    await tester.pumpAndSettle();

    // ---- 筛选面板 ----
    // 先点遮罩把记一笔关掉（面板占了下半屏，顶部遮罩还能点到）
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await _shot(tester, 'build/visual/shot_8_filter_sheet.png');
    expect(tester.takeException(), isNull, reason: '筛选面板有布局溢出');

    // ---- 筛选中二级分类：点「餐饮」后下面多出一排子分类 ----
    await tester.tap(
      find.descendant(of: find.byType(CategoryGrid), matching: find.text('餐饮')),
    );
    await tester.pump(const Duration(milliseconds: 300)); // 走完去抖
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_21_filter_subcats.png');
    expect(tester.takeException(), isNull, reason: '子分类筛选排有布局溢出');

    // ---- 筛选生效后的明细页 ----
    // 面板里的实时计数会走真实数据库（假时钟里 await 不到），这里直接从
    // Store 应用条件，专门验证明细页筛选态的版式：条件条 + 结果摘要 + 列表
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final cats = await Repo.listCategories(
        Store.i.ledgerId,
        type: TxnType.expense,
      );
      final food = cats.firstWhere((c) => c.name == '餐饮').id;
      await Store.i.applyFilter(
        TxnFilter(categoryId: food, minCents: 2000, maxCents: 20000),
      );
    });
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_9_filter_result.png');
    expect(tester.takeException(), isNull, reason: '筛选结果页有布局溢出');

    // ---- 筛选空结果态 ----
    await tester.runAsync(() async {
      await Store.i.applyFilter(const TxnFilter(minCents: 999999900));
    });
    await tester.pumpAndSettle();
    await _shot(tester, 'build/visual/shot_10_filter_empty.png');
    expect(tester.takeException(), isNull, reason: '筛选空结果页有布局溢出');

    // ---- 数据安全（自动快照列表）----
    // 单测里没有 path_provider 的平台通道，快照目录指到临时目录
    final snapDir = Directory.systemTemp.createTempSync('heita_shot_');
    BackupService.snapshotDirOverride = () async => snapDir;
    addTearDown(() {
      BackupService.snapshotDirOverride = null;
      try {
        if (snapDir.existsSync()) snapDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows 上临时目录偶尔还被句柄占着（截图用的 png 刚关）。
        // 只是个临时目录，删不掉就留给系统，不值得让整条测试挂掉。
      }
    });
    await tester.runAsync(() => BackupService.writeSnapshot(reason: 'wipe'));
    // 必须自己套一层 RepaintBoundary(_shotKey)：整棵树被换掉之后，
    // _shot() 找的就是这个 key，漏了会直接空指针。
    //
    // 建树也放进 runAsync：页面的 initWithState 里就要读文件（listSnapshots），
    // 在假时钟里那个 Future 永远回不来，会一直卡在加载态。
    await tester.runAsync(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _shotKey,
          child: MaterialApp(
            theme: buildAppTheme(),
            debugShowCheckedModeBanner: false, // 否则右上角会盖一条 DEBUG 斜带
            home: const SafetyPage(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // 原来这里只 `pump()` 一次，靠前面那个固定 300ms 赌「文件 IO 已经回来」。
    // 改成**有界等待**加载态结束，少一个时间赌注。
    // （不用 pumpAndSettle：加载态里是 `CircularProgressIndicator`，无限动画，
    //   settle 会一直等到超时。）
    //
    // ⚠️ 注意：这张图**仍然不是完全确定的**。对拍实测差 45~90 个像素，
    //    包围盒落在 x177..184 / y442..452 —— 一个字符宽，是页面上那行
    //    「快照体积/时间」：测试每次都会 writeSnapshot 写一份新文件，
    //    内容里的时间戳不同、体积就不同，那一位数字必然变。
    //    所以 `tools/visual_diff.py` 跑这张图时要 `--exclude shot_24_safety`。
    //    真要让它稳定，得让这个用例读固定 fixture，而不是现写一份 —— 留作后续。
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await _shot(tester, 'build/visual/shot_24_safety.png');
    expect(tester.takeException(), isNull, reason: '数据安全页有布局溢出');
  });

  // ---- 记一笔 · 键盘让位三档截图（#6）----
  //
  // ## 为什么必须是「图」而不是断言
  //
  // 自动化能证明的只有一件事：**面板顶边在输入法升降全程不跳**（
  // `record_note_layout_test` 60 帧 × 5dp、容差 2dp）。它证明不了「好看」——
  // 去掉 40dp 门槛之后，输入法完全升起时槽里会留 24dp 的碎边（第一排键的顶边
  // 被剪下来的一条），靠槽下沿一条 24dp 渐隐溶进卡面。溶得干不干净、会不会
  // 看起来像「画坏了的一道横线」，只能看图。这是 #6 唯一可能被真机否掉的地方。
  //
  // ## 三档取在门槛附近
  //
  // 键盘自然高度 324（56 键高）；旧行为在 `槽高 < 40` 时整块收掉，所以：
  //
  // | viewInsets | 槽高 | 这一档要看什么 |
  // |---|---|---|
  // | 0          | 324  | 满键盘：**绝不能有任何渐隐**（会把「0 / . / 确认」溶掉） |
  // | 280        | 44   | 刚过旧门槛一点：旧代码在 44 还是完整、39 就整块没了 |
  // | 300        | 24   | 典型碎边：一排键被剪掉一条，靠渐隐溶掉 |
  //
  // 三张都要 `takeException()` 为 null —— 图再好看，溢出也是错的。
  testWidgets('记一笔 · 键盘让位三档截图（#6）', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());

    await tester.pumpWidget(
      RepaintBoundary(key: _shotKey, child: const HeitaApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 打开「记一笔」（底栏 60 高，圆的「＋」圆心在 802 附近）
    await tester.tapAt(const Offset(195, 802));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // 三档都要**有备注内容**：键盘收起时那一屏如果空空如也，就看不出
    // 「被输入法压住的是什么」。写一句真实的备注。
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '楼下那家面馆，加了两个卤蛋',
    );
    await tester.pumpAndSettle();

    /// 摆一个输入法高度并截图。[imeDp] 是逻辑像素。
    Future<void> shotAt(String name, double imeDp) async {
      tester.view.viewInsets = FakeViewPadding(bottom: imeDp * 2);
      await tester.pumpAndSettle();
      // 槽高是这个用例的核心变量：断言一次，免得以后别人改了公式、
      // 截图还在、却不是当初那三档了。
      final slotFinder = find.byKey(const ValueKey('record_keypad_slot'));
      final slotH = slotFinder.evaluate().isEmpty
          ? 0.0
          : tester.getSize(slotFinder).height;
      expect(
        slotH,
        closeTo((324 - imeDp).clamp(0.0, 324.0), 0.5),
        reason: '输入法 ${imeDp}dp 时槽高应当是 ${324 - imeDp}dp，实际 $slotH',
      );
      await _shot(tester, 'build/visual/$name');
      expect(tester.takeException(), isNull, reason: '$name 有布局溢出');
    }

    await shotAt('shot_kb_000.png', 0);
    await shotAt('shot_kb_280.png', 280);
    await shotAt('shot_kb_300.png', 300);

    // 满键盘那一张必须**没有**渐隐层：`shatterFade == 0` 时这一层根本不出现。
    // 反过来断言一次，免得将来把渐隐写成「永远画」—— 那会把真键溶掉。
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('record_keypad_shatter_fade')),
      findsNothing,
      reason: '满键盘不该有碎边渐隐 —— 它会把「0 / . / 确认」这排真键溶掉',
    );
  });
}

/// 造一批贴近真实的演示数据：整月零散支出 + 两笔收入 + 一个超支分类
Future<void> _seedDemoData() async {
  final store = Store.i;
  final ledgerId = store.ledgerId;
  final month = Fmt.month(DateTime.now());

  Future<int?> cat(String name, TxnType type) async {
    final list = await Repo.listCategories(ledgerId, type: type);
    for (final c in list) {
      if (c.name == name) return c.id;
    }
    return null;
  }

  final food = await cat('餐饮', TxnType.expense);
  final transport = await cat('出行', TxnType.expense);
  final shopping = await cat('购物', TxnType.expense);
  final home = await cat('居家', TxnType.expense);
  final fun = await cat('娱乐', TxnType.expense);
  final salary = await cat('工资', TxnType.income);

  final accounts = store.accounts;
  final cash = accounts.isEmpty ? null : accounts.first.id;
  final alipay = accounts.length > 1
      ? accounts[1].id
      : (accounts.isEmpty ? null : accounts.first.id);

  final rows = <(int, String, TxnType, int, int?, int?, String)>[
    (12, '$month-01', TxnType.expense, 2800, food, cash, '早餐'),
    (11, '$month-01', TxnType.expense, 600, transport, cash, '地铁'),
    (10, '$month-02', TxnType.expense, 12800, food, alipay, '和同事聚餐'),
    (9, '$month-03', TxnType.expense, 39900, shopping, alipay, '换了个键盘'),
    (8, '$month-05', TxnType.expense, 150000, home, alipay, '房租'),
    (7, '$month-06', TxnType.expense, 4500, transport, cash, '打车'),
    (6, '$month-08', TxnType.expense, 6800, fun, alipay, '电影票'),
    (5, '$month-09', TxnType.expense, 2350, food, cash, '午饭'),
    (4, '$month-10', TxnType.expense, 19900, shopping, alipay, '外套'),
    (3, '$month-11', TxnType.expense, 3200, food, cash, '奶茶'),
  ];

  for (final r in rows) {
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: r.$3,
        amountCents: r.$4,
        date: r.$2,
        categoryId: r.$5,
        accountId: r.$6,
        note: r.$7,
      ),
    );
  }

  await Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.income,
      amountCents: 1280000,
      date: '$month-10',
      categoryId: salary,
      accountId: alipay,
      note: '10月工资',
    ),
  );

  // 预算：总预算 + 一个必然超支的分类（用于验证红色警示）
  await Repo.setBudget(
    ledgerId: ledgerId,
    periodStart: '$month-01',
    amountCents: 600000,
  );
  if (food != null) {
    await Repo.setBudget(
      ledgerId: ledgerId,
      periodStart: '$month-01',
      categoryId: food,
      amountCents: 120000,
    );
  }
  if (transport != null) {
    await Repo.setBudget(
      ledgerId: ledgerId,
      periodStart: '$month-01',
      categoryId: transport,
      amountCents: 30000,
    );
  }

  // 储蓄目标
  await Repo.insertGoal(
    const SavingGoal(
      id: 0,
      name: '旅行基金',
      icon: 'plane',
      targetCents: 2000000,
      savedCents: 850000,
      dueMonth: '2027-06',
    ),
  );
  await Repo.insertGoal(
    const SavingGoal(
      id: 0,
      name: '换电脑',
      icon: 'laptop',
      targetCents: 800000,
      savedCents: 230000,
    ),
  );
  await Repo.insertGoal(
    const SavingGoal(
      id: 0,
      name: '应急金',
      icon: 'wallet',
      targetCents: 3000000,
      savedCents: 1260000,
    ),
  );

  // 记账模板：四张，「早餐」「地铁」用过几次 —— 顶部那排模板的排序靠它
  final tplBreakfast = await Repo.insertTemplate(
    TxnTemplate(
      id: 0,
      ledgerId: ledgerId,
      name: '早餐',
      icon: 'food',
      type: TxnType.expense,
      amountCents: 1200,
      categoryId: food,
      accountId: cash,
      note: '包子 + 豆浆',
    ),
  );
  final tplMetro = await Repo.insertTemplate(
    TxnTemplate(
      id: 0,
      ledgerId: ledgerId,
      name: '地铁',
      icon: 'transport',
      type: TxnType.expense,
      amountCents: 600,
      categoryId: transport,
      accountId: cash,
    ),
  );
  await Repo.insertTemplate(
    TxnTemplate(
      id: 0,
      ledgerId: ledgerId,
      name: '房租',
      icon: 'home',
      type: TxnType.expense,
      amountCents: 150000,
      categoryId: home,
      accountId: alipay,
      note: '每月 5 号',
    ),
  );
  await Repo.insertTemplate(
    TxnTemplate(
      id: 0,
      ledgerId: ledgerId,
      name: '奶茶',
      icon: 'food',
      type: TxnType.expense,
      amountCents: 0,
      categoryId: food,
      accountId: alipay,
    ),
  );
  for (var i = 0; i < 3; i++) {
    await Repo.touchTemplate(tplBreakfast);
  }
  await Repo.touchTemplate(tplMetro);

  await store.loadAll();
}
