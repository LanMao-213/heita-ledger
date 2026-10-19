import 'package:flutter/material.dart';

import '../data/category_seed.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';

/// 分类管理（两级）。
///
/// 一级列表显示「几个子分类」，点进去管理该组的子分类。用户新增/删除
/// 都走这里 —— 界面上不做「只能选默认分类」的限制，但**数据层拦住第三级**
/// （见 `Repo.insertCategory`），因为三级会把统计、预算、筛选全部变成递归。
class CatsPage extends StatefulWidget {
  const CatsPage({super.key});

  @override
  State<CatsPage> createState() => _CatsPageState();
}

class _CatsPageState extends State<CatsPage> {
  TxnType _type = TxnType.expense;

  @override
  Widget build(BuildContext context) {
    final s = Store.i;

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('分类管理'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
      ),
      body: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          final cats = _type.isExpense ? s.expenseCats : s.incomeCats;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.xl,
                  vertical: S.sm,
                ),
                child: SegTabs(
                  value: _type,
                  onChanged: (t) => setState(() => _type = t),
                ),
              ),
              Expanded(
                child: cats.isEmpty
                    ? const EmptyHint(text: '这个类型下还没有分类')
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: cats.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          color: C.line,
                          indent: 64,
                          endIndent: S.lg,
                        ),
                        itemBuilder: (context, i) {
                          final c = cats[i];
                          final n = s.childrenOf(c.id).length;
                          return SettingRow(
                            icon: c.icon,
                            title: c.name,
                            subtitle: n == 0 ? '还没有子分类' : '$n 个子分类',
                            // 整行可点：主操作是「进去管子分类」，
                            // 改名/删除这种低频动作收进右侧菜单
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _SubCatsPage(
                                  parent: c,
                                  onAdd: (ctx) => _edit(ctx, null, parent: c),
                                  onEdit: (ctx, cat) => _edit(ctx, cat),
                                ),
                              ),
                            ),
                            trailing: IconButton(
                              onPressed: () => _menu(context, c),
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                size: 20,
                                color: C.ink3,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        backgroundColor: C.ink,
        foregroundColor: C.bg,
        elevation: 0,
        icon: const LineIcon('plus', size: 20, color: C.bg, strokeWidth: 1.8),
        label: const Text('新增分类', style: TextStyle(fontSize: 14)),
      ),
    );
  }

  Future<void> _menu(BuildContext context, Category c) async {
    final n = Store.i.childrenOf(c.id).length;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: c.name),
            SettingRow(
              icon: 'tpl',
              title: '编辑名称与图标',
              onTap: () {
                Navigator.pop(ctx);
                _edit(context, c);
              },
            ),
            SettingRow(
              icon: 'plus',
              title: '新增子分类',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _SubCatsPage(
                      parent: c,
                      onAdd: (ctx) => _edit(ctx, null, parent: c),
                      onEdit: (ctx, cat) => _edit(ctx, cat),
                    ),
                  ),
                );
              },
            ),
            SettingRow(
              icon: 'more',
              title: '删除',
              // 一级分类带着子分类一起删，文案必须说清楚，否则用户以为只删了一层
              subtitle: n == 0
                  ? '该分类下的历史记录会变成「未分类」，不会被删掉'
                  : '连同 $n 个子分类一起删除；历史记录会变成「未分类」，不会被删掉',
              danger: true,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirmDelete(context, c, subCount: n);
                if (ok != true) return;
                await Repo.deleteCategory(c.id);
                await Store.i.afterCategoryChange();
                if (context.mounted) showToast(context, '已删除');
              },
            ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(
    BuildContext context,
    Category c, {
    int subCount = 0,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${c.name}」？', style: T.section),
        content: Text(
          subCount > 0
              ? '它的 $subCount 个子分类会一起删掉。历史记录不会消失，会显示为「未分类」。'
              : '这个分类下的历史记录不会消失，会显示为「未分类」。',
          style: T.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: C.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: C.over)),
          ),
        ],
      ),
    );
  }

  /// 新增/编辑。传 [parent] 表示在它的下面加子分类。
  Future<void> _edit(
    BuildContext context,
    Category? cat, {
    Category? parent,
  }) async {
    final s = Store.i;
    final type = cat?.type ?? parent?.type ?? _type;
    final nameCtl = TextEditingController(text: cat?.name ?? '');
    var icon = cat?.icon ?? (parent?.icon ?? 'more');

    final choices = iconChoices(type);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            cat == null
                ? (parent == null ? '新增分类' : '新增子分类')
                : '编辑分类',
            style: T.section,
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (parent != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.sm),
                    child: Text('属于「${parent.name}」', style: T.caption),
                  ),
                TextField(
                  controller: nameCtl,
                  autofocus: true,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    hintText: '分类名称',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: S.md),
                SizedBox(
                  height: 168,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: S.sm,
                          crossAxisSpacing: S.sm,
                        ),
                    itemCount: choices.length,
                    itemBuilder: (c2, i) {
                      final k = choices[i];
                      final on = k == icon;
                      return GestureDetector(
                        onTap: () => setLocal(() => icon = k),
                        child: Container(
                          decoration: BoxDecoration(
                            color: on ? C.ink : C.bg2,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: LineIcon(
                              k,
                              size: 19,
                              color: on ? C.bg : C.ink2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: C.ink2)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存', style: TextStyle(color: C.ink)),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final name = nameCtl.text.trim();
    if (name.isEmpty) {
      if (context.mounted) showToast(context, '名称不能为空');
      return;
    }

    if (cat == null) {
      final siblings = parent == null
          ? (type.isExpense ? s.expenseCats : s.incomeCats)
          : s.childrenOf(parent.id);
      await Repo.insertCategory(
        Category(
          id: 0,
          ledgerId: s.ledgerId,
          type: type,
          name: name,
          icon: icon,
          parentId: parent?.id,
          // 排在最后：新加的分区永远在末尾，不会打乱用户已经熟悉的顺序
          sortOrder: siblings.length,
        ),
      );
    } else {
      await Repo.updateCategory(cat.copyWith(name: name, icon: icon));
    }
    await s.afterCategoryChange();
    if (context.mounted) showToast(context, '已保存');
  }

  /// 图标候选：先列分类种子里用过的（最常用），再补图标库全集
  static List<String> iconChoices(TxnType type) {
    final seed = type.isExpense ? kExpenseSeed : kIncomeSeed;
    final used = <String>[
      for (final c in seed) ...[c.icon, for (final sub in c.subs) sub.icon],
    ];
    return {...used, ...kIcons.keys}.toList();
  }
}

/// 某个一级分类下的子分类管理页
class _SubCatsPage extends StatefulWidget {
  const _SubCatsPage({
    required this.parent,
    required this.onAdd,
    required this.onEdit,
  });

  final Category parent;

  /// 新增子分类 / 编辑某个子分类 —— 复用一级页的编辑弹窗，
  /// 避免两处各写一套「名称 + 图标」表单而慢慢长歪
  final Future<void> Function(BuildContext context) onAdd;
  final Future<void> Function(BuildContext context, Category cat) onEdit;

  @override
  State<_SubCatsPage> createState() => _SubCatsPageState();
}

class _SubCatsPageState extends State<_SubCatsPage> {
  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: Text('${widget.parent.name} · 子分类'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
      ),
      body: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          final subs = s.childrenOf(widget.parent.id);
          if (subs.isEmpty) {
            return const EmptyHint(text: '还没有子分类，点右下角添加');
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: subs.length,
            separatorBuilder: (_, _) => const Divider(
              height: 1,
              color: C.line,
              indent: 64,
              endIndent: S.lg,
            ),
            itemBuilder: (context, i) {
              final c = subs[i];
              return SettingRow(
                icon: c.icon,
                title: c.name,
                subtitle: c.name == widget.parent.name ? '与一级同名' : null,
                trailing: IconButton(
                  onPressed: () => _menu(context, c),
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    size: 20,
                    color: C.ink3,
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => widget.onAdd(context),
        backgroundColor: C.ink,
        foregroundColor: C.bg,
        elevation: 0,
        icon: const LineIcon('plus', size: 20, color: C.bg, strokeWidth: 1.8),
        label: const Text('新增子分类', style: TextStyle(fontSize: 14)),
      ),
    );
  }

  Future<void> _menu(BuildContext context, Category c) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: c.name),
            SettingRow(
              icon: 'tpl',
              title: '编辑名称与图标',
              onTap: () {
                Navigator.pop(ctx);
                widget.onEdit(context, c);
              },
            ),
            SettingRow(
              icon: 'more',
              title: '删除',
              subtitle: '该子分类下的记录会变成「未分类」，不会被删掉',
              danger: true,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text('删除「${c.name}」？', style: T.section),
                    content: const Text(
                      '这个子分类下的记录不会消失，会显示为「未分类」。',
                      style: T.body2,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: C.ink2),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text(
                          '删除',
                          style: TextStyle(color: C.over),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                await Repo.deleteCategory(c.id);
                await Store.i.afterCategoryChange();
                if (context.mounted) showToast(context, '已删除');
              },
            ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }
}
