import 'package:flutter/material.dart';

import '../app.dart';
import '../data/backup_service.dart';
import '../data/db.dart';
import '../data/excel_service.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/hairline.dart';
import '../design/icons.dart';
import '../design/palette.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/menu.dart';
import '../widgets/restore_flow.dart';
import '../widgets/storage_note.dart';
import '../widgets/theme_sheet.dart';
import 'cats_page.dart';
import 'import_bill_page.dart';
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
                  icon: 'filter',
                  title: '导出当前筛选结果',
                  subtitle: '只导明细页正在看的那部分',
                  onTap: () => _exportFiltered(context),
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
                // 支付宝 / 微信账单是**别人的格式**：只补流水、不动余额，
                // 所以单独一个入口，不并进上面那条 Excel 导入 ——
                // 两条的语义完全不同（一个改余额，一个不改），混在一起用户会误判。
                SettingRow(
                  icon: 'download',
                  title: '从支付宝 / 微信账单导入',
                  subtitle: 'CSV（需 UTF-8 编码），逐行过目后再算入',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ImportBillPage(ledgerId: Store.i.ledgerId),
                    ),
                  ),
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
          // 偏好：主题 + 触感。
          //
          // 主题这一行为什么存在：配色是记账 App 里少有的「纯个人口味」项 ——
          // 有人夜里记账要深色，有人觉得深色刺眼，谁也说服不了谁。
          // 与其挑一套当唯一答案，不如六套都给，让用户自己挑。
          // 出厂默认黑塔·永夜（见 kDefaultTheme），老版本升上来也是它。
          const SectionTitle('偏好'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: Column(
              children: [
                SettingRow(
                  icon: 'palette',
                  title: '主题',
                  subtitle: '${paletteOf(s.themeId).name} · 共 ${kPalettes.length} 套',
                  onTap: () => _pickTheme(context),
                ),
                Divider(
                  height: 1,
                  thickness: hairlineOf(context),
                  color: C.line,
                  indent: 52,
                ),
                // 为什么给这个开关：震动是「我们替用户做的决定」，而它恰好有两类人
                // 会立刻反感 —— 开会/夜里记账的人、以及手机常年静音连触感也关掉的人。
                // 系统层面关掉当然有效，但用户不会为了一个记账 App 去翻系统设置。
                //
                // 没有「音量」开关：这个应用**不出声**（全仓库没有一处 SystemSound /
                // 音频库），没有开关可加。真要做提示音属于新功能，不是开关。
                SettingRow(
                  icon: 'pulse',
                  title: '触感反馈',
                  subtitle:
                      s.hapticsEnabled ? '记账、删除时短震一下' : '已关闭，不做任何震动',
                  onTap: () => s.setHapticsEnabled(!s.hapticsEnabled),
                  trailing: Switch(
                    value: s.hapticsEnabled,
                    onChanged: s.setHapticsEnabled,
                  ),
                ),
              ],
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
                SettingRow(
                  icon: 'lock',
                  title: '本地存储',
                  subtitle: '不联网、不上传 · 点开看数据存在哪',
                  onTap: () => showAppDialog<void>(
                    context: context,
                    title: '账本存在哪',
                    content: const StorageNote(),
                    actions: const [
                      DialogAction(label: '知道了', strong: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
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

  // ---------------------------------------------------------------- 主题

  /// 选主题。选中即生效 —— `Store.setTheme` 会让 ThemeCtrl 通知整树重建。
  ///
  /// 这里**不能**在切换后弹 toast：换肤会重建 `_BootGate` 子树，
  /// 这个 context 随之失效，再用它抓 Overlay 会拿到已被卸载的元素。
  static Future<void> _pickTheme(BuildContext context) async {
    final s = Store.i;
    final picked = await showThemeSheet(context, current: s.themeId);
    if (picked == null || picked == s.themeId) return;
    await s.setTheme(picked);
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

    final ok = await showAppConfirm(
      context,
      title: '改账单日？',
      message: '会按新的账单日重算全部记账算在哪一期，并把已有预算挪到新的期上。'
          '金额一笔都不会动，变的只是「算在哪一期」。',
    );
    if (!ok) return;

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

  /// 导出「当前筛选结果」。
  ///
  /// 和上面的整本导出是两件事：那个是备份，这个是交付（「把这个月的餐饮发我」）。
  /// 筛选条件由明细页设置、存在 [Store.filter.current] 里 —— 所以这里不需要再选一次，
  /// 但要**先确认筛选是开着的**，否则用户会以为导出了筛选结果、其实是整本。
  static Future<void> _exportFiltered(BuildContext context) async {
    final s = Store.i;
    if (s.filter.current.isEmpty) {
      showToast(context, '先在明细页设置筛选条件');
      return;
    }
    try {
      final path = await ExcelService.exportAll(
        s.ledgerId,
        ledgerName: s.currentLedger?.name,
        filter: s.filter.current,
      );
      if (!context.mounted) return;
      await ExcelService.share(path, text: '$kAppName 筛选结果导出');
    } catch (e) {
      if (context.mounted) showToast(context, '导出失败：$e');
    }
  }

  // ------------------------------------------------------------------ 导入

  static Future<void> _import(BuildContext context) async {
    final s = Store.i;
    ImportResult? result;
    try {
      result = await s.importExcel();
    } catch (e) {
      if (context.mounted) showToast(context, '导入失败：$e');
      return;
    }
    final done = result;
    if (done == null) return; // 用户取消了
    if (!context.mounted) return;

    await showAppNotice(
      context,
      title: '导入完成',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(done.summary, style: T.body),
          if (done.problems.isNotEmpty) ...[
            const SizedBox(height: S.md),
            Text('有 ${done.problems.length} 行没能导入：', style: T.caption),
            const SizedBox(height: S.xs),
            for (final p in done.problems.take(6)) Text('· $p', style: T.caption),
          ],
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
    final ok = await showAppConfirm(
      context,
      title: '清空全部数据？',
      message: '所有账目、账户、分类、目标都会被删除，恢复成刚装好的样子。\n\n'
          '清空前会自动存一份快照，后悔了可以从「我的 → 数据安全」里找回来。',
      confirmLabel: '确认清空',
      danger: true,
    );
    if (!ok || !context.mounted) return;

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
      await showAppNotice(
        context,
        title: '已清空',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('账目、账户、分类都已恢复成刚装好的样子。', style: T.body2),
            const SizedBox(height: S.md),
            Text('清空前的数据已存到：', style: T.caption),
            const SizedBox(height: S.xs),
            Text(snapshot, style: T.caption.copyWith(color: C.ink2)),
            const SizedBox(height: S.sm),
            Text(
              '要找回来的话，去「我的 → 数据安全」用这份快照恢复。',
              style: T.caption,
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => AnimatedBuilder(
        // 删除/合并后会改 Store.i.accounts，列表要跟着重建
        animation: Store.i,
        builder: (ctx, _) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (ctx2, controller) => SheetShell(
            title: '账户管理',
            child: Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.only(bottom: S.lg),
                children: [
                  MenuGroup(
                    children: [
                      for (final a in Store.i.accounts)
                        MenuTile(
                          action: MenuAction(
                            icon: a.icon,
                            title: a.name,
                            subtitle:
                                '${a.kind.label} · ${Fmt.yuan(a.balanceCents)}'
                                '${a.includeInTotal ? '' : ' · 不计入净资产'}',
                            // 不关这一层：账户菜单是叠在它上面的另一层，
                            // 关掉就回不到列表了
                            popFirst: false,
                            // 行本身也能点开菜单：目标小、又在底部弹层里，
                            // 只靠右边那颗 ⋯ 容易点空
                            onTap: () => _accountMenu(context, a),
                            trailing: IconButton(
                              onPressed: () => _accountMenu(context, a),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              icon: LineIcon(
                                'more', semanticLabel: '更多',
                                size: 20,
                                color: C.ink3,
                              ),
                            ),
                          ),
                        ),
                      MenuTile(
                        action: MenuAction(
                          icon: 'plus',
                          title: '新增账户',
                          popFirst: false,
                          onTap: () => _accountSheet(context, null),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
    await showMenuSheet<void>(
      context: context,
      title: a.name,
      groups: [
        MenuGroup(
          actions: [
            MenuAction(
              icon: 'tpl',
              title: '编辑资料',
              subtitle: '名称 · 类型 · 余额校准',
              onTap: () => _accountSheet(context, a),
            ),
            MenuAction(
              icon: 'trash',
              title: '删除账户',
              subtitle: '余额和记录会转到一个你指定的账户',
              danger: true,
              onTap: () => _confirmDeleteAccount(context, a),
            ),
          ],
        ),
      ],
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
    final ok = await showAppDialog<bool>(
      context: context,
      title: '删除「${a.name}」？',
      content: StatefulBuilder(
        builder: (ctx, setLocal) {
          final cur =
              others.where((o) => o.id == target).firstOrNull;
          return Column(
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
                PickField(
                  label: '并到',
                  valueText: cur == null
                      ? ''
                      : '${cur.name} · ${Fmt.yuan(cur.balanceCents)}',
                  onTap: () async {
                    final v = await showPickSheet<int>(
                      context: ctx,
                      title: '并到哪个账户',
                      options: [
                        for (final o in others)
                          PickOption(
                            value: o.id,
                            icon: o.icon,
                            title: o.name,
                            subtitle: Fmt.yuan(o.balanceCents),
                          ),
                      ],
                      current: target,
                    );
                    if (v != null) setLocal(() => target = v);
                  },
                ),
                const SizedBox(height: S.md),
                Text(
                  '$count 笔记录会挂到目标账户名下，历史不丢。',
                  style: T.caption,
                ),
              ],
            ],
          );
        },
      ),
      actions: const [
        DialogAction(label: '取消', value: false),
        DialogAction(label: '删除', value: true, danger: true),
      ],
    );

    if (ok != true || !context.mounted) return;
    if (empty) {
      await s.deleteAccount(a.id);
    } else {
      if (target == null) return;
      await s.mergeAccount(from: a.id, to: target!);
    }
    if (context.mounted) {
      showToast(context, empty ? '已删除' : '已删除，余额和记录已并入目标账户');
    }
  }

  static Future<void> _accountSheet(BuildContext context, Account? acc) async {
    final nameCtl = TextEditingController(text: acc?.name ?? '');
    final balCtl = TextEditingController(
      text: acc == null ? '' : Fmt.plain(acc.balanceCents),
    );
    var kind = acc?.kind ?? AccountKind.cash;
    var include = acc?.includeInTotal ?? true;

    final ok = await showAppDialog<bool>(
      context: context,
      title: acc == null ? '新增账户' : '编辑账户',
      content: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
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
              title: Text('计入净资产', style: T.body2),
            ),
          ],
        ),
      ),
      actions: [
        if (acc != null)
          // ⚠️ 这颗「删除」带回的是 false，和「取消」一样 —— 也就是说它
          // 按下去什么也不做（删账户走账户菜单里的那条）。行为原样保留，
          // 但要删请走菜单；这里留着是为了不让老用户找不到位置。
          const DialogAction(label: '删除', value: false, danger: true),
        const DialogAction(label: '保存', value: true, strong: true),
      ],
    );
    if (ok != true) return;

    // 名称为空视为删除（仅编辑态）
    final name = nameCtl.text.trim();
    if (acc != null && name.isEmpty) {
      await Store.i.deleteAccount(acc.id);
      if (context.mounted) showToast(context, '已删除');
      return;
    }
    if (name.isEmpty) return;

    final balance = Fmt.parseCents(balCtl.text);
    // 新账户还没有流水，手填的余额就是期初值 —— v8 起必须显式写，
    // 否则默认 0 会让「余额 = 期初 + 流水合计」当场不成立。
    // 这两种情况在 `Store.saveAccount` 里已经收束（新建写期初、编辑走
    // `Repo.saveAccount`），这里只描述"要存成什么样"。
    await Store.i.saveAccount(
      acc == null
          ? Account(
              id: 0,
              name: name,
              kind: kind,
              includeInTotal: include,
              sortOrder: 999,
            )
          : acc.copyWith(name: name, kind: kind, includeInTotal: include),
      balanceCents: balance,
    );
    if (context.mounted) showToast(context, '已保存');
  }

  // -------------------------------------------------------------- 账本管理

  static Future<void> _manageLedgers(BuildContext context) async {
    final s = Store.i;
    await showMenuSheet<void>(
      context: context,
      title: '账本管理',
      groups: [
        MenuGroup(
          actions: [
            for (final l in s.ledgers)
              MenuAction(
                icon: l.icon,
                title: l.name,
                subtitle: l.id == s.ledgerId ? '当前账本' : null,
                checked: l.id == s.ledgerId,
                onTap: () async {
                  final added = await s.switchLedger(l.id);
                  if (added > 0 && context.mounted) {
                    showToast(context, '已补记 $added 笔周期账单');
                  }
                },
              ),
            MenuAction(
              icon: 'plus',
              title: '新建账本',
              onTap: () => _newLedger(context),
            ),
          ],
        ),
      ],
    );
  }

  /// 新建账本：问名字 → 建 → 切过去。
  static Future<void> _newLedger(BuildContext context) async {
    final s = Store.i;
    final ctl = TextEditingController();
    final name = await showAppDialog<String>(
      context: context,
      title: '新建账本',
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
        const DialogAction(label: '取消'),
        DialogAction(
          label: '创建',
          valueOf: () => ctl.text.trim(),
          strong: true,
        ),
      ],
    );
    if (name == null || name.isEmpty) return;
    final added = await s.addLedger(name);
    if (added > 0 && context.mounted) {
      showToast(context, '已补记 $added 笔周期账单');
    }
  }
}

// --------------------------------------------------------------------- 头部

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    // 50px 的标志压在最上面、又不承担任何功能，是「装饰占着最贵的位置」。
    // 收到 28 并进同一条页头：四页的内容起点从此对齐在同一高度。
    return Padding(
      padding: const EdgeInsets.only(top: S.sm),
      child: PageHeader(
        title: kAppName,
        leading: const BrandMark(height: 28),
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
            style: T.hero,
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
                      style: T.amountXs,
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
    return SheetShell(
      title: '账单日',
      subtitle: '1–31 号，短月自动取月末',
      child: Padding(
        // 与上面「账单日」标题行同是 16，两者左右对齐
        padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.lg),
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
    );
  }
}
