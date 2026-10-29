import 'package:flutter/material.dart';

import '../app.dart';
import '../data/excel_service.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/backup_flow.dart';
import '../widgets/common.dart';
import '../widgets/menu.dart';
import '../widgets/restore_flow.dart';
import '../widgets/theme_sheet.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/wipe_flow.dart';

// ---------------------------------------------------------------------------
// 设置动作：一个入口，两个摆放位置
// ---------------------------------------------------------------------------
//
// 这些函数原本是 `MinePage` 的私有 static 方法，只有「我的」页能调。1.7.0 加了
// 侧拉栏之后，同一批动作需要出现在**两个**界面上（侧拉栏的「数据」「管理」组，
// 以及「我的」页原本那几张卡）。
//
// 摆在页面类里的话，侧拉栏要么 import 一个 page（把「我的」当成工具箱用），
// 要么把这些 SQL、文件选择、二次确认再抄一遍 —— 后者是最坏的情况：导出与恢复
// 的**文案和快照策略**必须只有一份，否则同一个动作在两个入口说两套话，用户
// 会以为那是两件不同的事（1.4.x 的「清空」就吃过这个亏）。
//
// 所以动作一律放到这里，页面与侧拉栏都只负责「把它们摆在菜单里」。

// ------------------------------------------------------------------ 偏好

/// 选主题。选中即生效 —— `Store.setTheme` 会让 ThemeCtrl 通知整树重建。
///
/// 这里**不能**在切换后弹 toast：换肤会重建 `_BootGate` 子树，
/// 这个 context 随之失效，再用它抓 Overlay 会拿到已被卸载的元素。
Future<void> pickTheme(BuildContext context) async {
  final s = Store.i;
  final picked = await showThemeSheet(context, current: s.themeId);
  if (picked == null || picked == s.themeId) return;
  await s.setTheme(picked);
}

// -------------------------------------------------------------- 账单日

/// 选账单日。改完要把全部记录的归属期重算一遍，所以必须先说清楚再动手。
Future<void> pickCycleStartDay(BuildContext context) async {
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

Future<void> exportExcel(BuildContext context) async {
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
/// 筛选条件由明细页设置、存在 `Store.filter.current` 里 —— 所以这里不需要再选一次，
/// 但要**先确认筛选是开着的**，否则用户会以为导出了筛选结果、其实是整本。
Future<void> exportFilteredExcel(BuildContext context) async {
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

Future<void> importExcel(BuildContext context) async {
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
//
// 导出与「从备份恢复」的实现都在 `lib/widgets/backup_flow.dart` /
// `restore_flow.dart` 里：任何入口走同一套动作，文案与快照策略必须是同一份。
// 这里只负责把它们接到按钮上。

// ------------------------------------------------------------------ 恢复

Future<void> restoreFromBackup(BuildContext context) async {
  // 1. 选文件 + 解出来（明文直接用，加密的要口令，最多试 3 次）。
  //    校验失败不会碰数据库 —— payload 解不出来就走不到 restore。
  final picked = await pickBackupFlow(context);
  if (picked == null || !context.mounted) return;

  // 2~4. 二次确认 → 先留快照 → 覆盖 → 结果弹窗，全在 [runRestoreFlow] 里
  //      （「数据安全」页恢复自动快照走的是同一套，口径必须是同一份）
  await runRestoreFlow(
    context,
    payload: picked.payload,
    summary: picked.summary,
    sourceLabel: picked.name,
  );
}

// ------------------------------------------------------------------ 清空

/// 清空全部数据。流程本体在 [runWipeFlow]，和「从备份恢复」一样是覆盖式写。
Future<void> wipeAllData(BuildContext context) => runWipeFlow(context);

// -------------------------------------------------------------- 账户管理

Future<void> manageAccounts(BuildContext context) async {
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 「默认」徽章：记账面板会预选它，这件事在账户
                              // 列表上得看得见，否则用户设完就再也找不到证据。
                              if (a.id == Store.i.defaultExpenseAccountId)
                                const _DefaultBadge(),
                              IconButton(
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
                            ],
                          ),
                        ),
                      ),
                    MenuTile(
                      action: MenuAction(
                        // 转账是账户之间的动作，入口就放在账户管理里。
                        // 记一笔面板的四档（支出/收入/借出/借入）刻意不加
                        // 第五档：那四档都在回答「这笔算收入还是支出」，
                        // 而转账两者都不是，统计里不该出现。
                        //
                        // popFirst 用默认的 true：转完账 `Store.addTxn` 会把
                        // 视角搬到明细页，账户弹层留在上面就成了「盖在另一页
                        // 上的旧弹层」。
                        icon: 'coin',
                        title: '转账',
                        subtitle: '账户之间挪钱，不计入收支',
                        onTap: () => showTransferSheet(context),
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
Future<void> _accountMenu(BuildContext context, Account a) async {
  final s = Store.i;
  final isDefault = s.defaultExpenseAccountId == a.id;
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
          // 默认支出账户：设 / 取消都在这一个位置上，靠标题区分 ——
          // 分成两条（一条「设为默认」一条「取消默认」）会让禁用中的那条
          // 也留在菜单里，用户得先判断哪条才有效。
          MenuAction(
            icon: 'check',
            title: isDefault ? '取消默认支出账户' : '设为默认支出账户',
            subtitle: isDefault ? '记账面板当前预选这个账户' : '记账面板新建一笔时预选它',
            checked: isDefault,
            onTap: () => s.setDefaultExpenseAccount(isDefault ? null : a.id),
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
Future<void> _confirmDeleteAccount(BuildContext context, Account a) async {
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
        final cur = others.where((o) => o.id == target).firstOrNull;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              empty ? '这个账户没有余额，也没有记录。' : '余额和记录会并到这个账户：',
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
              Text('$count 笔记录会挂到目标账户名下，历史不丢。', style: T.caption),
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

Future<void> _accountSheet(BuildContext context, Account? acc) async {
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                  label: Text(k.label, style: T.caption),
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

Future<void> manageLedgers(BuildContext context) async {
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
          MenuAction(icon: 'plus', title: '新建账本', onTap: () => _newLedger(context)),
        ],
      ),
      // 删除单独一组、且每本各占一行：它和上面那组「切过去」是两种意图，
      // 混在同一组里最容易被误点 —— 而这一步不可恢复。
      MenuGroup(
        actions: [
          for (final l in s.ledgers)
            MenuAction(
              icon: 'trash',
              title: '删除「${l.name}」',
              danger: true,
              onTap: () => _confirmDeleteLedger(context, l),
            ),
        ],
      ),
    ],
  );
}

/// 删除账本：先说清会删掉多少笔，再动手。
///
/// 两条硬规则：
/// 1. **至少保留一个账本** —— 没有账本时所有查询都按一个不存在的 ledger_id
///    去查，界面空白，用户会以为数据全没了；
/// 2. 二次确认里必须写出**笔数**。「删除账本」听起来像删一个文件夹，
///    实际上里面的账目一起没 —— 不写数字，用户不会意识到这是一次清空。
Future<void> _confirmDeleteLedger(BuildContext context, Ledger l) async {
  final s = Store.i;
  if (s.ledgers.length <= 1) {
    showToast(context, '至少保留一个账本');
    return;
  }
  final count = await Repo.ledgerTxnCount(l.id);
  if (!context.mounted) return;

  final ok = await showAppDialog<bool>(
    context: context,
    title: '删除「${l.name}」？',
    content: Text('该账本内的 $count 笔账目会一起删除，不可恢复。', style: T.body2),
    actions: const [
      DialogAction(label: '取消', value: false),
      DialogAction(label: '删除', value: true, danger: true),
    ],
  );
  if (ok != true || !context.mounted) return;

  // 删的是当前账本时，Store.deleteLedger 会切到剩余的第一本并重载
  await s.deleteLedger(l.id);
  if (context.mounted) showToast(context, '已删除「${l.name}」');
}

/// 新建账本：问名字 → 建 → 切过去。
Future<void> _newLedger(BuildContext context) async {
  final s = Store.i;
  final ctl = TextEditingController();
  final name = await showAppDialog<String>(
    context: context,
    title: '新建账本',
    content: TextField(
      controller: ctl,
      autofocus: true,
      maxLength: 12,
      decoration: const InputDecoration(hintText: '例如：装修账本', counterText: ''),
    ),
    actions: [
      const DialogAction(label: '取消'),
      DialogAction(label: '创建', valueOf: () => ctl.text.trim(), strong: true),
    ],
  );
  if (name == null || name.isEmpty) return;
  final added = await s.addLedger(name);
  if (added > 0 && context.mounted) {
    showToast(context, '已补记 $added 笔周期账单');
  }
}

// --------------------------------------------------------------------- 组件

/// 「默认」小徽章：标在记账面板会预选的那个支出账户上。
///
/// 用 `bg2` 底 + `ink3` 字，不是实心 `ink` 底：它是一条**状态说明**，
/// 不是「已达成」那种结论。做得和余额一样抢眼，扫列表时反而读不出重点。
class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      // 右边留 2：紧挨着那颗 ⋯，不留缝隙会看成同一个控件
      margin: const EdgeInsets.only(right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(R.xs),
      ),
      child: Text('默认', style: T.overline.copyWith(color: C.ink3)),
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
                    border: Border.all(color: d == current ? C.ink : C.line),
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
