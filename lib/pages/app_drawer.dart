import 'package:flutter/material.dart';

import '../app.dart';
import '../design/hairline.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/backup_flow.dart';
import '../widgets/menu.dart';
import '../widgets/transfer_sheet.dart';
import 'cats_page.dart';
import 'help_page.dart';
import 'import_bill_page.dart';
import 'onboarding_page.dart';
import 'recurring_page.dart';
import 'safety_page.dart';
import 'settings_actions.dart';
import 'templates_page.dart';

/// 侧拉栏：把「导航 / 管理 / 数据 / 帮助」全部收进一个从左边拉出来的面。
///
/// ## 为什么要它
///
/// 加它之前，这个 App 的功能分布是：四页底栏负责看账，其余**十四个**入口全部
/// 堆在「我的」页那一长条列表里（导出、加密备份、恢复、数据安全、账户、分类、
/// 账本、模板、周期账单、账单日、主题、触感、清空、帮助）。结果是两件事同时
/// 发生：常用动作（记一笔、转账）要滑到底找；不复用的设置项把常用项挤到屏幕
/// 外面。侧拉栏把这两类分开摆放，且**任何页面都能一次手势到达**。
///
/// ## 三处刻意设计
///
/// 1. **按组摆放，组可收起**。19 个入口平铺仍然是灾难，所以分五组；组标题可点，
///    收起后这组只剩一行标题。收起状态只记在内存（不给它落库）—— 它是「这会儿
///    不想看这一组」的临时偏好，不是设置项，为它加一张表或一个键都不值当。
/// 2. **当前页有标记**。导航组里当前那一页左边有一条墨色竖线 + 文字加粗：抽屉
///    打开时用户第一件事是确认「我现在在哪」。
/// 3. **动作要等抽屉收完再执行**。直接在执行里 `closeDrawer()` 然后立刻 push，
///    新页面会从还没收回的抽屉上方压过去 —— 抽屉在半空中被盖住，返回时它还在。
///    所以统一走 [_run]，把动作排到收起动画之后。
///
/// ## 为什么把 `hostContext` 当参数传进来
///
/// 抽屉里几乎所有动作都要弹一个对话框或 push 一个页面，而**这个 widget 自己
/// 在抽屉收起后就被销毁了**（`Scaffold` 在 dismissed 状态不构建抽屉子树），
/// 拿着它的 context 去 `showDialog` 会拿到一个已被卸载的元素。宿主（[HomeShell]）
/// 的 context 一直活着，所以动作一律在宿主上执行。
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.hostContext,
    required this.onRecord,
  });

  /// 宿主页面的 context（关掉抽屉之后仍然有效）
  final BuildContext hostContext;

  /// 「记一笔」。由宿主提供，这样扫过账之后的提示语只有一处实现
  final VoidCallback onRecord;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  /// 收起的分组 id。**会话内有效**，不落库（理由见类注释第 1 条）。
  static final Set<String> _collapsed = <String>{};

  /// 关抽屉 → 等收起动画 → 在宿主上执行动作。
  ///
  /// 用 `closeDrawer()` 而不是 `Navigator.pop()`：抽屉不是一条路由，
  /// pop 掉的是底下那个页面。
  void _run(void Function(BuildContext) action) {
    final host = widget.hostContext;
    Scaffold.of(context).closeDrawer();
    Future<void>.delayed(M.base, () {
      if (host.mounted) action(host);
    });
  }

  /// 导入账单：两条路的语义完全不同（Excel 会改账户余额，支付宝/微信 CSV 不改、
  /// 而是反向调期初），混成一个入口用户会误判 —— 所以合成一张菜单，让名字先说清楚。
  void _showImportMenu(BuildContext host) {
    showMenuSheet<void>(
      context: host,
      title: '导入账单',
      groups: [
        MenuGroup(
          actions: [
            MenuAction(
              icon: 'doc',
              title: 'Excel (.xlsx)',
              subtitle: '按导出格式批量导入，会改账户余额',
              onTap: () => importExcel(host),
            ),
            MenuAction(
              icon: 'doc',
              title: '支付宝 / 微信账单 CSV',
              subtitle: '逐行过目后再算入，不改余额',
              onTap: () => Navigator.of(host).push(
                MaterialPageRoute<void>(
                  builder: (_) => ImportBillPage(ledgerId: Store.i.ledgerId),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 备份与恢复：同一份数据的三个动作，收进一层。
  ///
  /// 为什么不再并列成三行：加密与明文导出的**内容一字不差**，区别只在容器；
  /// 而恢复两种都认。三个入口摆在抽屉里，等于逼用户在打开抽屉的那一刻就决定
  /// 「我要加密还是明文」，而他此刻想的是「备个份」。
  void _showBackupMenu(BuildContext host) {
    showMenuSheet<void>(
      context: host,
      title: '备份与恢复',
      subtitle: '三者的内容相同，区别只在容器与方向',
      groups: [
        MenuGroup(
          actions: [
            MenuAction(
              icon: 'lock',
              title: '加密备份',
              subtitle: '.heita · 要口令，忘口令不可恢复',
              onTap: () => runSealedExportFlow(host),
            ),
            MenuAction(
              icon: 'doc',
              title: '明文备份',
              subtitle: '.json · 谁拿到谁能读',
              onTap: () => runPlainExportFlow(host),
            ),
            MenuAction(
              icon: 'download',
              title: '从备份恢复',
              subtitle: '加密与明文都认，按内容判型',
              onTap: () => restoreFromBackup(host),
            ),
          ],
        ),
      ],
    );
  }

  /// 帮助：把「重看引导」和「帮助说明」放一起 —— 两者都是「我忘了怎么用」。
  ///
  /// 引导以前是抽屉里独立一行。它一年用不到第二次，却和管理类入口同样醒目，
  /// 而真正会被反复翻的是帮助说明。
  void _showHelpMenu(BuildContext host) {
    showMenuSheet<void>(
      context: host,
      title: '帮助',
      groups: [
        MenuGroup(
          actions: [
            MenuAction(
              icon: 'help',
              title: '帮助说明',
              subtitle: '记账规则、备份、隐私，一篇看完',
              onTap: () => Navigator.of(host).push(
                MaterialPageRoute<void>(builder: (_) => const HelpPage()),
              ),
            ),
            MenuAction(
              icon: 'bulb',
              title: '重看使用引导',
              subtitle: '五步，随时可以再看一遍',
              onTap: () => showOnboarding(host),
            ),
          ],
        ),
      ],
    );
  }

  void _push(Widget page) => _run(
    (host) =>
        Navigator.of(host).push(MaterialPageRoute<void>(builder: (_) => page)),
  );

  void _toggle(String id) {
    setState(() {
      if (!_collapsed.remove(id)) _collapsed.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: C.bg,
      // 右侧两角圆一点：抽屉是从屏幕外滑进来的一个「面」，圆角让它看起来
      // 是浮在内容之上的一层，而不是把界面切掉一块
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(R.sheet)),
      ),
      child: SafeArea(
        child: AnimatedBuilder(
          // 当前账本名、账户数、当前 tab 都可能变，抽屉打开时要读到最新的
          animation: Store.i,
          builder: (context, _) => Column(
            children: [
              const _Header(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // 唯一的「动作」行。记一笔由底栏中央的「+」承担，抽屉里
                    // 再放一条就是同一个动作两个入口（1.7.3 删）。
                    _Entry(
                      icon: 'coin',
                      label: '转账',
                      hint: '账户之间挪钱',
                      onTap: () => _run(showTransferSheet),
                    ).build(context),
                    _group(
                      id: 'ledger',
                      title: '账本',
                      entries: [
                        _Entry(
                          icon: 'wallet',
                          label: '账户管理',
                          hint: '${Store.i.accounts.length} 个',
                          onTap: () => _run(manageAccounts),
                        ),
                        _Entry(
                          icon: 'tag',
                          label: '分类管理',
                          onTap: () => _push(const CatsPage()),
                        ),
                        _Entry(
                          icon: 'book',
                          label: '账本管理',
                          hint: '${Store.i.ledgers.length} 个',
                          onTap: () => _run(manageLedgers),
                        ),
                        _Entry(
                          icon: 'tpl',
                          label: '记账模板',
                          onTap: () => _push(const TemplatesPage()),
                        ),
                        _Entry(
                          icon: 'rec',
                          label: '周期账单',
                          onTap: () => _push(const RecurringPage()),
                        ),
                        _Entry(
                          icon: 'card',
                          label: '账单日',
                          hint: '每月 ${Store.i.cycleStartDay} 号',
                          onTap: () => _run(pickCycleStartDay),
                        ),
                      ],
                    ),
                    _group(
                      id: 'data',
                      title: '数据',
                      entries: [
                        _Entry(
                          icon: 'upload',
                          label: '导出 Excel',
                          onTap: () => _run(exportExcel),
                        ),
                        // 导入原本只在「我的」页：导出在抽屉、导入在设置页，
                        // 同一件事的两个方向被拆到两处，是最容易「找不到」的形态。
                        _Entry(
                          icon: 'download',
                          label: '导入账单',
                          hint: 'Excel / 支付宝',
                          onTap: () => _run(_showImportMenu),
                        ),
                        // 加密 / 明文 / 恢复是同一份数据的三个动作。三个并列入口
                        // 让用户在这里就要做「加密还是明文」的决定，而他此刻想的
                        // 只是「备个份」。收进一层，进到里面再选。
                        _Entry(
                          icon: 'lock',
                          label: '备份与恢复',
                          hint: '加密 / 明文 / 恢复',
                          onTap: () => _run(_showBackupMenu),
                        ),
                        _Entry(
                          icon: 'shield',
                          label: '数据安全',
                          hint: '快照与回滚',
                          onTap: () => _push(const SafetyPage()),
                        ),
                      ],
                    ),
                    _group(
                      id: 'help',
                      title: '帮助',
                      entries: [
                        _Entry(
                          icon: 'help',
                          label: '帮助与引导',
                          onTap: () => _run(_showHelpMenu),
                        ),
                      ],
                    ),
                    _footer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 分组

  Widget _group({
    required String id,
    required String title,
    required List<_Entry> entries,
  }) {
    final collapsed = _collapsed.contains(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _toggle(id),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.only(left: S.lg, right: S.lg),
              child: Row(
                children: [
                  Text(
                    title,
                    style: T.overline.copyWith(
                      color: C.ink3,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // 收起时箭头朝右（-90°），展开时朝下。用旋转而不是换图标：
                  // 位置和大小都不动，转起来才像「同一个东西折叠了」
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: M.fast,
                    curve: M.standard,
                    child: LineIcon('chevron_down', size: 16, color: C.ink4),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: M.fast,
          curve: M.standard,
          alignment: Alignment.topCenter,
          child: collapsed
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final e in entries) e.build(context)],
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: S.xs),
          child: Divider(
            height: hairlineOf(context),
            thickness: hairlineOf(context),
            color: C.line,
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '不联网 · 数据只在这台设备上',
            style: T.caption.copyWith(color: C.ink3),
          ),
          const SizedBox(height: 2),
          Text('$kAppName v$kAppVersion', style: T.overline.copyWith(color: C.ink4)),
        ],
      ),
    );
  }
}

/// 抽屉顶部：品牌 + 当前账本。
///
/// 品牌标志从「我的」页头搬到这里 —— 一个 App 的身份标识属于导航面，
/// 不属于某一页的装饰。
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final s = Store.i;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, S.md),
      child: Row(
        children: [
          const BrandMark(height: 34),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  kAppName,
                  style: T.section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '当前账本 · ${s.currentLedger?.name ?? '账本'}',
                  style: T.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 抽屉里的一行。
///
/// 1.7.3 去掉了 `active`（「你正在这一页」的竖线标记）：那个标记只服务于
/// 「导航」组，而导航组已经删掉 —— 底栏四个 tab 本身就是当前位置的标记，
/// 抽屉再去标一遍，等于在一个不承担导航的面里做导航。
class _Entry {
  const _Entry({
    required this.icon,
    required this.label,
    this.hint,
    required this.onTap,
  });

  final String icon;
  final String label;

  /// 右侧的补充信息（「3 个」「每月 1 号」）。不是必需：绝大多数行不需要
  final String? hint;

  final VoidCallback onTap;

  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: S.lg),
            LineIcon(icon, size: 19, color: C.ink2),
            const SizedBox(width: S.md),
            Expanded(
              child: Text(
                label,
                style: T.body.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(left: S.sm),
                child: Text(hint!, style: T.caption),
              ),
            const SizedBox(width: S.lg),
          ],
        ),
      ),
    );
  }
}
