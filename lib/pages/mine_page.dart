import 'package:flutter/material.dart';

import '../app.dart';
import '../data/backup_service.dart';
import '../data/db.dart';
import '../data/excel_service.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/hairline.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/restore_flow.dart';
import 'cats_page.dart';
import 'recurring_page.dart';
import 'safety_page.dart';
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
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: Column(
              children: [
                SettingRow(
                  icon: 'wallet',
                  title: '账户管理',
                  subtitle: '${s.accounts.length} 个账户',
                  onTap: () => _manageAccounts(context),
                ),
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
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
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
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
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
                SettingRow(
                  icon: 'book',
                  title: '账本管理',
                  subtitle: '${s.ledgers.length} 个账本',
                  onTap: () => _manageLedgers(context),
                ),
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
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
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: SettingRow(
              icon: 'card',
              title: '账单日',
              subtitle: '每月 ${s.cycleStartDay} 号起算一期，到下月该日前一天',
              onTap: () => _pickCycleStartDay(context),
            ),
          ),
          const SectionTitle('数据'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: Column(
              children: [
                SettingRow(
                  icon: 'upload',
                  title: '导出账单到 Excel',
                  subtitle: '生成 .xlsx，可发微信 / 存网盘',
                  onTap: () => _export(context),
                ),
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
                SettingRow(
                  icon: 'download',
                  title: '从 Excel 导入账单',
                  subtitle: '按导出格式即可批量导入',
                  onTap: () => _import(context),
                ),
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
                // Excel 只带账单；下面这两行才是「换手机能原样搬过去」
                SettingRow(
                  icon: 'upload',
                  title: '备份全部数据',
                  subtitle: 'JSON，含预算、目标、模板、账户余额',
                  onTap: () => _backup(context),
                ),
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
                SettingRow(
                  icon: 'download',
                  title: '从备份恢复',
                  subtitle: '会覆盖当前全部数据，覆盖前自动留快照',
                  onTap: () => _restore(context),
                ),
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
                SettingRow(
                  icon: 'shield',
                  title: '数据安全',
                  subtitle: '清空 / 恢复前的自动快照，可回滚',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SafetyPage()),
                  ),
                ),
              ],
            ),
          ),
          // 偏好：目前只有触感一项。
          //
          // 为什么给这个开关：震动是「我们替用户做的决定」，而它恰好有两类人
          // 会立刻反感 —— 开会/夜里记账的人、以及手机常年静音连触感也关掉的人。
          // 系统层面关掉当然有效，但用户不会为了一个记账 App 去翻系统设置。
          //
          // 没有「音量」开关：这个应用**不出声**（全仓库没有一处 SystemSound /
          // 音频库），没有开关可加。真要做提示音属于新功能，不是开关。
          const SectionTitle('偏好'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: SettingRow(
              icon: 'pulse',
              title: '触感反馈',
              subtitle: s.hapticsEnabled ? '记账、删除时短震一下' : '已关闭，不做任何震动',
              onTap: () => s.setHapticsEnabled(!s.hapticsEnabled),
              trailing: Switch(
                value: s.hapticsEnabled,
                onChanged: s.setHapticsEnabled,
              ),
            ),
          ),
          // 「清空」单独拎出来：它和导出/导入不是一类操作，混在一张卡里容易误触
          const SectionTitle('危险操作'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: SettingRow(
              icon: 'more',
              title: '清空全部数据',
              // 1.4.3 起清空前会自动留快照、能从「数据安全」回滚，
              // 再写「不可撤销」就是骗人 —— 这行是 1.4.3 改弹窗时漏下的
              subtitle: '会先自动存一份快照，可找回',
              danger: true,
              onTap: () => _wipe(context),
            ),
          ),
          const SectionTitle('关于'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: Column(
              children: [
                const SettingRow(
                  icon: 'info',
                  title: kAppName,
                  subtitle: '版本 $kAppVersion · 数据存在本机',
                ),
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
                const SettingRow(
                  icon: 'lock',
                  title: '本地存储',
                  subtitle: '不联网、不上传，卸载即清空',
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(S.lg, S.xl, S.lg, 0),
            child: Text(
              '所有数据保存在这台设备上，应用不会发起任何网络请求。\n'
              '换手机或重装前，记得先导出 Excel 备份。',
              style: T.caption,
            ),
          ),
          // 版本脚注：出问题时用户第一时间要报的就是这个号
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.xl, S.lg, S.lg),
            child: Text(
              '$kAppName v$kAppVersion · 本地版',
              textAlign: TextAlign.center,
              style: T.overline.copyWith(color: C.ink3),
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

    // 2~4. 二次确认 → 先留快照 → 覆盖 → 结果弹窗，全在 [runRestoreFlow] 里
    //      （「数据安全」页恢复自动快照走的是同一套，口径必须是同一份）
    await runRestoreFlow(context, payload: payload, summary: summary);
  }

  // ------------------------------------------------------------------ 清空

  static Future<void> _wipe(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部数据？', style: T.section),
        content: const Text(
          '所有账目、账户、分类、目标都会被删除，恢复成刚装好的样子。\n\n'
          '清空前会自动存一份快照，后悔了可以从「我的 → 数据安全」里找回来。',
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
    if (ok != true || !context.mounted) return;

    // 先留快照再清：清空是单向门，1.4.1 就栽在「不可逆 + 静默失败」上。
    // 留不下就**不清**，和「从备份恢复」的策略保持一致 —— 宁可这次没清成，
    // 也不要开一条找不回来的口子。
    final String snapshot;
    try {
      snapshot = await BackupService.writeSnapshot(reason: 'wipe');
    } catch (e) {
      if (context.mounted) showToast(context, '没能生成快照，已取消：$e');
      return;
    }

    // 失败必须说出来：异常在 1.4.1 里被悄悄吞掉，用户看到的就是
    // 「点了没反应、数据还在」。现在删除与重建在同一个事务里（见
    // `Db.wipeAllData`），抛异常等于整体回滚，所以可以明确说「数据未改动」。
    try {
      await Db.wipeAllData();
      await Store.i.reboot();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('已清空', style: T.section),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('账目、账户、分类都已恢复成刚装好的样子。', style: T.body2),
              const SizedBox(height: S.md),
              const Text('清空前的数据已存到：', style: T.caption),
              const SizedBox(height: S.xs),
              Text(snapshot, style: T.caption.copyWith(color: C.ink2)),
              const SizedBox(height: S.sm),
              const Text(
                '要找回来的话，去「我的 → 数据安全」用这份快照恢复。',
                style: T.caption,
              ),
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
      if (context.mounted) showToast(context, '清空失败，数据未改动：$e');
    }
  }

  // -------------------------------------------------------------- 账户管理

  static Future<void> _manageAccounts(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AnimatedBuilder(
        // 删除/合并后会改 Store.i.accounts，列表要跟着重建
        animation: Store.i,
        builder: (ctx, _) => DraggableScrollableSheet(
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
                        // 行本身也能点开菜单：目标小、又在底部弹层里，
                        // 只靠右边那颗 ⋯ 容易点空
                        onTap: () => _accountMenu(context, a),
                        trailing: IconButton(
                          onPressed: () => _accountMenu(context, a),
                          icon: const LineIcon(
                            'more', semanticLabel: '更多',
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
      ),
    );
  }

  /// 账户的二级菜单：编辑 / 删除。
  ///
  /// 原来那颗 ⋯ 点下去直接跳「编辑账户」，名字叫「更多」、行为却是编辑 ——
  /// 想删账户的人在弹层里翻不到入口，只能以为它不能删。
  static Future<void> _accountMenu(BuildContext context, Account a) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: a.name),
            SettingRow(
              icon: 'tpl',
              title: '编辑资料',
              subtitle: '名称 · 类型 · 余额校准',
              showChevron: false,
              onTap: () {
                Navigator.pop(ctx);
                _accountSheet(context, a);
              },
            ),
            SettingRow(
              icon: 'trash',
              title: '删除账户',
              subtitle: '余额和记录会转到一个你指定的账户',
              danger: true,
              showChevron: false,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteAccount(context, a);
              },
            ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }

  /// 删除账户：余额与流水一并并入另一个账户。
  ///
  /// 直接删会留下孤儿流水（`txn.account_id` 没有外键），所以凡是有余额或
  /// 有记录的账户，都必须先选一个「倒去哪」。
  static Future<void> _confirmDeleteAccount(
    BuildContext context,
    Account a,
  ) async {
    final s = Store.i;
    final others = s.accounts.where((x) => x.id != a.id).toList();
    final count = await Repo.accountTxnCount(a.id);
    if (!context.mounted) return;

    final empty = count == 0 && a.balanceCents == 0;
    // 唯一账户且有数据：没法合并，只能先建一个
    if (!empty && others.isEmpty) {
      showToast(context, '这是唯一的账户，先新建一个账户再删');
      return;
    }

    var target = others.isEmpty ? null : others.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('删除「${a.name}」？', style: T.section),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                empty
                    ? '这个账户没有余额，也没有记录。'
                    : '余额和记录会并到这个账户：',
                style: T.body2,
              ),
              if (!empty) ...[
                const SizedBox(height: S.md),
                DropdownButtonFormField<int>(
                  initialValue: target,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '并到',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final o in others)
                      DropdownMenuItem(
                        value: o.id,
                        child: Text('${o.name} · ${Fmt.yuan(o.balanceCents)}'),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => target = v),
                ),
                const SizedBox(height: S.md),
                Text(
                  '$count 笔记录会挂到目标账户名下，历史不丢。',
                  style: T.caption,
                ),
              ],
            ],
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
      ),
    );

    if (ok != true || !context.mounted) return;
    if (empty) {
      await Repo.deleteAccount(a.id);
    } else {
      if (target == null) return;
      await Repo.mergeAccount(from: a.id, to: target!);
    }
    await s.afterAccountChange();
    if (context.mounted) {
      showToast(context, empty ? '已删除' : '已删除，余额和记录已并入目标账户');
    }
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
                          style: T.caption,
                        ),
                        selected: kind == k,
                        onSelected: (_) => setLocal(() => kind = k),
                        backgroundColor: C.bg2,
                        selectedColor: C.ink,
                        labelStyle: T.caption.copyWith(
                          color: kind == k ? C.bg : C.ink2,
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
      // 新账户还没有流水，手填的余额就是期初值 —— v8 起必须显式写，
      // 否则默认 0 会让「余额 = 期初 + 流水合计」当场不成立
      await Repo.insertAccount(
        Account(
          id: 0,
          name: name,
          kind: kind,
          balanceCents: balance,
          openingCents: balance,
          includeInTotal: include,
          sortOrder: 999,
        ),
      );
    } else {
      // 手填余额改的是期初（opening_cents），不是余额本身，见 Repo.saveAccount
      await Repo.saveAccount(
        acc.copyWith(name: name, kind: kind, includeInTotal: include),
        balance,
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
                    ? const LineIcon('check', size: 20, color: C.ink)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  final added = await s.switchLedger(l.id);
                  if (added > 0 && context.mounted) {
                    showToast(context, '已补记 $added 笔周期账单');
                  }
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
                  final added = await s.switchLedger(id);
                  if (added > 0 && context.mounted) {
                    showToast(context, '已补记 $added 笔周期账单');
                  }
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
      padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, S.md),
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
            Fmt.yuan(s.netWorthWithDebtCents),
            style: T.hero.copyWith(fontSize: 32),
          ),
          // 借出/借入：账户余额只反映现金，这里把应收应付补上，
          // 否则借出 5000 会看起来像「钱少了 5000」
          if (s.receivableCents > 0 || s.payableCents > 0) ...[
            const SizedBox(height: 4),
            Text(
              '含应收 ${Fmt.yuan(s.receivableCents)} · 应付 ${Fmt.yuan(s.payableCents)}',
              style: T.caption.copyWith(color: C.ink3),
            ),
          ],
          if (s.accounts.isNotEmpty) ...[
            const SizedBox(height: S.md),
            Divider(height: 1, thickness: hairlineOf(context), color: C.line),
            const SizedBox(height: S.sm),
            for (final a in s.accounts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.xs),
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
              borderRadius: BorderRadius.circular(R.xs),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
            child: Row(
              children: [
                Text('账单日', style: T.section),
                const Spacer(),
                const Text('1–31 号，短月自动取月末', style: T.caption),
              ],
            ),
          ),
          Padding(
            // 与上面「账单日」标题行同是 16，两者左右对齐
            padding: const EdgeInsets.symmetric(horizontal: S.lg),
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
