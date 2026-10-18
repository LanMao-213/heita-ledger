import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';

/// 周期账单管理。
///
/// 界面里会明确告诉用户执行机制 —— 单机应用没有后台服务，
/// **补记发生在打开 App 的那一刻**，这是必须讲清楚的预期管理。
class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key});

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  List<RecurringRule> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Repo.listRecurring(Store.i.ledgerId);
    if (!mounted) return;
    setState(() {
      _rules = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('周期账单'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.ink))
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(S.xl, S.sm, S.xl, S.md),
                  child: Text(
                    '房租、话费、订阅这类固定支出，设一次就够了。\n'
                    '应用不联网、没有后台服务，所以补记是在**每次打开应用时**'
                    '检查有没有到期，并把漏掉的按原定日期补上。',
                    style: T.caption,
                  ),
                ),
                if (_rules.isEmpty)
                  const EmptyHint(
                    icon: 'rec',
                    text: '还没有周期账单',
                    hint: '点右下角新建一条',
                  )
                else
                  for (final r in _rules) _RuleCard(rule: r, onChanged: _load),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        backgroundColor: C.ink,
        foregroundColor: C.bg,
        elevation: 0,
        icon: const LineIcon('plus', size: 20, color: C.bg, strokeWidth: 1.8),
        label: const Text('新建规则', style: TextStyle(fontSize: 14)),
      ),
    );
  }

  Future<void> _edit(BuildContext context, RecurringRule? rule) async {
    final s = Store.i;
    final amountCtl = TextEditingController(
      text: rule == null ? '' : (rule.amountCents / 100).toStringAsFixed(2),
    );
    final noteCtl = TextEditingController(text: rule?.note ?? '');
    var type = rule?.type ?? TxnType.expense;
    var categoryId = rule?.categoryId;
    var accountId =
        rule?.accountId ?? (s.accounts.isEmpty ? null : s.accounts.first.id);
    var freq = rule?.freq ?? 'monthly';
    var nextDate = rule?.nextRunDate ?? Fmt.today();

    const freqLabels = {
      'daily': '每天',
      'weekly': '每周',
      'monthly': '每月',
      'yearly': '每年',
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cats = type.isIncome ? s.incomeCats : s.expenseCats;
          return AlertDialog(
            title: Text(rule == null ? '新建周期账单' : '编辑规则', style: T.section),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegTabs(
                    value: type,
                    onChanged: (t) => setLocal(() {
                      type = t;
                      categoryId = null;
                    }),
                  ),
                  const SizedBox(height: S.md),
                  TextField(
                    controller: amountCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '¥ ',
                      hintText: '金额',
                    ),
                  ),
                  const SizedBox(height: S.md),
                  TextField(
                    controller: noteCtl,
                    decoration: const InputDecoration(hintText: '备注，如「房租」'),
                  ),
                  const SizedBox(height: S.md),
                  DropdownButtonFormField<int>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: '分类'),
                    items: [
                      for (final c in cats)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setLocal(() => categoryId = v),
                  ),
                  const SizedBox(height: S.md),
                  DropdownButtonFormField<String>(
                    initialValue: freq,
                    decoration: const InputDecoration(labelText: '重复'),
                    items: [
                      for (final e in freqLabels.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setLocal(() => freq = v ?? 'monthly'),
                  ),
                  const SizedBox(height: S.md),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.tryParse(nextDate) ?? now,
                        firstDate: DateTime(now.year - 3),
                        lastDate: DateTime(now.year + 5),
                        locale: const Locale('zh', 'CN'),
                      );
                      if (picked != null) {
                        setLocal(() => nextDate = Fmt.date(picked));
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: '下次记账日'),
                      child: Text(nextDate, style: T.body),
                    ),
                  ),
                  const SizedBox(height: S.md),
                  DropdownButtonFormField<int>(
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: '账户'),
                    items: [
                      for (final a in s.accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setLocal(() => accountId = v),
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
          );
        },
      ),
    );

    if (ok != true) return;
    final amount = Fmt.parseCents(amountCtl.text);
    if (amount <= 0) {
      if (context.mounted) showToast(context, '金额要大于 0');
      return;
    }

    if (rule == null) {
      await Repo.insertRecurring(
        RecurringRule(
          id: 0,
          ledgerId: s.ledgerId,
          type: type,
          amountCents: amount,
          categoryId: categoryId,
          accountId: accountId,
          note: noteCtl.text.trim(),
          freq: freq,
          nextRunDate: nextDate,
        ),
      );
    } else {
      await Repo.updateRecurring(
        RecurringRule(
          id: rule.id,
          ledgerId: rule.ledgerId,
          type: type,
          amountCents: amount,
          categoryId: categoryId,
          accountId: accountId,
          note: noteCtl.text.trim(),
          freq: freq,
          interval: rule.interval,
          nextRunDate: nextDate,
          endDate: rule.endDate,
          enabled: rule.enabled,
        ),
      );
    }
    await Store.i.afterTxnChange();
    if (context.mounted) showToast(context, '已保存');
    await _load();
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.onChanged});

  final RecurringRule rule;
  final Future<void> Function() onChanged;

  static const _freqLabels = {
    'daily': '每天',
    'weekly': '每周',
    'monthly': '每月',
    'yearly': '每年',
  };

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    final cat = s.categoryOf(rule.categoryId);
    final stale = rule.nextRunDate.compareTo(Fmt.today()) <= 0;

    return SectionCard(
      padding: const EdgeInsets.all(S.md),
      margin: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.xs),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: C.bg2,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: LineIcon(cat?.icon ?? 'rec', size: 19, color: C.ink),
            ),
          ),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.note.isNotEmpty ? rule.note : (cat?.name ?? '周期账单'),
                  style: T.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_freqLabels[rule.freq] ?? rule.freq} · '
                  '${rule.type.label} ${Fmt.money(rule.amountCents)} · '
                  '${stale ? '待补记' : '下次 ${Fmt.md(rule.nextRunDate)}'}',
                  style: T.caption.copyWith(color: stale ? C.over : C.ink3),
                ),
              ],
            ),
          ),
          Switch(
            value: rule.enabled,
            activeThumbColor: C.ink,
            onChanged: (v) async {
              await Repo.updateRecurring(
                RecurringRule(
                  id: rule.id,
                  ledgerId: rule.ledgerId,
                  type: rule.type,
                  amountCents: rule.amountCents,
                  categoryId: rule.categoryId,
                  accountId: rule.accountId,
                  note: rule.note,
                  freq: rule.freq,
                  interval: rule.interval,
                  nextRunDate: rule.nextRunDate,
                  endDate: rule.endDate,
                  enabled: v,
                ),
              );
              await onChanged();
            },
          ),
          IconButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除这条规则？', style: T.section),
                  content: const Text('已经补记过的账目不会受影响。', style: T.body2),
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
              if (ok != true) return;
              await Repo.deleteRecurring(rule.id);
              await onChanged();
            },
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: C.ink3,
            ),
          ),
        ],
      ),
    );
  }
}
