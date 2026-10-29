import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../design/icons.dart';
import '../design/palette.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/backup_flow.dart';
import '../widgets/common.dart';
import '../widgets/menu.dart';
import '../widgets/storage_note.dart';
import 'cats_page.dart';
import 'help_page.dart';
import 'import_bill_page.dart';
import 'recurring_page.dart';
import 'safety_page.dart';
import 'settings_actions.dart';
import 'templates_page.dart';

/// 「我的」：全部设置项的**摆放位置**。
///
/// 这个文件只管布局：每一行点下去做什么，全在 `settings_actions.dart` 里。
/// 为什么分开 —— 1.7.0 的侧拉栏要复用其中大半动作（账户、账本、账单日、导出、
/// 备份、恢复、清空），动作留在页面类里就得抄一份或者让侧拉栏去 import 一个 page。
/// 抄一份意味着同一个动作在两个入口有两套文案，而「清空」这类动作的措辞差一句
/// 就是一次数据事故。
///
/// 页头从「品牌标志 + 应用名」改成「侧拉栏按钮 + 应用名」：品牌标志移到侧拉栏
/// 顶部（那是它该在的地方 —— 一个跨全 App 的身份标识，不是某一页的装饰）。
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
          const Padding(
            padding: EdgeInsets.only(top: S.sm),
            child: PageHeader(title: kAppName, leading: MenuButton()),
          ),
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
                  onTap: () => manageAccounts(context),
                ),
                const SettingDivider(),
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
                const SettingDivider(),
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
                const SettingDivider(),
                SettingRow(
                  icon: 'book',
                  title: '账本管理',
                  subtitle: '${s.ledgers.length} 个账本',
                  onTap: () => manageLedgers(context),
                ),
                const SettingDivider(),
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
              onTap: () => pickCycleStartDay(context),
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
                  onTap: () => exportExcel(context),
                ),
                const SettingDivider(),
                SettingRow(
                  icon: 'filter',
                  title: '导出当前筛选结果',
                  subtitle: '只导明细页正在看的那部分',
                  onTap: () => exportFilteredExcel(context),
                ),
                const SettingDivider(),
                SettingRow(
                  icon: 'download',
                  title: '从 Excel 导入账单',
                  subtitle: '按导出格式即可批量导入',
                  onTap: () => importExcel(context),
                ),
                const SettingDivider(),
                // 支付宝 / 微信账单是**别人的格式**：只补流水、不动余额，
                // 所以单独一个入口，不并进上面那条 Excel 导入 ——
                // 两条的语义完全不同（一个改余额，一个不改），混在一起用户会误判。
                SettingRow(
                  icon: 'download',
                  title: '从支付宝 / 微信账单导入',
                  subtitle: 'CSV（需 UTF-8 编码），逐行过目后再算入',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImportBillPage(ledgerId: Store.i.ledgerId),
                    ),
                  ),
                ),
                const SettingDivider(),
                // Excel 只带账单；下面这几行才是「换手机能原样搬过去」。
                //
                // 加密与明文是**并列的两个入口**，不是「高级选项」：两者导出
                // 的内容一字不差（同一份 payload），区别只在容器。所以副标题
                // 各自把代价说清 —— 一个说「口令忘了打不开」，一个说「谁能
                // 拿到谁能读」，让用户在两个代价之间选，而不是默认替他选。
                SettingRow(
                  icon: 'lock',
                  title: '加密备份',
                  subtitle: '设一个口令，文件离开手机也打不开（口令不保存）',
                  onTap: () => runSealedExportFlow(context),
                ),
                const SettingDivider(),
                SettingRow(
                  icon: 'upload',
                  title: '明文备份',
                  // 副标题必须写明「未加密」：这是一份能被任何文本编辑器打开的
                  // 明文 JSON，里面是整本账（含备注、账户余额、「借给谁」）。
                  subtitle: '明文 JSON（未加密），适合只存在自己的电脑里',
                  onTap: () => runPlainExportFlow(context),
                ),
                const SettingDivider(),
                SettingRow(
                  icon: 'download',
                  title: '从备份恢复',
                  subtitle: '会覆盖当前全部数据，覆盖前自动留快照',
                  onTap: () => restoreFromBackup(context),
                ),
                const SettingDivider(),
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
          // 出厂默认圣地 · 审判白（见 kDefaultTheme），老版本升上来也是它。
          const SectionTitle('偏好'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: Column(
              children: [
                SettingRow(
                  icon: 'palette',
                  title: '主题',
                  subtitle: '${paletteOf(s.themeId).name} · 共 ${kPalettes.length} 套',
                  onTap: () => pickTheme(context),
                ),
                const SettingDivider(),
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
              onTap: () => wipeAllData(context),
            ),
          ),
          const SectionTitle('关于'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: S.sm),
            child: Column(
              children: [
                SettingRow(
                  icon: 'help',
                  title: '帮助说明',
                  subtitle: '记账规则、备份、隐私，一篇看完',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HelpPage()),
                  ),
                ),
                const SettingDivider(),
                const SettingRow(
                  icon: 'info',
                  title: kAppName,
                  subtitle: '版本 $kAppVersion · 数据存在本机',
                ),
                const SettingDivider(),
                SettingRow(
                  icon: 'lock',
                  title: '本地存储',
                  subtitle: '不联网、不上传 · 点开看数据存在哪',
                  onTap: () => showAppDialog<void>(
                    context: context,
                    title: '账本存在哪',
                    content: const StorageNote(),
                    actions: const [DialogAction(label: '知道了', strong: true)],
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
          Text(Fmt.yuan(s.netWorthWithDebtCents), style: T.hero),
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
            const SettingDivider(indent: 0),
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
                    Text(Fmt.yuan(a.balanceCents), style: T.amountXs),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
