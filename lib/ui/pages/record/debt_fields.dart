import 'package:flutter/material.dart';

import '../../../core/local_date.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// 借贷模式的三字段：对方（必填）、应还日（可空）、计入预算（仅借入）。
///
/// 口径（§3.2）：
/// - **借出恒不计入预算**（钱不是消费），所以「计入预算」开关只在借入时出现；
/// - 对方为空**不能保存**（「未填对方」的债务在按人汇总里会挤成一堆，用户找不到）。
class DebtFields extends StatelessWidget {
  const DebtFields({
    super.key,
    required this.borrow,
    required this.counterparty,
    required this.dueDate,
    required this.countInBudget,
    required this.onCounterpartyChanged,
    required this.onDueDateChanged,
    required this.onCountInBudgetChanged,
    this.today,
  });

  /// true = 借入（我欠别人）；false = 借出（别人欠我）。
  final bool borrow;

  final String counterparty;
  final LocalDate? dueDate;
  final bool countInBudget;

  final ValueChanged<String> onCounterpartyChanged;
  final ValueChanged<LocalDate?> onDueDateChanged;
  final ValueChanged<bool> onCountInBudgetChanged;

  final LocalDate? today;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final LocalDate now = today ?? LocalDate.today();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          key: const ValueKey<String>('record-counterparty'),
          initialValue: counterparty,
          style: Ts.body.copyWith(color: pal.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: pal.surfaceAlt,
            labelText: borrow ? '出借人' : '欠款人',
            hintText: borrow ? '向谁借的' : '谁欠你',
            hintStyle: Ts.body2.copyWith(color: pal.ink4),
            labelStyle: Ts.caption.copyWith(color: pal.ink3),
            border: OutlineInputBorder(
              borderRadius: R.rMd,
              borderSide: BorderSide(color: pal.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: R.rMd,
              borderSide: BorderSide(color: pal.line),
            ),
          ),
          onChanged: onCounterpartyChanged,
        ),
        const SizedBox(height: S.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey<String>('record-due-date'),
                onPressed: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: (dueDate ?? now.addDays(30)).toDateTime(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    onDueDateChanged(LocalDate.fromDateTime(picked));
                  }
                },
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(
                  dueDate == null
                      ? '应还日（可不填）'
                      : '应还 ${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ts.body2.copyWith(color: pal.ink2),
                ),
              ),
            ),
            if (dueDate != null)
              IconButton(
                key: const ValueKey<String>('record-due-clear'),
                onPressed: () => onDueDateChanged(null),
                icon: Icon(Icons.close, size: 16, color: pal.ink3),
                tooltip: '清除应还日',
              ),
          ],
        ),
        // 借出恒不计入预算（数据层还会再强改一次）；只有借入给开关
        if (borrow)
          // 外面那层 DecoratedBox 有底色，ListTile 需要自己的透明 Material
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey<String>('record-count-in-budget'),
              value: countInBudget,
              onChanged: onCountInBudgetChanged,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '计入本期预算',
                style: Ts.body2.copyWith(color: pal.ink),
              ),
              subtitle: Text(
                '打开后，这笔借入会抬高本期的可用额度',
                style: Ts.caption.copyWith(color: pal.ink3),
              ),
            ),
          ),
      ],
    );
  }
}
