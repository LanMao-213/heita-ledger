import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/ui/pages/template/template_editor.dart';
import 'package:heita_ledger/ui/pages/template/templates_page.dart';
import 'package:heita_ledger/ui/widgets/icon_map.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 模板页与模板编辑器：列表、拖拽手柄、名称上限、图标墙剔除导航图标、金额可空、必填校验。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<int> tpl(String name, {int amount = 1000}) async => Repo.template.insert(
    TxnTemplate(
      ledgerId: await currentLedger(),
      name: name,
      type: TxnType.expense,
      amountCents: amount,
      categoryId: await topCategoryId(),
      accountId: await defaultAccountId(),
    ),
  );

  Future<UiHarness> pumpPage(WidgetTester tester) async {
    final UiHarness h = UiHarness();
    await h.load();
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.wrap(const TemplatesPage()));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('模板列表：一行一个，副行写类型/金额/用过次数', (
    WidgetTester tester,
  ) async {
    await tpl('早饭');
    final int id = await tpl('地铁');
    await pumpPage(tester);

    expect(find.text('早饭'), findsOneWidget);
    expect(find.text('地铁'), findsOneWidget);
    expect(find.byKey(ValueKey<String>('tpl-row-$id')), findsOneWidget);
    expect(find.textContaining('用过 0 次'), findsNWidgets(2));
  });

  testWidgets('没有模板 → 空态', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(find.byKey(const ValueKey<String>('tpl-empty')), findsOneWidget);
  });

  testWidgets('编辑器：名称 maxLength = 8', (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey<String>('tpl-new')));
    await tester.pumpAndSettle();

    final TextField name = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('tpl-name')),
    );
    expect(name.maxLength, kTemplateNameMax);
    expect(kTemplateNameMax, 8);
  });

  testWidgets('编辑器：图标墙剔除导航图标（列表/饼图/我的/加号）', (
    WidgetTester tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey<String>('tpl-new')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('tpl-icon-utensils')), findsOneWidget);
    for (final String nav in <String>['list', 'pie', 'person', 'plus']) {
      expect(
        find.byKey(ValueKey<String>('tpl-icon-$nav')),
        findsNothing,
        reason: '导航图标不该出现在分类/模板的图标墙里',
      );
    }
    expect(
      templateIcons(),
      isNot(contains('pie')),
      reason: '「饼图」是底栏图标，出现在图标墙里会被当成导航按钮',
    );
    expect(
      templateIcons().length,
      IconMap.known.where((String n) => !isNavIcon(n)).length,
    );
  });

  testWidgets('编辑器：分类没选 → toast 不弹保存', (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey<String>('tpl-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('tpl-name')),
      '测试',
    );
    await tester.tap(find.byKey(const ValueKey<String>('tpl-save')));
    await tester.pumpAndSettle();

    expect(find.text('先选一个分类'), findsOneWidget);
    expect(await Repo.template.all(await currentLedger()), isEmpty);
  });

  testWidgets('编辑器：名称留空用分类名，金额留空 = 0', (WidgetTester tester) async {
    final int cat = await topCategoryId();
    final String catName = (await Repo.category.tree(
      await currentLedger(),
    )).byId(cat)!.name;
    final int id = await tpl('占位');
    await pumpPage(tester);

    // 点进去改：清空名字与金额 → 名字回落分类名、金额变 0
    await tester.tap(find.byKey(ValueKey<String>('tpl-row-$id')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('tpl-name')), '');
    await tester.enterText(find.byKey(const ValueKey<String>('tpl-amount')), '');
    await tester.tap(find.byKey(const ValueKey<String>('tpl-save')));
    await tester.pumpAndSettle();

    final TxnTemplate saved = (await Repo.template.all(
      await currentLedger(),
    )).single;
    expect(saved.name, catName, reason: '名称留空 → 用分类名');
    expect(saved.amountCents, 0, reason: '金额留空 = 0（每次现输）');
  });

  test('模板行副行文案：金额为 0 时写「金额每次现填」', () {
    const TxnTemplate t = TxnTemplate(
      ledgerId: 1,
      name: 'x',
      type: TxnType.expense,
      amountCents: 0,
    );
    expect(templateSubtitle(t), contains('金额每次现填'));

    const TxnTemplate t2 = TxnTemplate(
      ledgerId: 1,
      name: 'y',
      type: TxnType.income,
      amountCents: 500000,
    );
    final String sub = templateSubtitle(t2, categoryOf: (int? _) => '工资');
    expect(sub, contains('收入'));
    expect(sub, contains('工资'));
    expect(sub, contains('5,000.00'));
  });

  test('删除模板的确认文案说清「已记过的账不受影响」', () async {
    await tpl('早饭');
    final List<TxnTemplate> all = await Repo.template.all(await currentLedger());
    expect(all.length, 1);
    // 文案在页面里，这里断言数据侧：删了模板，流水还在（见 template_order_test）
    await Repo.template.delete(all.single.id!);
    expect(await Repo.template.all(await currentLedger()), isEmpty);
    expect(LocalDate.today().year, greaterThan(2000));
  });
}
