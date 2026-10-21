import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../core/scope.dart';
import '../../../data/models/models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/chip_tabs.dart';
import '../../widgets/icon_map.dart';
import '../../widgets/pickers/account_sheet.dart';
import '../../widgets/pickers/picker_wheels.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/toast.dart';

/// 模板名的长度上限（`maxLength 8`：再长就挤掉金额，横排放不下）。
const int kTemplateNameMax = 8;

/// 图标墙里**不出现**的图标：底栏与浮钮用的那四个。
///
/// 分类/模板用「列表」「饼图」「我的」「加号」当图标会让用户看着像导航按钮。
const Set<String> kNavIcons = <String>{'list', 'pie', 'person', 'plus'};

/// 模板可选的图标：全量减去导航图标。
List<String> templateIcons() => <String>[
  for (final String n in IconMap.known)
    if (!kNavIcons.contains(n)) n,
];

/// 新建 / 编辑记账模板。返回 `null` = 取消。
Future<TxnTemplate?> showTemplateEditor(
  BuildContext context, {
  TxnTemplate? template,
}) {
  return showModalBottomSheet<TxnTemplate>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _TemplateEditor(template: template),
  );
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({this.template});

  final TxnTemplate? template;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.template?.name ?? '',
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.template == null || widget.template!.amountCents == 0
        ? ''
        : Fmt.money(widget.template!.amountCents, trimZero: true),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.template?.note ?? '',
  );
  late TxnType _type = widget.template?.type ?? TxnType.expense;
  late String _icon = widget.template?.icon ?? 'tpl';
  late int? _categoryId = widget.template?.categoryId;
  late int? _accountId = widget.template?.accountId;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final picked = await showCategoryPicker(
      context,
      tree: CatalogScope.of(context).tree,
      type: _type,
      topId: _categoryId,
      title: '这笔算哪个分类',
    );
    if (picked == null || !mounted) return;
    setState(() => _categoryId = picked.subId ?? picked.topId);
  }

  Future<void> _pickAccount() async {
    final int? picked = await showAccountSheet(
      context,
      accounts: CatalogScope.of(context).accounts,
      selectedId: _accountId,
      title: '默认账户',
    );
    if (picked == null || !mounted) return;
    setState(() => _accountId = picked);
  }

  void _save() {
    if (_categoryId == null) {
      showToast(context, '先选一个分类', error: true);
      return;
    }
    if (_accountId == null) {
      showToast(context, '先选一个账户', error: true);
      return;
    }
    final String typed = _name.text.trim();
    final String name = typed.isEmpty
        ? CatalogScope.of(context)
              .tree
              .byId(_categoryId)
              ?.name ??
              '模板'
        : (typed.length > kTemplateNameMax
              ? typed.substring(0, kTemplateNameMax)
              : typed);
    // 金额留空 = 0：有的模板只固定分类和账户，金额每次现输
    final int amount = _amount.text.trim().isEmpty
        ? 0
        : Fmt.parseCents(_amount.text.trim());
    final TxnTemplate base =
        widget.template ??
        TxnTemplate(
          ledgerId: 0,
          name: name,
          type: _type,
          amountCents: amount,
        );
    Navigator.of(context).pop(
      base.copyWith(
        name: name,
        icon: _icon,
        type: _type,
        amountCents: amount,
        categoryId: _categoryId,
        accountId: _accountId,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final List<String> icons = templateIcons();
    return SheetFrame(
      title: widget.template == null ? '新建模板' : '编辑模板',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('名称（最多 $kTemplateNameMax 字，留空用分类名）',
                style: Ts.micro.copyWith(color: pal.ink3)),
            const SizedBox(height: S.xs),
            TextField(
              key: const ValueKey<String>('tpl-name'),
              controller: _name,
              maxLength: kTemplateNameMax,
              style: Ts.body.copyWith(color: pal.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.surfaceAlt,
                hintText: '例如：早饭',
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
            Text('类型', style: Ts.micro.copyWith(color: pal.ink3)),
            const SizedBox(height: S.xs),
            ChipTabs<TxnType>(
              padding: EdgeInsets.zero,
              items: const <ChipTabItem<TxnType>>[
                ChipTabItem<TxnType>(TxnType.expense, '支出'),
                ChipTabItem<TxnType>(TxnType.income, '收入'),
              ],
              selected: _type,
              onChanged: (TxnType t) => setState(() {
                _type = t;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: S.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('tpl-category'),
                    onPressed: _pickCategory,
                    child: Text(
                      CatalogScope.watch(context).displayName(_categoryId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('tpl-account'),
                    onPressed: _pickAccount,
                    child: Text(
                      CatalogScope.watch(context).accountName(_accountId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.md),
            Text('金额（留空 = 每次现输）',
                style: Ts.micro.copyWith(color: pal.ink3)),
            const SizedBox(height: S.xs),
            TextField(
              key: const ValueKey<String>('tpl-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: Ts.body.copyWith(color: pal.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.surfaceAlt,
                hintText: '可为空',
                hintStyle: Ts.body2.copyWith(color: pal.ink4),
                prefixText: '¥ ',
                prefixStyle: Ts.body.copyWith(color: pal.ink3),
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
            Text('备注', style: Ts.micro.copyWith(color: pal.ink3)),
            const SizedBox(height: S.xs),
            TextField(
              key: const ValueKey<String>('tpl-note'),
              controller: _note,
              style: Ts.body.copyWith(color: pal.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.surfaceAlt,
                hintText: '可选',
                hintStyle: Ts.body2.copyWith(color: pal.ink4),
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
              height: 128,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: S.sm,
                  runSpacing: S.sm,
                  children: <Widget>[
                    for (final String n in icons)
                      GestureDetector(
                        key: ValueKey<String>('tpl-icon-$n'),
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
                key: const ValueKey<String>('tpl-save'),
                onPressed: _save,
                child: const Text('保存'),
              ),
            ),
            const SizedBox(height: S.sm),
          ],
        ),
      ),
    );
  }
}
