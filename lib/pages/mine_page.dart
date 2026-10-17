import 'package:flutter/material.dart';

import '../app.dart';
import '../data/db.dart';
import '../data/excel_service.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import 'cats_page.dart';
import 'recurring_page.dart';
import 'templates_page.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: S.xxl),
        children: [
          const _BrandHeader(),
          const _NetWorthCard(),
          const SectionTitle('管理'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingRow(
                  icon: 'wallet',
                  title: '账户管理',
                  subtitle: '${s.accounts.length} 个账户',
                  onTap: () => _manageAccounts(context),
                ),
                const Divider(height: 1, color: C.line, indent: 52),
                SettingRow(
                  icon: 'tag',
                  title: '分类管理',
                  subtitle: '支出 ${s.expenseCats.length} · 收入 ${s.incomeCats.length}',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CatsPage()),
                  ),
                ),
                const Divider(height: 1, color: C.line, indent: 52),
                SettingRow(
                  icon: 'tpl',
                  title: '记账模板',
                  subtitle: s.templates.isEmpty
                      ? '把常记的一笔存起来，一键填入'
                      : '${s.templates.length} 个模板',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TemplatesPage()),
                  ),
                ),
                const Divider(height: 1, color: C.line, indent: 52),
                SettingRow(
                  icon: 'book',
                  title: '账本管理',
                  subtitle: '${s.ledgers.length} 个账本',
                  onTap: () => _manageLedgers(context),
                ),
                const Divider(height: 1, color: C.line, indent: 52),
                SettingRow(
                  icon: 'rec',
                  title: '周期账单',
                  subtitle: '房租、话费这类每月固定支出',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecurringPage()),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('数据'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingRow(
                  icon: 'upload',
                  title: '导出账单到 Excel',
                  subtitle: '生成 .xlsx，可发微信 / 存网盘',
                  onTap: () => _export(context),
                ),
                const Divider(height: 1, color: C.line, indent: 52),
                SettingRow(
                  icon: 'download',
                  title: '从 Excel 导入账单',
                  subtitle: '按导出格式即可批量导入',
                  onTap: () => _import(context),
                ),
                const Divider(height: 1, color: C.line, indent: 52),
                SettingRow(
                  icon: 'more',
                  title: '清空全部数据',
                  subtitle: '恢复成刚装好的样子',
                  danger: true,
                  onTap: () => _wipe(context),
                ),
              ],
            ),
          ),
          const SectionTitle('关于'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const SettingRow(
                  icon: 'info',
                  title: kAppName,
                  subtitle: '版本 $kAppVersion · 数据存在本机',
                ),
                const Divider(height: 1, color: C.line, indent: 52),
                const SettingRow(
                  icon: 'lock',
                  title: '本地存储',
                  subtitle: '不联网、不上传，卸载即清空',
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, 0),
            child: Text(
              '所有数据保存在这台设备上，应用不会发起任何网络请求。\n'
              '换手机或重装前，记得先导出 Excel 备份。',
              style: T.caption,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 导出

  static Future<void> _export(BuildContext context) async {
    final s = Store.i;
    if (s.monthTxns.isEmpty) {
      final all = await Repo.monthTotals(s.ledgerId, s.month);
      if (all.$3 == 0) {
        if (context.mounted) showToast(context, '还没有记录可以导出');
        return;
      }
    }
    try {
      final path = await ExcelService.exportAll(
        s.ledgerId,
        ledgerName: s.currentLedger?.name,
      );
      if (!context.mounted) return;
      await ExcelService.share(path, text: '$kAppName 账单导出');
    } catch (e) {
      if (context.mounted) showToast(context, '导出失败：$e');
    }
  }

  // ------------------------------------------------------------------ 导入

  static Future<void> _import(BuildContext context) async {
    final s = Store.i;
    ImportResult? result;
    try {
      result = await ExcelService.pickAndImport(s.ledgerId);
    } catch (e) {
      if (context.mounted) showToast(context, '导入失败：$e');
      return;
    }
    if (result == null) return; // 用户取消了
    await s.afterTxnChange();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入完成', style: T.section),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result!.summary, style: T.body),
            if (result.problems.isNotEmpty) ...[
              const SizedBox(height: S.md),
              Text('有 ${result.problems.length} 行没能导入：', style: T.caption),
              const SizedBox(height: S.xs),
              for (final p in result.problems.take(6))
                Text('· $p', style: T.caption),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(color: C.ink)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 清空

  static Future<void> _wipe(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部数据？', style: T.section),
        content: const Text(
          '所有账目、账户、分类、目标都会被删除，且无法恢复。\n\n'
          '建议先导出 Excel 备份。',
          style: T.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: C.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空', style: TextStyle(color: C.over)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Db.wipeAllData();
    await Store.i.reboot();
    if (context.mounted) showToast(context, '已清空');
  }

  // -------------------------------------------------------------- 账户管理

  static Future<void> _manageAccounts(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx2, controller) => Column(
          children: [
            const SheetHeader(title: '账户管理'),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  for (final a in Store.i.accounts)
                    SettingRow(
                      icon: a.icon,
                      title: a.name,
                      subtitle: '${a.kind.label} · ${Fmt.yuan(a.balanceCents)}'
                          '${a.includeInTotal ? '' : ' · 不计入净资产'}',
                      trailing: IconButton(
                        onPressed: () => _accountSheet(context, a),
                        icon: const Icon(Icons.more_horiz_rounded,
                            size: 20, color: C.ink3),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(S.lg),
                    child: OutlinedButton.icon(
                      onPressed: () => _accountSheet(context, null),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: const BorderSide(color: C.line2),
                        foregroundColor: C.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                      ),
                      icon: const LineIcon('plus', size: 18, color: C.ink),
                      label: const Text('新增账户'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _accountSheet(BuildContext context, Account? acc) async {
    final nameCtl = TextEditingController(text: acc?.name ?? '');
    final balCtl = TextEditingController(
      text: acc == null ? '' : (acc.balanceCents / 100).toStringAsFixed(2),
    );
    var kind = acc?.kind ?? AccountKind.cash;
    var include = acc?.includeInTotal ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(acc == null ? '新增账户' : '编辑账户', style: T.section),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtl,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '账户名称'),
                ),
                const SizedBox(height: S.md),
                TextField(
                  controller: balCtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '当前余额（元）',
                    helperText: '记一笔时会自动增减',
                  ),
                ),
                const SizedBox(height: S.md),
                Wrap(
                  spacing: S.sm,
                  runSpacing: S.sm,
                  children: [
                    for (final k in AccountKind.values)
                      ChoiceChip(
                        label: Text(k.label, style: const TextStyle(fontSize: 12.5)),
                        selected: kind == k,
                        onSelected: (_) => setLocal(() => kind = k),
                        backgroundColor: C.bg2,
                        selectedColor: C.ink,
                        labelStyle: TextStyle(
                          color: kind == k ? C.bg : C.ink2,
                          fontSize: 12.5,
                        ),
                        side: BorderSide.none,
                        showCheckmark: false,
                      ),
                  ],
                ),
                const SizedBox(height: S.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: include,
                  onChanged: (v) => setLocal(() => include = v),
                  activeThumbColor: C.ink,
                  title: const Text('计入净资产', style: T.body2),
                ),
              ],
            ),
          ),
          actions: [
            if (acc != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('删除', style: TextStyle(color: C.over)),
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

    // 名称为空视为删除（仅编辑态）
    final name = nameCtl.text.trim();
    if (acc != null && name.isEmpty) {
      await Repo.deleteAccount(acc.id);
      await Store.i.afterAccountChange();
      if (context.mounted) showToast(context, '已删除');
      return;
    }
    if (name.isEmpty) return;

    final balance = Fmt.parseCents(balCtl.text);
    if (acc == null) {
      await Repo.insertAccount(Account(
        id: 0,
        name: name,
        kind: kind,
        balanceCents: balance,
        includeInTotal: include,
        sortOrder: 999,
      ));
    } else {
      await Repo.updateAccount(acc.copyWith(
        name: name,
        kind: kind,
        balanceCents: balance,
        includeInTotal: include,
      ));
    }
    await Store.i.afterAccountChange();
    if (context.mounted) showToast(context, '已保存');
  }

  // -------------------------------------------------------------- 账本管理

  static Future<void> _manageLedgers(BuildContext context) async {
    final s = Store.i;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(title: '账本管理'),
            for (final l in s.ledgers)
              SettingRow(
                icon: l.icon,
                title: l.name,
                subtitle: l.id == s.ledgerId ? '当前账本' : null,
                trailing: l.id == s.ledgerId
                    ? const Icon(Icons.check_rounded, size: 20, color: C.ink)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await s.switchLedger(l.id);
                },
              ),
            Padding(
              padding: const EdgeInsets.all(S.lg),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ctl = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: const Text('新建账本', style: T.section),
                      content: TextField(
                        controller: ctl,
                        autofocus: true,
                        maxLength: 12,
                        decoration: const InputDecoration(
                          hintText: '例如：装修账本',
                          counterText: '',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dctx),
                          child: const Text('取消',
                              style: TextStyle(color: C.ink2)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, ctl.text.trim()),
                          child: const Text('创建',
                              style: TextStyle(color: C.ink)),
                        ),
                      ],
                    ),
                  );
                  if (name == null || name.isEmpty) return;
                  final id = await Repo.insertLedger(Ledger(id: 0, name: name));
                  if (ctx.mounted) Navigator.pop(ctx);
                  await s.switchLedger(id);
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: C.line2),
                  foregroundColor: C.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                ),
                icon: const LineIcon('plus', size: 18, color: C.ink),
                label: const Text('新建账本'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- 头部

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.md),
      child: Row(
        children: [
          const BrandMark(height: 50),
          const SizedBox(width: S.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kAppName, style: T.title),
              const SizedBox(height: 2),
              Text('记账，简单点', style: T.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('净资产', style: T.caption),
          const SizedBox(height: 4),
          Text(
            Fmt.yuan(s.netWorthCents),
            style: T.hero.copyWith(fontSize: 32),
          ),
          if (s.accounts.isNotEmpty) ...[
            const SizedBox(height: S.md),
            const Divider(height: 1, color: C.line),
            const SizedBox(height: S.sm),
            for (final a in s.accounts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    LineIcon(a.icon, size: 17, color: C.ink3),
                    const SizedBox(width: S.sm),
                    Text(a.name, style: T.body2),
                    const Spacer(),
                    Text(
                      Fmt.yuan(a.balanceCents),
                      style: T.amountSm.copyWith(fontSize: 13.5),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
