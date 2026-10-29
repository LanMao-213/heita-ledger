import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'payload.dart';
import 'plain_file.dart';

// ---------------------------------------------------------------------------
// 自动快照：覆盖式写入之前的退路
// ---------------------------------------------------------------------------
//
// ## 为什么快照永远不加密
//
// 快照是**兜底**，不是档案。它存在的场景是「用户刚清空/刚恢复，现在后悔了」——
// 那个时刻他手上唯一确定的东西就是这台手机。如果快照要口令，那么：
//
//   - 用户在惊慌的时候还得先想起一个口令；
//   - 口令只能存在设备上（否则他又得记第二个口令），存在设备上就等于没加密；
//   - 忘了口令 = 兜底失效 = 这条退路比没有更糟（它让人以为有）。
//
// 所以就明文写在应用私有目录里 —— 那个目录别的应用读不到，卸载会一起清掉。
// 「要长期保存」这件事由用户主动导出承担，而那时他才需要选明文还是加密。
//
// ## 这条口径怎么保证
//
// **这个文件不 import `sealed_file.dart`**，`writeSnapshot` 的签名里也没有
// 口令参数。想给快照加密，必须先改 import 图 —— 那一步会被 `architecture_test`
// 的源码探针看见（`snapshot.dart` 里不许出现 `password` 与 `sealed_file`）。
// 靠约定维持的口径迟早会破，靠 import 图维持的不会。

/// 一份自动快照的描述，「数据安全」页列表用。
class SnapshotInfo {
  const SnapshotInfo({
    required this.path,
    required this.time,
    required this.reason,
    required this.summary,
    required this.sizeBytes,
  });

  final String path;
  final DateTime time;

  /// 产生这份快照的动作：`wipe` / `restore` / `manual`；null = 普通自动快照
  final String? reason;

  /// 读不出内容时为 null（文件损坏）
  final BackupSummary? summary;
  final int sizeBytes;

  bool get readable => summary != null;

  String get reasonLabel => switch (reason) {
    'wipe' => '清空前',
    'restore' => '恢复前',
    'manual' => '手动备份',
    _ => '自动快照',
  };

  /// `2026-10-20 17:21`
  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  /// 「12 笔记录 · 4 个账户」；坏掉的快照直接说明读不出来
  String get contentLabel {
    final s = summary;
    if (s == null) return '文件损坏，无法恢复';
    return '${s.txns} 笔记录 · ${s.accounts} 个账户 · ${s.categories} 个分类';
  }
}

/// 自动快照的读写与清理。
abstract final class SnapshotStore {
  /// `auto-<reason>-<yyyymmdd>-<hhmmss>.json`，reason 可省（老快照就是这种）。
  static final _snapshotName = RegExp(
    r'^auto-(?:([a-z]+)-)?(\d{8})-(\d{6})\.json$',
  );

  /// 快照目录的测试注入点 —— 和 `Db.fileName` 同一个用途：
  /// 单测里没有 path_provider 的平台通道，不能真去查文档目录。
  static Future<Directory> Function()? snapshotDirOverride;

  /// 覆盖前的自动快照，写到应用文档目录。
  ///
  /// 和「导出」的区别：这个不分享、不打扰用户，纯粹是「万一弄坏了还能捞回来」
  /// 的兜底。临时目录会被系统清理，所以放文档目录。
  ///
  /// [reason] 会进文件名（`auto-wipe-20261020-172105.json`），「数据安全」页
  /// 用它说明这份快照是**哪个动作**留下的。传 null 就是普通自动快照。
  ///
  /// ★ 签名里**没有口令**，也不该有：快照永远明文（理由见文件头）。
  static Future<String> writeSnapshot({String? reason}) async {
    final data = await BackupPayload.dump();
    final dir = await resolveDir();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final tag = reason == null ? 'auto' : 'auto-$reason';
    final file = File(
      p.join(dir.path, '$tag-${PlainBackupFile.stampOf(DateTime.now())}.json'),
    );
    // 快照用紧凑 JSON（不是导出那份带缩进的）：它进不了人手，省一半 IO
    await file.writeAsString(jsonEncode(data));
    // 快照是兜底，不是档案库：写完顺手把超量 / 过期的删掉。
    // 轮转失败不影响「这次快照已经留在盘上」这个事实，所以不让它抛给调用方。
    await pruneSnapshots();
    return file.path;
  }

  /// 现有快照，按时间倒序。读不出来的文件也会列出来（`readable == false`），
  /// 因为「有一份坏文件」本身就是要让用户看见的信息。
  static Future<List<SnapshotInfo>> listSnapshots() async {
    final dir = await resolveDir();
    if (!dir.existsSync()) return const [];

    final out = <SnapshotInfo>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final m = _snapshotName.firstMatch(name);
      if (m == null) continue; // 用户自己放进去的备份不归这里管

      DateTime time;
      try {
        final d = m.group(2)!;
        final t = m.group(3)!;
        time = DateTime(
          int.parse(d.substring(0, 4)),
          int.parse(d.substring(4, 6)),
          int.parse(d.substring(6, 8)),
          int.parse(t.substring(0, 2)),
          int.parse(t.substring(2, 4)),
          int.parse(t.substring(4, 6)),
        );
      } on FormatException {
        time = entity.statSync().modified;
      }

      BackupSummary? summary;
      try {
        summary = BackupPayload.summarize(
          PlainBackupFile.decode(await entity.readAsString()),
        );
      } on BackupException {
        summary = null; // 内容坏了：列出来但不能恢复
      } on FileSystemException {
        summary = null;
      }

      out.add(
        SnapshotInfo(
          path: entity.path,
          time: time,
          reason: m.group(1),
          summary: summary,
          sizeBytes: entity.lengthSync(),
        ),
      );
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// 删掉超过 [keep] 份、或早于 [maxAge] 的快照，返回删掉的数量。
  ///
  /// 只碰 `auto-*.json`：用户手动导出的备份可能在同一个目录旁边，绝不能动。
  /// 删单份失败只跳过（快照多留一份没有副作用，抛错反而会打断清空/恢复）。
  static Future<int> pruneSnapshots({
    int keep = 3,
    Duration maxAge = const Duration(days: 7),
  }) async {
    final items = await listSnapshots();
    final now = DateTime.now();
    var removed = 0;
    for (var i = 0; i < items.length; i++) {
      final s = items[i];
      if (i < keep && now.difference(s.time) <= maxAge) continue;
      try {
        final f = File(s.path);
        if (f.existsSync()) f.deleteSync();
        removed++;
      } on FileSystemException {
        continue;
      }
    }
    return removed;
  }

  /// 删掉一份快照（「数据安全」页手动清理用）。
  static Future<void> deleteSnapshot(String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    try {
      f.deleteSync();
    } on FileSystemException catch (e) {
      throw BackupException('删不掉：${e.message}');
    }
  }

  /// 快照目录。默认「文档目录/backup」。
  static Future<Directory> resolveDir() async {
    final override = snapshotDirOverride;
    if (override != null) return override();
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'backup'));
  }
}
