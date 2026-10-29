import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'backup_compat.dart';
import 'backup/payload.dart';
import 'backup/plain_file.dart';
import 'backup/restore.dart';
import 'backup/sealed_file.dart';
import 'backup/snapshot.dart';

export 'backup/payload.dart';
export 'backup/plain_file.dart';
export 'backup/sealed_file.dart';
export 'backup/snapshot.dart';

/// 备份 / 恢复的**门面**：只转发，不实现。
///
/// 拆成五个文件的理由写在各自的文件头里，一句话版本：
///
/// | 文件 | 管什么 | 不许出现什么 |
/// |---|---|---|
/// | `backup/payload.dart` | 备份内容的结构、校验、摘要 | 口令、加密件 |
/// | `backup/restore.dart` | 覆盖式恢复（写库、跑迁移） | —— |
/// | `backup/plain_file.dart` | 明文容器（`.json`，就是 payload 本身） | 加密件 |
/// | `backup/sealed_file.dart` | 加密容器（`.heita`，AES-256-GCM） | —— |
/// | `backup/snapshot.dart` | 覆盖前的自动快照（永远明文） | 口令、加密件 |
///
/// 拆的目的不是「文件小一点」，而是让「快照永远是明文、只有用户主动导出才加密」
/// 这条口径在 **import 图上**成立：`snapshot.dart` 根本没有能力调用加密代码，
/// `payload.dart` 根本拿不到口令。靠调用方自觉的口径，加第三个入口时就破了。
abstract final class BackupService {
  // ---------------------------------------------------------------- 内容层

  /// 备份格式标识（payload 顶层 `format` 字段）。
  static const format = BackupPayload.format;

  /// payload 的结构版本。**与「是否加密」无关** —— 加密是容器的事。
  static const formatVersion = BackupPayload.formatVersion;

  /// 生成备份内容（不含文件 IO，测试直接用这个）
  static Future<Map<String, Object?>> dump() => BackupPayload.dump();

  /// 恢复前的摘要，给确认弹窗用。
  static BackupSummary summarize(Map<String, Object?> payload) =>
      BackupPayload.summarize(payload);

  /// 校验并恢复。返回每张表写入的行数。
  ///
  /// 调用方务必先弹二次确认，并留一份 [writeSnapshot] —— 这是覆盖式写入。
  static Future<Map<String, int>> restore(
    Map<String, Object?> payload, {
    ConformReport? report,
  }) => restoreBackup(payload, report: report);

  // ---------------------------------------------------------------- 明文容器

  /// 明文导出：写临时文件并返回路径（配合 [share] 发出去）。
  static Future<String> writeToTempFile() async {
    final data = await BackupPayload.dump();
    return PlainBackupFile.writeToTempFile(data);
  }

  /// 读一份明文文件（快照 / 用户挑的 `.json`）。
  static Future<Map<String, Object?>> readFile(String path) =>
      PlainBackupFile.readFile(path);

  /// 让用户挑一个文件，返回 `(原始内容, 文件名)`；取消返回 null。
  static Future<(String, String)?> pickText() => PlainBackupFile.pickText();

  /// 让用户挑一个备份文件并解成 payload。
  ///
  /// 明文直接解；加密的**这份摘要会失败**（没有口令），所以界面要走
  /// [pickText] + [decodeAny] + 输口令那条路。[password] 非空时两种都能解。
  static Future<(Map<String, Object?>, String)?> pickFile({
    String? password,
  }) async {
    final picked = await PlainBackupFile.pickText();
    if (picked == null) return null;
    final payload = await SealedBackupFile.decodeAny(
      picked.$1,
      password: password,
    );
    return (payload, picked.$2);
  }

  // ---------------------------------------------------------------- 加密容器

  /// 加密导出：写一份 `.heita` 到临时目录并返回路径。
  ///
  /// [password] 不落盘、不进日志、不留存 —— 忘了就打不开。
  static Future<String> writeSealedToTempFile({
    required String password,
    int? iterations,
  }) async {
    final data = await BackupPayload.dump();
    final text = await SealedBackupFile.seal(
      data,
      password: password,
      iterations: iterations ?? kDefaultKdfIterations,
    );
    return PlainBackupFile.writeTempFile(
      '黑塔消费日记-加密备份-'
      '${PlainBackupFile.stampOf(DateTime.now())}.${SealedBackupFile.extension}',
      text,
    );
  }

  /// 这份文件内容是不是加密备份（只看 `container`，不看扩展名）。
  static bool looksSealed(String text) => SealedBackupFile.looksSealed(text);

  /// 明文 / 加密都解成 payload。
  static Future<Map<String, Object?>> decodeAny(
    String text, {
    String? password,
  }) => SealedBackupFile.decodeAny(text, password: password);

  // ---------------------------------------------------------------- 快照

  /// 覆盖前的自动快照（永远明文，签名里没有口令）。
  static Future<String> writeSnapshot({String? reason}) =>
      SnapshotStore.writeSnapshot(reason: reason);

  /// 现有快照，按时间倒序。
  static Future<List<SnapshotInfo>> listSnapshots() =>
      SnapshotStore.listSnapshots();

  /// 删掉超量 / 过期的快照。
  static Future<int> pruneSnapshots({
    int keep = 3,
    Duration maxAge = const Duration(days: 7),
  }) => SnapshotStore.pruneSnapshots(keep: keep, maxAge: maxAge);

  /// 删掉一份快照。
  static Future<void> deleteSnapshot(String path) =>
      SnapshotStore.deleteSnapshot(path);

  /// 快照目录的测试注入点（单测没有 path_provider 平台通道）。
  static Future<Directory> Function()? get snapshotDirOverride =>
      SnapshotStore.snapshotDirOverride;

  static set snapshotDirOverride(Future<Directory> Function()? fn) =>
      SnapshotStore.snapshotDirOverride = fn;

  // ---------------------------------------------------------------- 分享

  /// 系统分享面板。**这是数据离开设备的唯一出口**，所以文案要说清是什么文件。
  static Future<void> share(String path) async {
    final sealed = path.endsWith('.${SealedBackupFile.extension}');
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            path,
            mimeType: sealed ? 'application/octet-stream' : 'application/json',
          ),
        ],
        text: sealed ? '黑塔消费日记 · 加密备份' : '黑塔消费日记 · 全量备份',
      ),
    );
  }
}
