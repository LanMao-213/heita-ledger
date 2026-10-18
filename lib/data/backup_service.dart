import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';
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
  static Future<String> writeSnapshot() async {
    final data = await dump();
    final dir = await getApplicationDocumentsDirectory();
    final sub = Directory(p.join(dir.path, 'backup'));
    if (!sub.existsSync()) sub.createSync(recursive: true);
    final file = File(p.join(sub.path, 'auto-${_stamp()}.json'));
    await file.writeAsString(jsonEncode(data));
    return file.path;
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

    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw BackupException('这个文件不是 JSON，可能选错了');
    }
    if (json is! Map) throw BackupException('备份文件内容不是 JSON 对象');
    return (json.map((k, v) => MapEntry(k.toString(), v)), files.first.name);
  }

  /// 校验并恢复。返回每张表写入的行数。
  ///
  /// 调用方务必先弹二次确认，并留一份 [writeSnapshot] —— 这是覆盖式写入。
  static Future<Map<String, int>> restore(Map<String, Object?> payload) async {
    final tables = _validate(payload);

    // 机器状态类的设置（应用名、实验开关）既不从备份恢复，也不能被清掉：
    // 先记下来，和回填放在同一个事务里补回去。
    final current = await Repo.listSettings();
    final keep = <String, String>{
      for (final e in current.entries)
        if (!_restoredSettingKeys.contains(e.key)) e.key: e.value,
    };

    return Repo.replaceTables(tables, keepSettings: keep);
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
