// 二级 / 三级菜单统一件（widgets/menu.dart）的守门测试。
//
// 为什么值得写：这一轮把全 App 的弹层从「谁用到谁随手搭」收成一套件，
// 收的是**形状约定**，不是某一处的颜色。约定写在文档里会慢慢烂掉 ——
// 弹层底必须是页面底、菜单项必须装进圆角卡、分割线必须内缩到 46、
// 「取消」必须独立成卡、危险按钮必须是 C.over —— 这些要靠测试钉住，
// 否则过两个月又有人手写一次 showModalBottomSheet，界面重新散开。
//
// 另一半是行为：菜单项点了要**先关弹层再执行动作**（漏一处就是「点了没
// 反应」），选择弹层要把选中的值带回去，PickField 点开要能选。
//
// ⚠️ 写这类测试的一个坑：`await showMenuSheet(...)` 会**一直等**到弹层被
// 关掉才返回。想断言弹层里的东西，只能先存下 Future、pump，最后再 await。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/design/palette.dart';
import 'package:ledger/design/theme_ctrl.dart';
import 'package:ledger/design/tokens.dart';
import 'package:ledger/widgets/menu.dart';

void main() {
  setUp(() => ThemeCtrl.i.loadSilently(kPalettes.first.id));

  /// 一个空的宿主页，用来给弹层提供 Navigator。
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
    return tester.element(find.byType(Scaffold));
  }

  group('二级菜单的形状', () {
    testWidgets('弹层底是页面底，菜单组装在卡面圆角卡里', (tester) async {
      final ctx = await pumpHost(tester);
      showMenuSheet<void>(
        context: ctx,
        title: '招商银行',
        groups: [
          MenuGroup(
            actions: [MenuAction(icon: 'tpl', title: '编辑资料', onTap: () {})],
          ),
        ],
      );
      await tester.pumpAndSettle();

      // 弹层底：SheetShell 画的那一层必须是页面底
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == C.bg,
        ),
        findsOneWidget,
        reason: '弹层底必须是 C.bg（页面底）；用卡面的话菜单行会和底同色',
      );

      // 菜单组：白卡浮在底上
      expect(
        find.byWidgetPredicate((w) => w is Material && w.color == C.cardBg),
        findsWidgets,
        reason: '菜单项要装在 C.cardBg 的圆角卡里',
      );

      expect(find.text('招商银行'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      // 把手：36×4，全站一个尺寸
      final handles = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .map((c) => c.decoration! as BoxDecoration)
          .where((d) => d.color == C.line2);
      expect(handles, isNotEmpty, reason: '弹层顶上要有把手');
    });

    testWidgets('菜单项点了先关弹层，再执行动作', (tester) async {
      final ctx = await pumpHost(tester);
      var edited = false;
      final fut = showMenuSheet<void>(
        context: ctx,
        title: '招商银行',
        groups: [
          MenuGroup(
            actions: [
              MenuAction(
                icon: 'tpl',
                title: '编辑资料',
                onTap: () => edited = true,
              ),
            ],
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('编辑资料'));
      await tester.pumpAndSettle();
      expect(edited, isTrue, reason: '菜单项点了要执行回调');
      expect(find.text('编辑资料'), findsNothing, reason: '点完要关掉弹层');
      await fut;
    });

    testWidgets('分割线内缩到 46，不横穿整行', (tester) async {
      final ctx = await pumpHost(tester);
      showMenuSheet<void>(
        context: ctx,
        title: '标题',
        groups: [
          MenuGroup(
            actions: [
              MenuAction(icon: 'tpl', title: '第一条'),
              MenuAction(icon: 'trash', title: '第二条', danger: true),
            ],
          ),
        ],
      );
      await tester.pumpAndSettle();

      final dividers = tester
          .widgetList<Divider>(find.byType(Divider))
          .toList();
      expect(dividers, isNotEmpty, reason: '组里有多条就该有分割线');
      for (final d in dividers) {
        expect(d.indent, MenuGroup.kIndent, reason: '分割线要内缩到文字左边');
        expect(d.color, C.line);
      }
    });

    testWidgets('危险项图标与文字一起转 C.over', (tester) async {
      final ctx = await pumpHost(tester);
      showMenuSheet<void>(
        context: ctx,
        title: '标题',
        groups: [
          MenuGroup(
            actions: [MenuAction(icon: 'trash', title: '删除账户', danger: true)],
          ),
        ],
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('删除账户'));
      expect(text.style?.color, C.over, reason: '危险项的字必须是 C.over');
    });
  });

  group('三级对话框', () {
    testWidgets('取消是次级色，确认是主色，危险是 C.over', (tester) async {
      final ctx = await pumpHost(tester);
      final fut = showAppConfirm(
        ctx,
        title: '删除「招商银行」？',
        message: '余额和记录会转到别的账户',
        confirmLabel: '删除',
        danger: true,
      );
      await tester.pumpAndSettle();

      final cancel = tester.widget<Text>(find.text('取消'));
      final confirm = tester.widget<Text>(find.text('删除'));
      expect(cancel.style?.color, C.ink2, reason: '取消键用次级墨色');
      expect(confirm.style?.color, C.over, reason: '危险确认键用 C.over');
      expect(confirm.style?.fontWeight, FontWeight.w600);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await fut, isFalse, reason: '点取消要返回 false');
    });

    testWidgets('确认键返回 true', (tester) async {
      final ctx = await pumpHost(tester);
      final fut = showAppConfirm(ctx, title: '确定吗', confirmLabel: '确定');
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(await fut, isTrue);
    });

    testWidgets('两个按钮等宽，中间一道竖线', (tester) async {
      final ctx = await pumpHost(tester);
      showAppConfirm(ctx, title: '确定吗');
      await tester.pumpAndSettle();

      expect(
        tester.widgetList<Expanded>(find.byType(Expanded)).length,
        2,
        reason: '两个按钮各占一半',
      );
      expect(find.byType(VerticalDivider), findsOneWidget);
    });

    testWidgets('表单类对话框的确认键在点下去那一刻才取值', (tester) async {
      final ctx = await pumpHost(tester);
      final ctl = TextEditingController();
      final fut = showAppDialog<String>(
        context: ctx,
        title: '新建账本',
        content: TextField(controller: ctl),
        actions: [
          const DialogAction(label: '取消'),
          DialogAction(
            label: '创建',
            valueOf: () => ctl.text.trim(),
            strong: true,
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '装修账本');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      expect(await fut, '装修账本', reason: '要读输入框里的当前文本，不是建对话框时的空串');
    });
  });

  group('选择类弹层', () {
    testWidgets('点哪条把哪条的值带回去', (tester) async {
      final ctx = await pumpHost(tester);
      final fut = showPickSheet<int>(
        context: ctx,
        title: '并到哪个账户',
        options: const [
          PickOption(value: 1, icon: 'wallet', title: '现金'),
          PickOption(value: 2, icon: 'card', title: '招行'),
        ],
        current: 1,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('招行'));
      await tester.pumpAndSettle();
      expect(await fut, 2);
    });

    testWidgets('PickField 点开弹层，选完回填', (tester) async {
      var picked = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setLocal) => PickField(
                label: '账户',
                valueText: picked == 0 ? '' : '账户 $picked',
                onTap: () async {
                  final v = await showPickSheet<int>(
                    context: ctx,
                    title: '用哪个账户',
                    options: const [
                      PickOption(value: 7, icon: 'wallet', title: '零钱'),
                    ],
                  );
                  if (v != null) setLocal(() => picked = v);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('请选择'), findsOneWidget, reason: '没选时显示占位');
      await tester.tap(find.byType(PickField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('零钱'));
      await tester.pumpAndSettle();
      expect(picked, 7);
      expect(find.text('账户 7'), findsOneWidget);
    });
  });
}
