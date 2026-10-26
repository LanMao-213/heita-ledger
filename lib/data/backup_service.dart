import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_compat.dart';
import 'db.dart';
import 'integrity.dart';
import 'repo.dart';

/// 备份/恢复过程中的用户可读错误。
///
/// 全部是「文件不对」这类可预期的问题，界面直接把 message 弹出来即可，
/// 不要显示堆栈。
class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 全量备份 / 覆盖式恢复。
///
/// 为什么需要它：Excel 导出只含 `txn` 一张表，预算、目标、模板、周期账单、
/// 账户余额、分类都不在里面。卸载重装 = 这些全丢。
///
/// 文件格式（JSON）：
/// ```json
/// {
///   "format": "heita-ledger-backup",
///   "formatVersion": 1,
///   "schemaVersion": 3,
///   "exportedAt": "2026-10-18T13:30:00.000",
///   "tables": { "ledger": [...], "txn": [...], ... }
/// }
/// ```
abstract final class BackupService {
  static const format = 'heita-ledger-backup';
  static const formatVersion = 1;

  /// 恢复时只跟着走的设置项。
  ///
  /// `app_name` / `schema_ready` 是种子标记，`ui.*` 是实验开关 —— 这些属于
  /// 「这台机器现在的状态」，不该被旧备份覆盖回去。只有「当前用哪个账本」
  /// 属于用户数据。
  static const _restoredSettingKeys = {'current_ledger_id'};

  static const _encoder = JsonEncoder.withIndent('  ');

  // ------------------------------------------------------------------ 导出

  /// 生成备份内容（不含文件 IO，测试直接用这个）
  static Future<Map<String, Object?>> dump() async {
    final tables = await Repo.dumpTables();
    return {
      'format': format,
      'formatVersion': formatVersion,
      'schemaVersion': Db.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    };
  }

  /// 写到临时目录并返回路径（配合 [share] 发出去）
  static Future<String> writeToTempFile() async {
    final data = await dump();
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '黑塔消费日记-备份-${_stamp()}.json'));
    await file.writeAsString(_encoder.convert(data));
    return file.path;
  }

  /// 覆盖前的自动快照，写到应用文档目录。
  ///
  /// 和 [writeToTempFile] 的区别：这个不分享、不打扰用户，纯粹是「万一恢复
  /// 弄坏了还能捞回来」的兜底。临时目录会被系统清理，所以放文档目录。
  ///
  /// [reason] 会进文件名（`auto-wipe-20261020-172105.json`），「数据安全」页
  /// 用它说明这份快照是**哪个动作**留下的。传 null 就是普通自动快照。
  static Future<String> writeSnapshot({String? reason}) async {
    final data = await dump();
    final dir = await _snapshotDir();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final tag = reason == null ? 'auto' : 'auto-$reason';
    final file = File(p.join(dir.path, '$tag-${_stamp()}.json'));
    await file.writeAsString(jsonEncode(data));
    // 快照是兜底，不是档案库：写完顺手把超量 / 过期的删掉。
    // 轮转失败不影响「这次快照已经留在盘上」这个事实，所以不让它抛给调用方。
    await pruneSnapshots();
    return file.path;
  }

  /// 现有快照，按时间倒序。读不出来的文件也会列出来（`readable == false`），
  /// 因为「有一份坏文件」本身就是要让用户看见的信息。
  static Future<List<SnapshotInfo>> listSnapshots() async {
    final dir = await _snapshotDir();
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
        summary = summarize(_decode(await entity.readAsString()));
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

  /// 读一份快照 / 备份文件成 payload。内容不对会抛 [BackupException]。
  static Future<Map<String, Object?>> readFile(String path) async {
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (e) {
      throw BackupException('读不了这个文件：${e.message}');
    }
    return _decode(text);
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

  static Future<void> share(String path) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/json')],
        text: '黑塔消费日记 · 全量备份',
      ),
    );
  }

  // ------------------------------------------------------------------ 导入

  /// 让用户挑一个备份文件。返回 `(内容, 文件名)`，取消返回 null。
  ///
  /// 用 `FileType.any` 而不是限定 json：Android 上不少文件管理器会把
  /// `.json` 识别成 `application/octet-stream`，限定类型反而选不到。
  static Future<(Map<String, Object?>, String)?> pickFile() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    final path = files.first.path;
    if (path == null) return null;

    final String text;
    try {
      text = await File(path).readAsString();
    } catch (e) {
      throw BackupException('读不了这个文件：$e');
    }
    return (_decode(text), files.first.name);
  }

  /// 校验并恢复。返回每张表写入的行数。
  ///
  /// 调用方务必先弹二次确认，并留一份 [writeSnapshot] —— 这是覆盖式写入。
  ///
  /// [report] 可选：记录「旧字段被忽略 / 换名 / 类型纠正」。老备份里有一列
  /// 现表已经没有时，以前会整次失败（`no such column`），现在只丢那一列并记账。
  static Future<Map<String, int>> restore(
    Map<String, Object?> payload, {
    ConformReport? report,
  }) async {
    final tables = _validate(payload);

    // 机器状态类的设置（应用名、实验开关）既不从备份恢复，也不能被清掉：
    // 先记下来，和回填放在同一个事务里补回去。
    final current = await Repo.listSettings();
    final keep = <String, String>{
      for (final e in current.entries)
        if (!_restoredSettingKeys.contains(e.key)) e.key: e.value,
    };

    final Map<String, int> counts;
    try {
      counts = await Repo.replaceTables(
        tables,
        keepSettings: keep,
        report: report,
      );
    } on BackupFieldException catch (e) {
      // 事务已回滚，数据未被改动 —— 把技术错误翻成用户能读懂的一句话
      throw BackupException(e.message);
    }

    // 旧备份里的分类是扁平的一套（交通 / 通讯 / 医疗…）。灌进新库之后，
    // 走一遍升级迁移把它们并进两级体系 —— 否则恢复出来的账本在分类管理页里
    // 是「9 个一级、0 个子分类」，而且再也不会被自动修正。
    final sv = payload['schemaVersion'];
    if (sv is int && sv < Db.schemaVersion) {
      await Db.upgradeRestoredData();
    }

    // v7 及以前的备份里没有 `opening_cents`，灌进新库后全是默认值 0，
    // 「余额 = 期初 + 流水」会当场不成立 —— 但账本其实是对的：老库里的
    // 「余额」本来就是用户手填的绝对值。这里把它认成新基准，
    // 恢复完立刻自洽，不然第一次体检会报一堆假问题。
    await Integrity.adoptCurrentBalances();

    return counts;
  }

  /// 恢复前的摘要，给确认弹窗用。
  static BackupSummary summarize(Map<String, Object?> payload) {
    final tables = payload['tables'];
    List<Object?> rows(String t) {
      if (tables is! Map) return const [];
      final v = tables[t];
      return v is List ? v : const [];
    }

    return BackupSummary(
      txns: rows('txn').length,
      accounts: rows('account').length,
      categories: rows('category').length,
      ledgers: rows('ledger').length,
      exportedAt: payload['exportedAt'] is String
          ? payload['exportedAt'] as String
          : null,
      schemaVersion: payload['schemaVersion'] is int
          ? payload['schemaVersion'] as int
          : null,
    );
  }

  // ------------------------------------------------------------------ 内部

  static Map<String, List<Map<String, Object?>>> _validate(
    Map<String, Object?> payload,
  ) {
    if (payload['format'] != format) {
      throw BackupException('这不是「黑塔消费日记」的备份文件');
    }

    final fv = payload['formatVersion'];
    if (fv is! int) throw BackupException('备份文件缺少格式版本');
    if (fv > formatVersion) {
      throw BackupException('备份格式过新（v$fv），请先把应用升级到新版本');
    }

    final sv = payload['schemaVersion'];
    if (sv is! int) throw BackupException('备份文件缺少数据版本');
    if (sv > Db.schemaVersion) {
      throw BackupException(
        '备份来自更新的版本（数据版本 $sv），当前应用只到 ${Db.schemaVersion}，'
        '请先升级应用再恢复',
      );
    }

    final rawTables = payload['tables'];
    if (rawTables is! Map) throw BackupException('备份文件里没有数据表');

    final out = <String, List<Map<String, Object?>>>{};
    for (final t in Repo.backupTables) {
      final raw = rawTables[t];
      if (raw != null && raw is! List) {
        throw BackupException('表 `$t` 的内容格式不对');
      }
      final rows = <Map<String, Object?>>[];
      for (final row in (raw as List?) ?? const <Object?>[]) {
        if (row is! Map) throw BackupException('表 `$t` 里有格式不对的记录');
        final map = row.map((k, v) => MapEntry(k.toString(), v));
        if (t == 'setting' && !_restoredSettingKeys.contains(map['k'])) {
          continue; // 见 _restoredSettingKeys 的说明
        }
        rows.add(map);
      }
      out[t] = rows;
    }

    // 一条记录都没有的备份，多半是空文件或选错了——不让它清空现有数据
    final total = out.values.fold<int>(0, (a, r) => a + r.length);
    if (total == 0) throw BackupException('备份文件是空的，没有可恢复的数据');

    return out;
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// `auto-<reason>-<yyyymmdd>-<hhmmss>.json`，reason 可省（老快照就是这种）。
  static final _snapshotName = RegExp(
    r'^auto-(?:([a-z]+)-)?(\d{8})-(\d{6})\.json$',
  );

  /// 快照目录。默认「文档目录/backup」。
  static Future<Directory> _snapshotDir() async {
    final override = snapshotDirOverride;
    if (override != null) return override();
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'backup'));
  }

  /// 快照目录的测试注入点 —— 和 [Db.fileName] 同一个用途：
  /// 单测里没有 path_provider 的平台通道，不能真去查文档目录。
  static Future<Directory> Function()? snapshotDirOverride;

  /// 文件内容 → payload。格式不对一律抛 [BackupException]（界面直接弹这句话）。
  static Map<String, Object?> _decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw BackupException('这个文件不是 JSON，可能选错了');
    }
    if (json is! Map) throw BackupException('备份文件内容不是 JSON 对象');
    return json.map((k, v) => MapEntry(k.toString(), v));
  }
}

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

/// 备份文件摘要（确认弹窗展示用）
class BackupSummary {
  const BackupSummary({
    required this.txns,
    required this.accounts,
    required this.categories,
    required this.ledgers,
    this.exportedAt,
    this.schemaVersion,
  });

  final int txns;
  final int accounts;
  final int categories;
  final int ledgers;
  final String? exportedAt;
  final int? schemaVersion;

  /// 「2026-10-18T13:30:00.000」→「2026-10-18 13:30」
  String get exportedLabel {
    final raw = exportedAt;
    if (raw == null || raw.length < 16) return '未知时间';
    return '${raw.substring(0, 10)} ${raw.substring(11, 16)}';
  }

  String get text =>
      '$ledgers 个账本 · $txns 笔记录 · $accounts 个账户 · $categories 个分类\n'
      '备份时间：$exportedLabel';
}
