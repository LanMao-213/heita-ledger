import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../design/tokens.dart';
import 'busy_dialog.dart';
import 'common.dart';
import 'menu.dart';
import 'password_sheet.dart';

// ---------------------------------------------------------------------------
// 导出 / 挑选备份：两个页面共用的四条流程
// ---------------------------------------------------------------------------
//
// 「我的」页和「数据安全」页都有导出入口，走的是同一套动作。复制两份的代价
// 不是多写几十行，而是**文案会分叉**：加密导出旁边那句「忘了打不开」漏在
// 某一个入口里，用户就只在一个地方被骗。所以四条流程只在这里写一遍。
//
// 加密与明文**是并列的两个动作**，不是一个动作的两个选项：
// - 明文：给「只存在自己电脑里」的场景，谁拿到谁能读；
// - 加密：给「要发给别人 / 传到网盘」的场景，口令在文件之外。
//
// 刻意**不做**「加密导出的同时再给一份明文」：那会让加密变成摆设 —— 一份
// 明文躺在同一个目录里，加密那份就没有任何意义了。

/// 明文导出：确认风险 → 写文件 → 分享。
///
/// 确认弹窗不是形式主义：导出口子是**唯一**会把整本账变成「一个可以随手转发
/// 的文件」的地方，而系统分享面板一打开，文件就出去了。
Future<void> runPlainExportFlow(BuildContext context) async {
  final ok = await showAppConfirm(
    context,
    title: '导出明文备份？',
    message: '文件是明文 JSON，拿到它的人能读出全部账目、备注和账户余额。\n\n'
        '请只发给自己（存本地、发自己邮箱）。要发给别人，用「加密导出」。',
    cancelLabel: '取消',
    confirmLabel: '导出明文',
  );
  if (!ok || !context.mounted) return;

  try {
    final path = await BackupService.writeToTempFile();
    if (!context.mounted) return;
    await BackupService.share(path);
  } catch (e) {
    if (context.mounted) showToast(context, '导出失败：$e');
  }
}

/// 加密导出：设口令 → 写 `.heita` → 分享。
///
/// 口令**不进日志、不留存**，用完即弃（见 `password_sheet.dart` 的红线）。
///
/// 加密这一步在 20k 笔的库上要 1.8 秒（低端机 3~5 秒），所以必须包一层阻塞
/// 进度 —— 界面在这段时间里一动不动的话，用户会再点一次或以为崩了。
Future<void> runSealedExportFlow(BuildContext context) async {
  final password = await showExportPasswordSheet(context);
  if (password == null || !context.mounted) return;

  try {
    final path = await runWithBusy(
      context,
      message: '正在加密备份…（约几秒，请不要退出）',
      task: () => BackupService.writeSealedToTempFile(password: password),
    );
    if (!context.mounted) return;
    await BackupService.share(path);
  } on BackupException catch (e) {
    if (context.mounted) showToast(context, '加密导出失败：${e.message}');
  } catch (e) {
    if (context.mounted) showToast(context, '加密导出失败：$e');
  }
}

/// 用户挑一份备份并解成 payload；取消返回 null。
///
/// 明文直接解；加密的要口令，**输错了允许再试**（最多 3 次）—— 用户打错一个
/// 字母就要重新去文件管理器挑一遍文件，那才是真的劝退。
///
/// 注意「打不开」的两种可能（口令不对 / 文件损坏）在密码学上不可区分，
/// 所以提示文案必须同时说这两件事，不能只说「口令错误」。
Future<({Map<String, Object?> payload, BackupSummary summary, String name})?>
pickBackupFlow(BuildContext context) async {
  final picked = await BackupService.pickText();
  if (picked == null) return null;
  final (text, name) = picked;
  final sealed = BackupService.looksSealed(text);

  String? password;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (sealed) {
      // 每次重试都重新确认 context 还活着：上一轮 await 期间用户可能已经退出去
      if (!context.mounted) return null;
      password = await showUnlockPasswordSheet(context, fileName: name);
      if (password == null || !context.mounted) return null;
    }
    try {
      if (!context.mounted) return null;
      // 解密要派一次密钥（210000 次 PBKDF2，约 1.2s），低端机更久。
      // 明文那一路不解密，就不必弹窗 —— 只有 sealed 才包。
      final payload = sealed
          ? await runWithBusy(
              context,
              message: '正在解密…（约几秒，请不要退出）',
              task: () =>
                  BackupService.decodeAny(text, password: password),
            )
          : await BackupService.decodeAny(text);
      if (!context.mounted) return null;
      return (payload: payload, summary: BackupService.summarize(payload), name: name);
    } on BackupSealedException catch (e) {
      // 头部坏 / 版本过新：再试一次也是同一个结果，直接抛给调用方去弹提示
      if (e.kind != SealedFailureKind.wrongPasswordOrCorrupt) rethrow;
      if (!context.mounted) rethrow;
      if (attempt >= 2) rethrow;
      await showAppNotice(
        context,
        title: '打不开',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.message, style: T.body2),
            const SizedBox(height: S.sm),
            Text('口令错和文件损坏在这里看起来是一样的，所以两种都可能。', style: T.caption),
          ],
        ),
        buttonLabel: '再试一次',
      );
      if (!context.mounted) return null;
    }
  }
  return null;
}
