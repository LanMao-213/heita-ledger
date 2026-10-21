import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../stores/plan_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/icon_map.dart';
import '../../widgets/progress_bar.dart';

/// 分类预算列表。
///
/// 三件事只在这里做：
/// 1. **只画传进来的行**（哪些分类该出现由 `buildCategoryBudgetRows` 定，
///    口径只有一处）；
/// 2. 没设预算的行显示「未设」而不是 0% 的条（0% 看着像「花了 0」）；
/// 3. 点一行 → 编辑该分类的额度。
class CategoryBudgetList extends StatelessWidget {
  const CategoryBudgetList({
    super.key,
    required this.rows,
    required this.onEdit,
  });

  final List<CategoryBudgetRow> rows;
  final ValueChanged<CategoryBudgetRow> onEdit;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.page),
        child: Text(
          '本期还没有支出，也没有设分类预算。',
          key: const ValueKey<String>('category-budget-empty'),
          style: Ts.caption.copyWith(color: pal.ink3),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: S.card,
        vertical: S.sm,
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: pal.line),
            _Row(row: rows[i], onTap: () => onEdit(rows[i])),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.onTap});

  final CategoryBudgetRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return InkWell(
      key: ValueKey<String>('cat-budget-${row.category.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(IconMap.of(row.category.icon), size: 14, color: pal.ink3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ts.body2.copyWith(color: pal.ink),
                  ),
                ),
                if (!row.hasBudget)
                  Text(
                    '未设',
                    key: ValueKey<String>('cat-budget-unset-${row.category.id}'),
                    style: Ts.micro.copyWith(color: pal.ink4),
                  )
                else
                  Row(
                    children: <Widget>[
                      AmountText(
                        cents: row.spentCents,
                        tier: AmountTier.small,
                        color: row.overCents > 0 ? pal.over : pal.ink,
                      ),
                      Text(
                        ' / ${Fmt.money(row.budgetCents, trimZero: true)}',
                        style: Ts.micro.copyWith(color: pal.ink4),
                      ),
                    ],
                  ),
              ],
            ),
            if (row.hasBudget) ...<Widget>[
              const SizedBox(height: 6),
              ProgressBar(
                ratio: row.ratio,
                overCents: row.overCents,
                height: 5,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 编辑某个分类的本期限额。返回 `null` = 取消；返回分 = 应用（`<= 0` 即删行）。
Future<int?> showCategoryBudgetSheet(
  BuildContext context, {
  required String categoryName,
  required int currentCents,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _CategoryBudgetSheet(
      categoryName: categoryName,
      currentCents: currentCents,
    ),
  );
}

class _CategoryBudgetSheet extends StatefulWidget {
  const _CategoryBudgetSheet({
    required this.categoryName,
    required this.currentCents,
  });

  final String categoryName;
  final int currentCents;

  @override
  State<_CategoryBudgetSheet> createState() => _CategoryBudgetSheetState();
}

class _CategoryBudgetSheetState extends State<_CategoryBudgetSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.currentCents <= 0
        ? ''
        : Fmt.money(widget.currentCents, trimZero: true),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: pal.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        child: Padding(
          padding: const EdgeInsets.all(S.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${widget.categoryName} · 分类预算',
                style: Ts.section.copyWith(color: pal.ink),
              ),
              const SizedBox(height: S.md),
              TextField(
                key: const ValueKey<String>('cat-budget-amount'),
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: Ts.body.copyWith(color: pal.ink),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: pal.surfaceAlt,
                  hintText: '留空或 0 = 不设限',
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
              const SizedBox(height: S.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('cat-budget-save'),
                  onPressed: () {
                    final String raw = _amount.text.trim();
                    Navigator.of(context).pop(
                      raw.isEmpty ? 0 : Fmt.parseCents(raw),
                    );
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
