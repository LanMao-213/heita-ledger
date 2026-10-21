import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/ui/pages/category/category_editor.dart';
import 'package:heita_ledger/ui/pages/category/cats_page.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';
import '../support/ui_fixture.dart';

/// 分类编辑器：空名不保存、图标墙种子优先、三个动作（保存 / 停用 / 删除）各自带回什么。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<CategoryAction? Function()> open(
    WidgetTester tester, {
    Category? category,
    TxnType type = TxnType.expense,
    int? parentId,
  }) async {
    final _Holder holder = _Holder();
    final UiHarness h = UiHarness();
    await h.load();
    await h.pump(
      tester,
      host(
        Builder(
          builder: (BuildContext ctx) => TextButton(
            onPressed: () async {
              holder.action = await showCategoryEditor(
                ctx,
                type: type,
                category: category,
                parentId: parentId,
              );
            },
            child: const Text('open-editor'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-editor'));
    await tester.pumpAndSettle();
    return () => holder.action;
  }

  testWidgets('③ 空名不保存：toast 提示，面板不关', (WidgetTester tester) async {
    final CategoryAction? Function() result = await open(tester);

    await tester.tap(find.byKey(const ValueKey<String>('cat-save')));
    await tester.pumpAndSettle();

    expect(find.text('名字不能为空'), findsOneWidget);
    expect(result(), isNull, reason: '面板还开着，没交回任何动作');
    expect(find.byKey(const ValueKey<String>('cat-name')), findsOneWidget);
  });

  testWidgets('③ 填名字 + 选图标 → 交回 SaveCategory', (WidgetTester tester) async {
    final CategoryAction? Function() result = await open(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('cat-name')),
      '咖啡',
    );
    await tester.tap(find.byKey(const ValueKey<String>('cat-icon-cup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('cat-save')));
    await tester.pumpAndSettle();

    final CategoryAction? action = result();
    expect(action, isA<SaveCategory>());
    final SaveCategory save = action! as SaveCategory;
    expect(save.draft.name, '咖啡');
    expect(save.draft.icon, 'cup');
    expect(save.draft.id, isNull, reason: '新建 → 没有 id');
  });

  testWidgets('③ 子页新建时 parentId 被带进 draft', (WidgetTester tester) async {
    final int top = await topCategoryId();
    final CategoryAction? Function() result = await open(
      tester,
      parentId: top,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('cat-name')),
      '下午茶',
    );
    await tester.tap(find.byKey(const ValueKey<String>('cat-save')));
    await tester.pumpAndSettle();

    final SaveCategory save = result()! as SaveCategory;
    expect(save.draft.parentId, top);
  });

  testWidgets('④ 编辑态：交回 ArchiveCategory（携带 id 与目标状态）', (
    WidgetTester tester,
  ) async {
    final int top = await topCategoryId();
    final Category cat = (await Repo.category.tree(
      await currentLedger(),
    )).byId(top)!;
    final CategoryAction? Function() result = await open(
      tester,
      category: cat,
    );

    expect(find.text('编辑分类'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('cat-archive')));
    await tester.pumpAndSettle();

    final ArchiveCategory archive = result()! as ArchiveCategory;
    expect(archive.categoryId, top);
    expect(archive.archived, isTrue, reason: '当前没停用 → 动作是「停用」');
  });

  testWidgets('⑤ 编辑态：交回 DeleteCategory', (WidgetTester tester) async {
    final int top = await topCategoryId();
    final Category cat = (await Repo.category.tree(
      await currentLedger(),
    )).byId(top)!;
    final CategoryAction? Function() result = await open(
      tester,
      category: cat,
    );

    await tester.tap(find.byKey(const ValueKey<String>('cat-delete')));
    await tester.pumpAndSettle();

    final DeleteCategory del = result()! as DeleteCategory;
    expect(del.categoryId, top);
  });

  test('③ 图标墙：种子用过的图标排在最前，导航图标被剔除', () {
    final List<String> icons = categoryIcons(seedIconNames());

    expect(icons.first, 'utensils', reason: '种子第一个是「餐饮」');
    expect(icons, isNot(contains('pie')));
    expect(icons, isNot(contains('list')));
    // 种子图标全集都在（去重后）
    final Set<String> seeds = seedIconNames().toSet();
    for (final String s in seeds) {
      if (kNavIconsForCategory.contains(s)) continue;
      expect(icons, contains(s));
    }
    // 不与全量重复
    expect(icons.length, icons.toSet().length);
  });

  test('停用文案说清「不级联子分类、历史仍显示原名」', () {
    expect(archiveCategoryBody, contains('子分类不会被一起停用'));
    expect(archiveCategoryBody, contains('原来的名字'));
  });
}

class _Holder {
  CategoryAction? action;
}
