import 'package:flutter/material.dart';

import '../data/backup_compat.dart';
import '../data/backup_service.dart';
import '../design/tokens.dart';
import '../store.dart';
import 'busy_dialog.dart';
import 'common.dart';
import 'menu.dart';

/// 覆盖式恢复的统一流程：**二次确认 → 先留快照 → 写入 → 结果弹窗**。
///
/// 抽出来是因为有两个入口要走同一套动作：
/// - 侧拉栏的「备份与恢复 → 从备份恢复」（用户自己挑文件）
/// - 侧拉栏的「数据安全」里直接恢复某一份自动快照
///
/// 文案、快照策略、失败口径必须一致，复制两份迟早走偏 —— 尤其「先留快照」
/// 这一步，漏一处就等于多了一条不可逆路径。
///
/// 返回 true 表示真的恢复了；取消 / 失败都是 false（失败已经弹过提示）。
Future<bool> runRestoreFlow(
  BuildContext context, {
  required Map<String, Object?> payload,
  required BackupSummary summary,
  String? sourceLabel,
}) async {
  // 1. 二次确认 —— 覆盖式写入，必须让人看清拿什么换什么
  final ok = await showAppDialog<bool>(
    context: context,
    title: '覆盖当前数据？',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sourceLabel != null) ...[
          Text('来源：$sourceLabel', style: T.caption),
          const SizedBox(height: S.xs),
        ],
        Text('这份备份里有：', style: T.caption),
        const SizedBox(height: S.xs),
        Text(summary.text, style: T.body),
        const SizedBox(height: S.md),
        Text(
          '恢复会覆盖当前的全部数据。覆盖前会自动存一份当前数据的快照，'
          '万一恢复错了还能从「数据安全」里再导回来。',
          style: T.body2,
        ),
      ],
    ),
    actions: const [
      DialogAction(label: '取消', value: false),
      DialogAction(label: '覆盖并恢复', value: true, danger: true),
    ],
  );
  if (ok != true || !context.mounted) return false;

  // 2. 先留快照，再覆盖。留不下就取消 —— 不能开一条不可逆的口子
  final String snapshot;
  try {
    snapshot = await BackupService.writeSnapshot(reason: 'restore');
  } catch (e) {
    if (context.mounted) showToast(context, '没能生成快照，已取消：$e');
    return false;
  }

  // 留快照这一步也要好几帧（读全表 + 写盘），回来时 context 可能已经不在了
  if (!context.mounted) return false;

  // 3. 写入 + 重载
  //
  // 这一步是整个应用里最重的一次写：整库替换 + 跑迁移 + 重载全部投影。
  // 20k 笔的库要几秒，期间界面必须**看得出在跑** —— 一个几秒的冻结界面，
  // 用户会以为崩了然后把 App 划掉（而此时事务正在写）。
  try {
    // 老备份可能少几个字段、或带着已经废弃的列：兼容动作记在这里，
    // 恢复完一并告诉用户 —— 悄悄丢一列比明说「忽略了 2 个旧字段」危险得多。
    final compat = ConformReport();
    final counts = await runWithBusy(
      context,
      message: '正在恢复…（约几秒，请不要退出）',
      task: () async {
        final n = await BackupService.restore(payload, report: compat);
        await Store.i.reloadAfterRestore();
        return n;
      },
    );
    if (!context.mounted) return true;
    await showAppNotice(
      context,
      title: '恢复完成',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${counts['txn'] ?? 0} 笔记录 · ${counts['account'] ?? 0} 个账户 · '
            '${counts['category'] ?? 0} 个分类',
            style: T.body,
          ),
          if (compat.summary != null) ...[
            const SizedBox(height: S.xs),
            Text('这份备份较旧：${compat.summary}', style: T.caption),
          ],
          const SizedBox(height: S.md),
          Text('覆盖前的数据已存到：', style: T.caption),
          const SizedBox(height: S.xs),
          Text(snapshot, style: T.caption.copyWith(color: C.ink2)),
          const SizedBox(height: S.sm),
          Text('如果这次恢复的结果不对，去侧拉栏的「数据安全」用这份快照再导回来。', style: T.caption),
        ],
      ),
    );
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, '恢复失败，数据未改动：$e');
    return false;
  }
}
