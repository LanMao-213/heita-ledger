import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';

/// 分类管理。按用户要求，这个页面从底部导航移到了「我的 → 分类管理」。
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
                padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.sm),
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
                          return SettingRow(
                            icon: c.icon,
                            title: c.name,
                            trailing: IconButton(
                              onPressed: () => _menu(context, c),
                              icon: const Icon(Icons.more_horiz_rounded,
                                  size: 20, color: C.ink3),
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
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: c.name),
            SettingRow(
              icon: 'tpl',
              title: '编辑',
              onTap: () {
                Navigator.pop(ctx);
                _edit(context, c);
              },
            ),
            SettingRow(
              icon: 'more',
              title: '删除',
              subtitle: '该分类下的历史记录会变成「未分类」，不会被删掉',
              danger: true,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirmDelete(context, c);
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

  Future<bool?> _confirmDelete(BuildContext context, Category c) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${c.name}」？', style: T.section),
        content: const Text(
          '这个分类下的历史记录不会消失，会显示为「未分类」。',
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

  Future<void> _edit(BuildContext context, Category? cat) async {
    final s = Store.i;
    final nameCtl = TextEditingController(text: cat?.name ?? '');
    var icon = cat?.icon ?? 'more';

    // 可选的图标全集：把与当前类型相关的排前面
    final choices = _iconChoices(_type);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(cat == null ? '新增分类' : '编辑分类', style: T.section),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            child: LineIcon(k,
                                size: 19, color: on ? C.bg : C.ink2),
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
      await Repo.insertCategory(Category(
        id: 0,
        ledgerId: s.ledgerId,
        type: _type,
        name: name,
        icon: icon,
        sortOrder: 999,
      ));
    } else {
      await Repo.updateCategory(cat.copyWith(name: name, icon: icon));
    }
    await s.afterCategoryChange();
    if (context.mounted) showToast(context, '已保存');
  }

  /// 常用图标优先，其余按图标库顺序补齐
  static List<String> _iconChoices(TxnType type) {
    final primary = type.isExpense
        ? ['food', 'transport', 'shopping', 'home', 'fun', 'medical',
           'study', 'comm', 'gift', 'more']
        : ['salary', 'bonus', 'parttime', 'invest', 'redpacket', 'more'];
    final all = <String>{...primary, ...kIcons.keys};
    return all.toList();
  }
}
