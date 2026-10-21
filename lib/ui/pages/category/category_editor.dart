import 'package:flutter/material.dart';

import '../../../core/scope.dart';
import '../../../data/db/seeds.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/icon_map.dart';
import '../../widgets/toast.dart';

/// 图标墙里**不出现**的图标（底栏 / 浮钮那四个）。
const Set<String> kNavIconsForCategory = <String>{'list', 'pie', 'person', 'plus'};

/// 图标墙的顺序：**种子用过的图标优先**，其余按字母序跟在后面。
///
/// 为什么种子优先：用户加分类时最常挑的就是「吃 / 车 / 家」这几个，
/// 把 60 个图标按字母排会让常用图标散落在各处。
List<String> categoryIcons(List<String> seedIcons) {
  final Set<String> seen = <String>{};
  final List<String> out = <String>[];
  for (final String n in seedIcons) {
    if (kNavIconsForCategory.contains(n)) continue;
    if (!seen.add(n)) continue;
    final String name = n;
    if (!IconMap.known.contains(name)) continue;
    out.add(name);
  }
  final List<String> rest = <String>[
    for (final String n in IconMap.known)
      if (!kNavIconsForCategory.contains(n) && !seen.contains(n)) n,
  ]..sort();
  return <String>[...out, ...rest];
}

/// 种子里用到的全部图标名（一级 + 子级，去重保序）。
List<String> seedIconNames() {
  final List<String> out = <String>[];
  for (final SeedCat c in kExpenseSeed) {
    out.add(c.icon);
    for (final SeedSub s in c.subs) {
      out.add(s.icon);
    }
  }
  for (final SeedCat c in kIncomeSeed) {
    out.add(c.icon);
    for (final SeedSub s in c.subs) {
      out.add(s.icon);
    }
  }
  return out;
}

/// 分类编辑器要交给调用方的动作。
sealed class CategoryAction {
  const CategoryAction();
}

/// 保存（新增或改名/换图标）。
class SaveCategory extends CategoryAction {
  const SaveCategory(this.draft);

  final Category draft;
}

/// 停用 / 恢复。
class ArchiveCategory extends CategoryAction {
  const ArchiveCategory({required this.categoryId, required this.archived});

  final int categoryId;
  final bool archived;
}

/// 删除（连带子分类与预算行）。
class DeleteCategory extends CategoryAction {
  const DeleteCategory({required this.categoryId});

  final int categoryId;
}

/// 新增 / 编辑分类。返回 `null` = 取消。
Future<CategoryAction?> showCategoryEditor(
  BuildContext context, {
  required TxnType type,
  Category? category,
  int? parentId,
}) {
  return showModalBottomSheet<CategoryAction>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) =>
        _CategoryEditor(type: type, category: category, parentId: parentId),
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.type, this.category, this.parentId});

  final TxnType type;
  final Category? category;
  final int? parentId;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );
  late String _icon = widget.category?.icon ?? 'more';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, '名字不能为空', error: true);
      return;
    }
    final Category base =
        widget.category ??
        Category(
          type: widget.type,
          name: name,
          parentId: widget.parentId,
        );
    Navigator.of(context).pop(
      SaveCategory(base.copyWith(name: name, icon: _icon)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final List<String> icons = categoryIcons(seedIconNames());
    final bool isEdit = widget.category != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: pal.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(S.page),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  isEdit ? '编辑分类' : '新建分类',
                  style: Ts.section.copyWith(color: pal.ink),
                ),
                const SizedBox(height: S.md),
                TextField(
                  key: const ValueKey<String>('cat-name'),
                  controller: _name,
                  autofocus: !isEdit,
                  maxLength: 8,
                  style: Ts.body.copyWith(color: pal.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: pal.surfaceAlt,
                    hintText: '分类名（最多 8 字）',
                    hintStyle: Ts.body2.copyWith(color: pal.ink4),
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: R.rMd,
                      borderSide: BorderSide(color: pal.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: R.rMd,
                      borderSide: BorderSide(color: pal.line),
                    ),
                  ),
                ),
                const SizedBox(height: S.md),
                Text('图标', style: Ts.micro.copyWith(color: pal.ink3)),
                const SizedBox(height: S.xs),
                SizedBox(
                  height: 132,
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: S.sm,
                      runSpacing: S.sm,
                      children: <Widget>[
                        for (final String n in icons)
                          GestureDetector(
                            key: ValueKey<String>('cat-icon-$n'),
                            onTap: () => setState(() => _icon = n),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: n == _icon ? pal.accent : pal.surfaceAlt,
                                borderRadius: R.rSm,
                              ),
                              child: Icon(
                                IconMap.of(n),
                                size: 16,
                                color: n == _icon ? pal.onAccent : pal.ink2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: S.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey<String>('cat-save'),
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
                if (isEdit) ...<Widget>[
                  const SizedBox(height: S.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      key: const ValueKey<String>('cat-archive'),
                      onPressed: () => Navigator.of(context).pop(
                        ArchiveCategory(
                          categoryId: widget.category!.id!,
                          archived: !widget.category!.archived,
                        ),
                      ),
                      child: Text(
                        widget.category!.archived ? '恢复这个分类' : '停用这个分类',
                      ),
                    ),
                  ),
                  const SizedBox(height: S.sm),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      key: const ValueKey<String>('cat-delete'),
                      onPressed: () => Navigator.of(context).pop(
                        DeleteCategory(categoryId: widget.category!.id!),
                      ),
                      child: Text(
                        '删除这个分类',
                        style: Ts.caption.copyWith(color: pal.over),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: S.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 删除分类的确认文案：**有没有子分类要说清楚**。
///
/// 两句话差别很大：「连同 3 个子分类一起删」和「删掉这个分类」。
/// 原版只有一句「确定删除？」，用户点下去才发现连带删了一串。
String deleteCategoryBody({
  required String name,
  required int childCount,
  required int txnCount,
}) {
  final String head = childCount > 0
      ? '「$name」连同 $childCount 个子分类一起删除。'
      : '「$name」没有子分类，直接删除。';
  return '$head\n'
      '已经记过的 $txnCount 笔账目会变成「未分类」，一条都不会少；'
      '这个分类下的预算限额会一起删掉。';
}

/// 分类页里「当前账本 id」的唯一来源。
int currentLedgerId(BuildContext context) => CatalogScope.of(context).ledgerId;
