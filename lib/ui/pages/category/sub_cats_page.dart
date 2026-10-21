import 'package:flutter/material.dart';

import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/category_repo.dart';
import '../../../data/repo/repo.dart';
import '../../../stores/catalog_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import 'category_editor.dart';
import 'cats_page.dart';

/// 子分类管理页（结构与一级页相同，但**没有第三层入口**）。
///
/// 两级是硬上限：数据层 `CategoryRepo.insert` 的 `_validateParent` 要求父级
/// `parent_id IS NULL`，这里也不给「新建子分类的子分类」的按钮。
class SubCatsPage extends StatefulWidget {
  const SubCatsPage({super.key, required this.topId});

  final int topId;

  @override
  State<SubCatsPage> createState() => _SubCatsPageState();
}

class _SubCatsPageState extends State<SubCatsPage> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (!mounted) return;
    await CatalogScope.of(context).reloadCategories();
  }

  Future<void> _add() async {
    final CategoryAction? action = await showCategoryEditor(
      context,
      type: _topType(),
      parentId: widget.topId,
    );
    if (action == null || !mounted) return;
    await _apply(action, isNew: true);
  }

  Future<void> _edit(Category category) async {
    final CategoryAction? action = await showCategoryEditor(
      context,
      type: category.type,
      category: category,
    );
    if (action == null || !mounted) return;
    await _apply(action, isNew: false);
  }

  TxnType _topType() =>
      CatalogScope.of(context).tree.byId(widget.topId)?.type ??
      TxnType.expense;

  Future<void> _apply(CategoryAction action, {required bool isNew}) async {
    final int ledgerId = CatalogScope.of(context).ledgerId;
    setState(() => _busy = true);
    int detached = 0;
    try {
      switch (action) {
        case SaveCategory(:final Category draft):
          if (isNew) {
            await Repo.category.insert(
              draft.copyWith(ledgerId: ledgerId, parentId: widget.topId),
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
  }

  Future<void> _reorder(List<Category> list, int oldIndex, int newIndex) async {
    final List<Category> next = <Category>[...list];
    final Category moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    // 只写这一层（子分类各自的 sort_order 与本层内顺序一致即可）
    await Repo.category.reorder(<int>[for (final Category c in next) c.id!]);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final CatalogStore catalog = CatalogScope.watch(context);
    final CategoryTree tree = catalog.tree;
    final Category? top = tree.byId(widget.topId);
    final List<Category> children = tree.childrenOf(widget.topId);
    final List<Category> active = <Category>[
      for (final Category c in children)
        if (!c.archived) c,
    ];
    final List<Category> archived = <Category>[
      for (final Category c in children)
        if (c.archived) c,
    ];

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        elevation: 0,
        title: Text(
          top == null ? '子分类' : '${top.name} · 子分类',
          key: const ValueKey<String>('sub-title'),
          style: Ts.section.copyWith(color: pal.ink),
        ),
        iconTheme: IconThemeData(color: pal.ink),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey<String>('sub-new'),
        onPressed: _busy ? null : _add,
        backgroundColor: pal.accent,
        foregroundColor: pal.onAccent,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('新建子分类'),
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: S.xxxl),
        itemCount: active.length,
        onReorderItem: (int a, int b) => _reorder(active, a, b),
        footer: archived.isEmpty
            ? null
            : Column(
                children: <Widget>[
                  for (final Category c in archived)
                    Opacity(
                      key: ValueKey<String>('sub-archived-${c.id}'),
                      opacity: 0.5,
                      child: ListTile(
                        title: Text(
                          c.name,
                          style: Ts.body.copyWith(color: pal.ink2),
                        ),
                        subtitle: Text(
                          '已停用',
                          style: Ts.caption.copyWith(color: pal.ink4),
                        ),
                        onTap: () => _edit(c),
                      ),
                    ),
                ],
              ),
        itemBuilder: (BuildContext ctx, int i) {
          final Category c = active[i];
          return Padding(
            key: ValueKey<String>('sub-row-${c.id}'),
            padding: const EdgeInsets.symmetric(horizontal: S.page),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ts.body.copyWith(color: pal.ink),
              ),
              subtitle: Text(
                c.icon,
                style: Ts.micro.copyWith(color: pal.ink4),
              ),
              onTap: () => _edit(c),
              trailing: ReorderableDragStartListener(
                index: i,
                child: Icon(Icons.drag_handle, size: 18, color: pal.ink4),
              ),
            ),
          );
        },
      ),
    );
  }
}
