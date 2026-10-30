import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../data/db.dart';
import '../design/tokens.dart';
import '../store.dart';
import 'common.dart';
import 'menu.dart';

/// 清空全部数据的统一流程：**二次确认 → 先留快照 → 清空 → 重启 → 结果弹窗**。
///
/// ## 为什么要单独成一个文件
///
/// 「从备份恢复」早就有 [runRestoreFlow] 了，「清空全部数据」却一直住在
/// `mine_page.dart` 的静态方法里。这两件事是**同一类风险**：
///
///   都是覆盖式写、都是单向门、都必须「先留一条退路再动手」。
///
/// 一样东西只在一个文件里有名字，另一个埋在某个页面的私有方法里时，下一个人
/// 加第三个入口（比如「设置 → 重置」）就会照抄页面里那份，然后漏掉快照那一步
/// —— 而漏掉快照不会报错、不会崩，只会在用户真后悔的那天才发现没有退路。
/// 1.4.1 就栽在「不可逆 + 静默失败」上。
///
/// 所以这里把顺序写死：**快照拿不到就什么都不做**。宁可这次没清成，也不开
/// 一条找不回来的口子。
///
/// 返回 true 表示真的清空了；取消 / 失败都是 false（失败已经弹过提示）。
Future<bool> runWipeFlow(BuildContext context) async {
  // 1. 二次确认 —— 说清「会失去什么」和「退路在哪」
  final ok = await showAppConfirm(
    context,
    title: '清空全部数据？',
    message: '所有账目、账户、分类、目标都会被删除，恢复成刚装好的样子。\n\n'
        '清空前会自动存一份快照，后悔了可以从侧拉栏的「数据安全」里找回来。',
    confirmLabel: '确认清空',
    danger: true,
  );
  if (!ok || !context.mounted) return false;

  // 2. 先留快照，再清。留不下就**不清**，和「从备份恢复」同一条策略。
  final String snapshot;
  try {
    snapshot = await BackupService.writeSnapshot(reason: 'wipe');
  } catch (e) {
    if (context.mounted) showToast(context, '没能生成快照，已取消：$e');
    return false;
  }

  // 3. 清空 + 重建 + 结果
  //
  // 失败必须说出来：异常在 1.4.1 里被悄悄吞掉，用户看到的就是「点了没反应、
  // 数据还在」。现在删除与重建在同一个事务里（见 `Db.wipeAllData`），抛异常
  // 等于整体回滚，所以可以明确说「数据未改动」。
  try {
    await Db.wipeAllData();
    await Store.i.reboot();
    if (!context.mounted) return true;
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
          Text('要找回来的话，去侧拉栏的「数据安全」用这份快照恢复。', style: T.caption),
        ],
      ),
    );
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, '清空失败，数据未改动：$e');
    return false;
  }
}
