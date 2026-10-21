import 'package:flutter/material.dart';

import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/category_repo.dart';
import '../../../data/repo/repo.dart';
import '../../../stores/catalog_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/chip_tabs.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/icon_map.dart';
import '../../widgets/section_header.dart';
import '../../widgets/toast.dart';
import 'category_editor.dart';
import 'sub_cats_page.dart';

/// 分类管理（一级）。支出 / 收入两档、拖拽只写**当前层**的 `sort_order`。
///
/// 两级是**硬上限**：这里没有「进入第三层」的入口，数据层
/// （`CategoryRepo.insert` 的 `_validateParent`）也会拦。
class CatsPage extends StatefulWidget {
  const CatsPage({super.key});

  @override
  State<CatsPage> createState() => _CatsPageState();
}

class _CatsPageState extends State<CatsPage> {
  TxnType _type = TxnType.expense;
  bool _busy = false;

  Future<void> _refresh() async {
    if (!mounted) return;
    await CatalogScope.of(context).reloadCategories();
  }

  /// 一级页的行 = 未停用的一级（按 sort_order）+ 末尾「已停用」段。
  List<Category> _tops(CategoryTree tree) => <Category>[
    for (final Category c in tree.tops)
      if (c.type == _type && !c.archived) c,
  ];

  List<Category> _archivedTops(CategoryTree tree) => <Category>[
    for (final Category c in tree.tops)
      if (c.type == _type && c.archived) c,
  ];

  Future<void> _reorder(List<Category> list, int oldIndex, int newIndex) async {
    final List<Category> next = <Category>[...list];
    final Category moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    // **只写当前层**：把这一层重编号成 0..n-1，别碰别的层
    await Repo.category.reorder(<int>[for (final Category c in next) c.id!]);
    await _refresh();
  }

  Future<void> _addTop() async {
    final CategoryAction? action = await showCategoryEditor(
      context,
      type: _type,
    );
    if (action == null || !mounted) return;
    await _applyAction(action, parentId: null);
  }

  Future<void> _edit(Category category) async {
    final CategoryAction? action = await showCategoryEditor(
      context,
      type: _type,
      category: category,
    );
    if (action == null || !mounted) return;
    await _applyAction(action, parentId: category.parentId);
  }

  Future<void> _applyAction(CategoryAction action, {required int? parentId}) async {
    final int ledgerId = CatalogScope.of(context).ledgerId;
    setState(() => _busy = true);
    int detached = 0;
    try {
      switch (action) {
        case SaveCategory(:final Category draft):
          if (draft.id == null) {
            await Repo.category.insert(
              draft.copyWith(ledgerId: ledgerId, parentId: parentId),
            );
          } else {
            await Repo.category.update(draft);
          }
        case ArchiveCategory(:final int categoryId, :final bool archived):
          await Repo.category.setArchived(categoryId, archived);
        case DeleteCategory(:final int categoryId):
          final DeleteCategoryResult result = await Repo.category.delete(
            categoryId,
          );
          detached = result.detachedTxns;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
    if (!mounted) return;
    if (action is DeleteCategory) toastCategoryDeleted(context, detached);
    if (action is ArchiveCategory && action.archived) {
      showToast(context, '已停用，历史账目仍显示原名');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final CatalogStore catalog = CatalogScope.watch(context);
    final CategoryTree tree = catalog.tree;
    final List<Category> tops = _tops(tree);
    final List<Category> archived = _archivedTops(tree);

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        elevation: 0,
        title: Text('分类管理', style: Ts.section.copyWith(color: pal.ink)),
        iconTheme: IconThemeData(color: pal.ink),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey<String>('cat-new'),
        onPressed: _busy ? null : _addTop,
        backgroundColor: pal.accent,
        foregroundColor: pal.onAccent,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('新建分类'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: S.sm, bottom: S.sm),
            child: ChipTabs<TxnType>(
              items: const <ChipTabItem<TxnType>>[
                ChipTabItem<TxnType>(TxnType.expense, '支出'),
                ChipTabItem<TxnType>(TxnType.income, '收入'),
              ],
              selected: _type,
              onChanged: (TxnType t) => setState(() => _type = t),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: S.xxxl),
              itemCount: tops.length,
              onReorderItem: (int a, int b) => _reorder(tops, a, b),
              footer: archived.isEmpty
                  ? null
                  : Column(
                      children: <Widget>[
                        const SectionHeader(title: '已停用'),
                        for (final Category c in archived)
                          _CatRow(
                            key: ValueKey<String>('cat-archived-${c.id}'),
                            category: c,
                            childCount: tree.childrenOf(c.id).length,
                            dimmed: true,
                            onTap: () => _edit(c),
                            onSubTap: null,
                            dragIndex: null,
                          ),
                      ],
                    ),
              itemBuilder: (BuildContext ctx, int i) {
                final Category c = tops[i];
                final int children = tree.childrenOf(c.id).length;
                return _CatRow(
                  key: ValueKey<String>('cat-row-${c.id}'),
                  category: c,
                  childCount: children,
                  dimmed: false,
                  dragIndex: i,
                  onTap: () => _openSubs(c),
                  onSubTap: () => _openSubs(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSubs(Category top) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => SubCatsPage(topId: top.id!),
      ),
    );
    await _refresh();
  }
}

/// 一行分类：图标 + 名字 + 副行（N 个子分类）+ 右侧手柄/箭头。
class _CatRow extends StatelessWidget {
  const _CatRow({
    super.key,
    required this.category,
    required this.childCount,
    required this.dimmed,
    required this.onTap,
    required this.onSubTap,
    required this.dragIndex,
  });

  final Category category;
  final int childCount;
  final bool dimmed;
  final VoidCallback onTap;

  /// 点「子分类」区域进子页；`null` = 不提供（已停用段）。
  final VoidCallback? onSubTap;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Material(
        color: pal.bg,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.sm),
            child: Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: pal.surfaceAlt,
                    borderRadius: R.rSm,
                  ),
                  child: Icon(
                    IconMap.of(category.icon),
                    size: 16,
                    color: pal.ink2,
                  ),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ts.body.copyWith(color: pal.ink),
                      ),
                      Text(
                        childCount == 0 ? '还没有子分类' : '$childCount 个子分类',
                        key: ValueKey<String>('cat-subcount-${category.id}'),
                        style: Ts.caption.copyWith(color: pal.ink4),
                      ),
                    ],
                  ),
                ),
                if (onSubTap != null) ...<Widget>[
                  IconButton(
                    key: ValueKey<String>('cat-edit-${category.id}'),
                    onPressed: onTap,
                    icon: Icon(Icons.edit_outlined, size: 16, color: pal.ink4),
                    tooltip: '编辑',
                  ),
                  TextButton(
                    key: ValueKey<String>('cat-subs-${category.id}'),
                    onPressed: onSubTap,
                    child: Text(
                      '子分类',
                      style: Ts.caption.copyWith(color: pal.ink3),
                    ),
                  ),
                ],
                if (dragIndex != null)
                  ReorderableDragStartListener(
                    index: dragIndex!,
                    child: Padding(
                      padding: const EdgeInsets.only(left: S.xs),
                      child: Icon(
                        Icons.drag_handle,
                        size: 18,
                        color: pal.ink4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 供外部打开分类管理。
Future<void> openCatsPage(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (BuildContext _) => const CatsPage()));

/// 停用分类的确认文案（停用不级联子分类，这一点要说清）。
const String archiveCategoryBody =
    '停用后，这个分类不会出现在记账和筛选里，但已经记过的账仍显示原来的名字。'
    '子分类不会被一起停用。想恢复时回到这一页点它就行。';

/// 停用 / 恢复（页面外部也能调，测试直接用它）。
Future<void> setCategoryArchived(int id, bool archived) =>
    Repo.category.setArchived(id, archived);

/// 删除确认（含子分类数与受影响笔数）。
Future<bool> confirmDeleteCategory(
  BuildContext context, {
  required Category category,
  required int childCount,
  required int txnCount,
}) async {
  return showConfirmDialog(
    context,
    title: '删除「${category.name}」？',
    body: deleteCategoryBody(
      name: category.name,
      childCount: childCount,
      txnCount: txnCount,
    ),
    confirmText: '删除',
    destructive: true,
  );
}

/// 提示文案（页面外部断言用）。
void toastCategoryDeleted(BuildContext context, int detached) =>
    showToast(context, detached > 0 ? '$detached 笔账目已转为未分类' : '已删除');
