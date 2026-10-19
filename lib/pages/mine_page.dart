import 'package:flutter/material.dart';

import '../app.dart';
import '../data/backup_service.dart';
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
          // 读 Store 的组件不能用 const 实例化（重建会被跳过）
          _NetWorthCard(),
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
                  subtitle:
                      '支出 ${s.expenseCats.length} 类 · 收入 ${s.incomeCats.length} 类',
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
          const SectionTitle('记账周期'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: SettingRow(
              icon: 'card',
              title: '账单日',
              subtitle: '每月 ${s.cycleStartDay} 号起算一期，到下月该日前一天',
              onTap: () => _pickCycleStartDay(context),
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
                // Excel 只带账单；下面这两行才是「换手机能原样搬过去」
                SettingRow(
                  icon: 'upload',
                  title: '备份全部数据',
                  subtitle: 'JSON，含预算、目标、模板、账户余额',
                  onTap: () => _backup(context),
                ),
                const Divider(height: 1, color: C.line, indent: 52),
                SettingRow(
                  icon: 'download',
                  title: '从备份恢复',
                  subtitle: '会覆盖当前全部数据，覆盖前自动留快照',
                  onTap: () => _restore(context),
                ),
              ],
            ),
          ),
          // 「清空」单独拎出来：它和导出/导入不是一类操作，混在一张卡里容易误触
          const SectionTitle('危险操作'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: SettingRow(
              icon: 'more',
              title: '清空全部数据',
              subtitle: '不可撤销，恢复成刚装好的样子',
              danger: true,
              onTap: () => _wipe(context),
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
          // 版本脚注：出问题时用户第一时间要报的就是这个号
          const Padding(
            padding: EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.lg),
            child: Text(
              '$kAppName v$kAppVersion · 本地版',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: C.ink4),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 账单日

  /// 选账单日。改完要把全部记录的归属期重算一遍，所以必须先说清楚再动手。
  static Future<void> _pickCycleStartDay(BuildContext context) async {
    final s = Store.i;
    final day = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => _CycleDaySheet(current: s.cycleStartDay),
    );
    if (day == null || day == s.cycleStartDay) return;
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg,
        title: const Text('改账单日？'),
        content: const Text(
          '会按新的账单日重算全部记账算在哪一期，并把已有预算挪到新的期上。'
          '金额一笔都不会动，变的只是「算在哪一期」。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await s.applyCycleStartDay(day);
    if (context.mounted) showToast(context, '账单日已改为 $day 号');
  }

  // ------------------------------------------------------------------ 导出

  static Future<void> _export(BuildContext context) async {
    final s = Store.i;
    if (s.txns.isEmpty) {
      // 本期没有不等于整个账本没有：导出是全量的，别因为这一期空就拦下来
      final months = await Repo.monthsWithData(s.ledgerId);
      if (months.isEmpty) {
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

  // ------------------------------------------------------------------ 备份

  static Future<void> _backup(BuildContext context) async {
    try {
      final path = await BackupService.writeToTempFile();
      if (!context.mounted) return;
      await BackupService.share(path);
    } catch (e) {
      if (context.mounted) showToast(context, '备份失败：$e');
    }
  }

  // ------------------------------------------------------------------ 恢复

  static Future<void> _restore(BuildContext context) async {
    final s = Store.i;

    // 1. 选文件 + 读出来校验（校验失败不会碰数据库）
    final Map<String, Object?> payload;
    final BackupSummary summary;
    try {
      final picked = await BackupService.pickFile();
      if (picked == null) return; // 用户取消
      payload = picked.$1;
      summary = BackupService.summarize(payload);
    } on BackupException catch (e) {
      if (context.mounted) showToast(context, e.message);
      return;
    }
    if (!context.mounted) return;

    // 2. 二次确认 —— 这是覆盖式写入，必须让人看清要拿什么换什么
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从备份恢复？', style: T.section),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('这份备份里有：', style: T.caption),
            const SizedBox(height: S.xs),
            Text(summary.text, style: T.body),
            const SizedBox(height: S.md),
            const Text(
              '恢复会**覆盖**当前的全部数据。\n覆盖前会自动存一份当前数据的快照，'
              '万一恢复错了还能再导回来。',
              style: T.body2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: C.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖并恢复', style: TextStyle(color: C.over)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    // 3. 先留快照，再覆盖
    String snapshot;
    try {
      snapshot = await BackupService.writeSnapshot();
    } catch (e) {
      if (context.mounted) showToast(context, '没能生成快照，已取消：$e');
      return;
    }

    try {
      final counts = await BackupService.restore(payload);
      await s.reloadAfterRestore();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复完成', style: T.section),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${counts['txn'] ?? 0} 笔记录 · ${counts['account'] ?? 0} 个账户 · '
                '${counts['category'] ?? 0} 个分类',
                style: T.body,
              ),
              const SizedBox(height: S.md),
              const Text('覆盖前的数据已存到：', style: T.caption),
              const SizedBox(height: S.xs),
              Text(snapshot, style: T.caption.copyWith(color: C.ink2)),
              const SizedBox(height: S.sm),
              const Text('如果这次恢复的结果不对，可以把这份快照再导回来。', style: T.caption),
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
    } catch (e) {
      if (context.mounted) showToast(context, '恢复失败，数据未改动：$e');
    }
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
                      subtitle:
                          '${a.kind.label} · ${Fmt.yuan(a.balanceCents)}'
                          '${a.includeInTotal ? '' : ' · 不计入净资产'}',
                      trailing: IconButton(
                        onPressed: () => _accountSheet(context, a),
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: C.ink3,
                        ),
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                        label: Text(
                          k.label,
                          style: const TextStyle(fontSize: 12.5),
                        ),
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
      await Repo.insertAccount(
        Account(
          id: 0,
          name: name,
          kind: kind,
          balanceCents: balance,
          includeInTotal: include,
          sortOrder: 999,
        ),
      );
    } else {
      await Repo.updateAccount(
        acc.copyWith(
          name: name,
          kind: kind,
          balanceCents: balance,
          includeInTotal: include,
        ),
      );
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
                          child: const Text(
                            '取消',
                            style: TextStyle(color: C.ink2),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, ctl.text.trim()),
                          child: const Text(
                            '创建',
                            style: TextStyle(color: C.ink),
                          ),
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
          Text(Fmt.yuan(s.netWorthCents), style: T.hero.copyWith(fontSize: 32)),
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

/// 账单日选择面板：1–31 号，短月自动收拢到月末（D14）。
class _CycleDaySheet extends StatelessWidget {
  const _CycleDaySheet({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: C.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
      ),
      padding: const EdgeInsets.only(top: S.md, bottom: S.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: C.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.xl, S.md, S.xl, S.sm),
            child: Row(
              children: [
                Text('账单日', style: T.section),
                const Spacer(),
                const Text('1–31 号，短月自动取月末', style: T.caption),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.md),
            child: GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var d = 1; d <= 31; d++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context, d),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: d == current ? C.ink : Colors.transparent,
                        border: Border.all(
                          color: d == current ? C.ink : C.line,
                        ),
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Text(
                        '$d',
                        style: T.body.copyWith(
                          color: d == current ? C.bg : C.ink,
                          fontWeight: d == current
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
