import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../data/repo/repo.dart';
import '../../../stores/catalog_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/icon_map.dart';
import '../../widgets/list_tile_row.dart';
import '../../widgets/toast.dart';
import 'template_editor.dart';

/// 记账模板页：拖拽排序 + 编辑 + 删除。
///
/// 拖拽用 `ReorderableListView`（自带长按拖拽与动画），落到库里是**一次**
/// `reorder`（单事务把 `sort_order` 重写成 0..n-1）。
class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  Future<void> _refresh() async {
    if (!mounted) return;
    await CatalogScope.of(context).reloadTemplates();
  }

  Future<void> _edit([TxnTemplate? template]) async {
    final TxnTemplate? saved = await showTemplateEditor(
      context,
      template: template,
    );
    if (saved == null || !mounted) return;
    if (saved.id == null) {
      await Repo.template.insert(
        saved.copyWith(ledgerId: CatalogScope.of(context).ledgerId),
      );
    } else {
      await Repo.template.update(saved);
    }
    await _refresh();
  }

  Future<void> _delete(TxnTemplate template) async {
    final bool ok = await showConfirmDialog(
      context,
      title: '删除这个模板？',
      body: '模板只是快捷方式：已经用它记过的账一条都不会动，'
          '那些账目的分类、金额、备注都还在。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await Repo.template.delete(template.id!);
    await _refresh();
    if (mounted) showToast(context, '已删除模板');
  }

  Future<void> _reorder(List<TxnTemplate> list, int oldIndex, int newIndex) async {
    final List<TxnTemplate> next = <TxnTemplate>[...list];
    final TxnTemplate moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    // 单事务把 sort_order 重写成 0..n-1（不是「交换两个数」——
    // 交换会让「先拖三次再拖回来」留下 0,2,1,3 这种洞）
    await Repo.template.reorder(
      <int>[for (final TxnTemplate t in next) t.id!],
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final CatalogStore catalog = CatalogScope.watch(context);
    final List<TxnTemplate> list = catalog.templates;

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        elevation: 0,
        title: Text('记账模板', style: Ts.section.copyWith(color: pal.ink)),
        iconTheme: IconThemeData(color: pal.ink),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey<String>('tpl-new'),
        onPressed: () => _edit(),
        backgroundColor: pal.accent,
        foregroundColor: pal.onAccent,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('新建模板'),
      ),
      body: list.isEmpty
          ? const EmptyState(
              key: ValueKey<String>('tpl-empty'),
              icon: Icons.bolt_outlined,
              title: '还没有模板',
              hint: '早饭、地铁、咖啡这类天天记的，做成模板点一下就填好了。',
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(top: S.sm, bottom: S.xxxl),
              itemCount: list.length,
              onReorderItem: (int oldIndex, int newIndex) =>
                  _reorder(list, oldIndex, newIndex),
              itemBuilder: (BuildContext ctx, int i) {
                final TxnTemplate t = list[i];
                return Padding(
                  key: ValueKey<String>('tpl-row-${t.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: S.page),
                  child: ListTileRow(
                    leadingIcon: IconMap.of(t.icon),
                    title: Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.body.copyWith(color: pal.ink),
                    ),
                    subtitle: Text(
                      templateSubtitle(t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.caption.copyWith(color: pal.ink3),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '用过 ${t.useCount} 次',
                          style: Ts.micro.copyWith(color: pal.ink4),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(left: S.sm),
                            child: Icon(
                              Icons.drag_handle,
                              size: 18,
                              color: pal.ink4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    showDivider: true,
                    onTap: () => _edit(t),
                    onLongPress: () => _delete(t),
                  ),
                );
              },
            ),
    );
  }
}

/// 模板行副行：`支出 · 餐饮 · ¥38.50` / `收入 · 工资`。
String templateSubtitle(TxnTemplate t, {String Function(int?)? categoryOf}) {
  final String type = t.type.isIncome ? '收入' : '支出';
  final String cat = categoryOf == null ? '' : categoryOf(t.categoryId);
  final String amount = t.amountCents > 0
      ? Fmt.money(t.amountCents)
      : '金额每次现填';
  final List<String> parts = <String>[
    type,
    if (cat.isNotEmpty && cat != '未分类') cat,
    amount,
  ];
  return parts.join(' · ');
}

/// 供外部打开模板页。
Future<void> openTemplatesPage(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (BuildContext _) => const TemplatesPage()));

/// 模板条上不显示的图标（供给测试断言「导航图标真的被剔掉了」）。
bool isNavIcon(String name) => kNavIcons.contains(name);

/// 金额位（模板页要展示金额，用统一入口而不是自己拼字符串）。
AmountText templateAmount(TxnTemplate t) =>
    AmountText(cents: t.amountCents, tier: AmountTier.small);
