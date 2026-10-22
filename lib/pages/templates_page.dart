import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/picker_wheels.dart';

/// 记账模板管理。
///
/// 模板解决的是「同一笔钱反复记」：早餐 12 块、房租 3000、通勤地铁 6 块。
/// 存成模板之后，「记一笔」面板顶部会出现最常用的三个，点一下就把
/// 分类 / 账户 / 金额 / 备注填好，只剩「保存」这一下。
class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  Future<void> _openEditor([TxnTemplate? t]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TemplateEditorPage(initial: t)),
    );
    if (saved == true && mounted) {
      showToast(context, t == null ? '已新增模板' : '已保存');
    }
  }

  Future<void> _menu(TxnTemplate t) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: t.name),
            SettingRow(
              icon: 'tpl',
              title: '编辑',
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(t);
              },
            ),
            SettingRow(
              icon: 'more',
              title: '删除',
              subtitle: '已经记下的账目不受影响',
              danger: true,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirmDelete(t);
                if (ok != true) return;
                await Repo.deleteTemplate(t.id);
                await Store.i.afterTemplateChange();
                if (mounted) showToast(context, '已删除');
              },
            ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(TxnTemplate t) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${t.name}」？', style: T.section),
        content: const Text('用这个模板记过的账目会保留，只是以后不再出现在列表里。', style: T.body2),
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

  /// 拖动排序 —— 只写 sort_order，不动使用次数
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final list = [...Store.i.templates];
    if (oldIndex >= list.length) return; // 末尾那行说明不可拖
    final item = list.removeAt(oldIndex);
    // 列表末尾还挂着一行说明文字，拖到它下面时 newIndex 会越界
    final at = newIndex > list.length ? list.length : newIndex;
    list.insert(at, item);
    await Repo.reorderTemplates(list.map((e) => e.id).toList());
    await Store.i.afterTemplateChange();
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.i;

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('记账模板'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
      ),
      body: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          final list = s.templates;
          if (list.isEmpty) {
            return const Center(
              child: EmptyHint(
                icon: 'tpl',
                text: '还没有模板',
                hint: '把「早餐 ¥12 现金」这类常记的一笔存成模板，\n下次在「记一笔」顶部点一下就能填好',
              ),
            );
          }
          return ReorderableListView.builder(
            // 底部留白给「新增模板」按钮，别让它压住最后一行
            padding: const EdgeInsets.only(top: S.sm, bottom: 96),
            buildDefaultDragHandles: false,
            itemCount: list.length + 1,
            onReorderItem: _onReorder,
            itemBuilder: (context, i) {
              // 最后一项是说明文字。放进列表里跟着滚，
              // 这样它不会像固定页脚那样被悬浮按钮盖住。
              if (i == list.length) {
                return const Padding(
                  key: ValueKey('hint'),
                  padding: EdgeInsets.fromLTRB(S.xl, S.md, S.xl, 0),
                  child: Text(
                    '拖动左侧手柄可调整顺序；最常用的三个会自动出现在「记一笔」顶部。',
                    style: T.caption,
                  ),
                );
              }
              final t = list[i];
              return _TemplateRow(
                key: ValueKey(t.id),
                index: i,
                template: t,
                subtitle: _subtitle(t),
                onTap: () => _openEditor(t),
                onMore: () => _menu(t),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: C.ink,
        foregroundColor: C.bg,
        elevation: 0,
        icon: const LineIcon('plus', size: 20, color: C.bg, strokeWidth: 1.8),
        label: const Text('新增模板', style: T.body),
      ),
    );
  }

  String _subtitle(TxnTemplate t) {
    final cat = Store.i.categoryOf(t.categoryId)?.name ?? '未分类';
    final acc = Store.i.accountOf(t.accountId)?.name;
    final amount = t.hasAmount ? Fmt.yuan(t.amountCents) : '金额现填';
    return acc == null ? '$cat · $amount' : '$cat · $amount · $acc';
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    super.key,
    required this.index,
    required this.template,
    required this.subtitle,
    required this.onTap,
    required this.onMore,
  });

  final int index;
  final TxnTemplate template;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.md, 10, S.sm, 10),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: C.ink4,
                  ),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: C.bg2,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Center(
                  child: LineIcon(template.icon, size: 20, color: C.ink2),
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: T.body.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: T.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onMore,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: C.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 模板的新增 / 编辑页。
///
/// 做成整页而不是弹窗：分类九宫格 + 图标墙 + 账户选择器堆在一个对话框里
/// 会挤成一团，而且键盘弹起后弹窗会被顶出屏幕。
class TemplateEditorPage extends StatefulWidget {
  const TemplateEditorPage({super.key, this.initial});

  final TxnTemplate? initial;

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  late TxnType _type;
  late int? _categoryId;
  late int? _accountId;
  late String _icon;
  late bool _iconTouched;
  late final TextEditingController _name;
  late final TextEditingController _amount;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    final s = Store.i;
    _type = t?.type ?? TxnType.expense;
    _categoryId = t?.categoryId ?? _firstCategoryId();
    _accountId =
        t?.accountId ?? (s.accounts.isEmpty ? null : s.accounts.first.id);
    _icon = t?.icon ?? (s.categoryOf(_categoryId)?.icon ?? 'tpl');
    _iconTouched = t != null;
    _name = TextEditingController(text: t?.name ?? '');
    _amount = TextEditingController(
      text: (t != null && t.hasAmount)
          ? Fmt.money(t.amountCents, trimZero: true)
          : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  List<Category> get _cats =>
      _type.isIncome ? Store.i.incomeCats : Store.i.expenseCats;

  int? _firstCategoryId() {
    final list = _cats;
    return list.isEmpty ? null : list.first.id;
  }

  void _switchType(TxnType t) {
    setState(() {
      _type = t;
      _categoryId = _firstCategoryId();
      // 分类换了，图标跟着换 —— 除非用户自己挑过图标
      if (!_iconTouched) {
        _icon = Store.i.categoryOf(_categoryId)?.icon ?? 'tpl';
      }
    });
  }

  void _selectCategory(int id) {
    setState(() {
      _categoryId = id;
      if (!_iconTouched) {
        _icon = Store.i.categoryOf(id)?.icon ?? 'tpl';
      }
    });
  }

  /// 点一级分类后再弹双轮盘：可以直接确认（= 不细分），也能滚到子分类。
  ///
  /// 模板原先只能挂一级分类，「每月房租」选不到「居家 / 房租房贷」；
  /// 这里复用记一笔的同一个轮盘，数据层不用动（category_id 本来就存得下子分类）。
  Future<void> _pickCategory(int topId) async {
    final pick = await showCategoryWheel(
      context,
      cats: _cats,
      childrenOf: Store.i.childrenOf,
      selectedCategoryId: topId,
    );
    if (pick == null || !mounted) return;
    _selectCategory(pick.txnCategoryId);
  }

  Future<void> _save() async {
    final s = Store.i;
    if (_categoryId == null) {
      showToast(context, '请先选一个分类');
      return;
    }
    if (_accountId == null) {
      showToast(context, '请先选一个账户');
      return;
    }
    final name = _name.text.trim().isEmpty
        ? (s.categoryOf(_categoryId)?.name ?? '模板')
        : _name.text.trim();

    final t = TxnTemplate(
      id: widget.initial?.id ?? 0,
      ledgerId: s.ledgerId,
      name: name,
      icon: _icon,
      type: _type,
      amountCents: Fmt.parseCents(_amount.text),
      categoryId: _categoryId,
      accountId: _accountId,
      // 备注沿用原模板的，编辑页不单独暴露
      note: widget.initial?.note ?? '',
      sortOrder: widget.initial?.sortOrder ?? 0,
    );

    if (_isNew) {
      await Repo.insertTemplate(t);
    } else {
      await Repo.updateTemplate(t);
    }
    await s.afterTemplateChange();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: Text(_isNew ? '新建模板' : '编辑模板'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context, false),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              '保存',
              style: T.amountSm,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: S.xxl),
        children: [
          const SectionTitle('模板名称'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.xl),
            child: TextField(
              controller: _name,
              maxLength: 8,
              inputFormatters: [LengthLimitingTextInputFormatter(8)],
              style: T.body,
              decoration: InputDecoration(
                counterText: '',
                hintText: '例如：早餐、房租、地铁通勤',
                hintStyle: T.body2.copyWith(color: C.ink4),
                filled: true,
                fillColor: C.bg2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: S.md,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SectionTitle('类型'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.xl),
            child: SegTabs(value: _type, onChanged: _switchType),
          ),
          const SectionTitle('图标'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.xl),
            child: Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              children: [
                for (final k in _iconChoices())
                  GestureDetector(
                    onTap: () => setState(() {
                      _icon = k;
                      _iconTouched = true;
                    }),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: k == _icon ? C.ink : C.bg2,
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Center(
                        child: LineIcon(
                          k,
                          size: 19,
                          color: k == _icon ? C.bg : C.ink2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SectionTitle('分类'),
          if (_cats.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: S.xl),
              child: Text('还没有分类，请先到「我的 → 分类管理」添加', style: T.caption),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.xl),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: S.sm,
                  crossAxisSpacing: S.sm,
                  childAspectRatio: 0.86,
                ),
                itemCount: _cats.length,
                itemBuilder: (context, i) {
                  final c = _cats[i];
                  final on = c.id == _categoryId;
                  return GestureDetector(
                    onTap: () => _pickCategory(c.id),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: on ? C.ink : C.bg2,
                            borderRadius: BorderRadius.circular(R.md),
                          ),
                          child: Center(
                            child: LineIcon(
                              c.icon,
                              size: 21,
                              color: on ? C.bg : C.ink2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          c.name,
                          style: T.overline.copyWith(
                            color: on ? C.ink : C.ink2,
                            fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SectionTitle('账户'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.xl),
            child: Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              children: [
                for (final a in Store.i.accounts)
                  GestureDetector(
                    onTap: () => setState(() => _accountId = a.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: S.md,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: a.id == _accountId ? C.bg2 : C.bg,
                        border: Border.all(
                          color: a.id == _accountId ? C.ink : C.line,
                        ),
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LineIcon(a.icon, size: 16, color: C.ink2),
                          const SizedBox(width: 6),
                          Text(
                            a.name,
                            style: T.body2.copyWith(
                              color: C.ink,
                              fontWeight: a.id == _accountId
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SectionTitle('金额'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.xl),
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: T.body,
              decoration: InputDecoration(
                prefixText: '¥ ',
                prefixStyle: T.body.copyWith(color: C.ink2),
                hintText: '留空则每次现填',
                hintStyle: T.body2.copyWith(color: C.ink4),
                filled: true,
                fillColor: C.bg2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: S.md,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(S.xl, S.sm, S.xl, 0),
            child: Text(
              '填了金额 = 点模板就能一键入账；留空 = 只省掉选分类和账户的步骤。',
              style: T.caption,
            ),
          ),
        ],
      ),
    );
  }

  /// 图标墙：常用分类图标排前面，其余按图标库顺序补齐。
  /// 底部导航那几个（列表 / 饼图 / 人像 / 加号）不属于「一笔账」，剔除。
  List<String> _iconChoices() {
    const primary = [
      'food',
      'transport',
      'shopping',
      'home',
      'fun',
      'medical',
      'study',
      'comm',
      'gift',
      'salary',
      'bonus',
      'parttime',
      'invest',
      'redpacket',
      'tpl',
      'wallet',
      'coin',
      'target',
      'car',
      'laptop',
      'plane',
      'flag',
      'card',
      'book',
      'rec',
      'bell',
      'tag',
      'moon',
    ];
    const navOnly = {'list', 'pie', 'person', 'plus'};
    final rest = kIcons.keys.where((k) => !navOnly.contains(k));
    return <String>{...primary, ...rest}.toList();
  }
}
