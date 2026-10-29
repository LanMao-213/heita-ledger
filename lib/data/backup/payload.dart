import '../db.dart';
import '../repo.dart';

// ---------------------------------------------------------------------------
// 备份 payload：结构、校验、摘要
// ---------------------------------------------------------------------------
//
// ## 这个文件为什么存在
//
// 「数据必须能带走」是这个应用的第三条红线。带走的路径有两条：
//
//   1. 自动快照（`snapshot.dart`）—— 覆盖式写入之前留的退路，永远明文，
//      用户看不见也不该需要口令；
//   2. 用户主动导出（明文 `.json` 或加密 `.heita`）—— 会给别人看的文件。
//
// 两者的内容**完全一样**，区别只在容器。所以内容这一层单独一个文件：
// 它不认识文件、不认识口令、不认识加密 —— 只认识「一张表一行」。
//
// ## 刻意不许出现的东西（`architecture_test` 有源码探针守着）
//
//   - 不许出现 `password`：payload 层拿不到口令，就没有「顺手加密一下」的
//     机会。加密只发生在 `sealed_file.dart`，只由用户点「加密导出」触发。
//   - 不许 import `sealed_file.dart`：快照永远明文，这个方向在 import 图上
//     就被堵死了，不靠调用方自觉。
//
// ## 三个版本号，各管各的
//
//   - `schemaVersion` —— 数据库结构（现在是 10）。恢复时要按它决定是否走迁移。
//   - `formatVersion` —— **payload 的结构**（现在是 1）。加表、改字段名才动它。
//   - `containerVersion` —— **容器封装**（明文 1 / 加密 1，见 `plain_file.dart`
//     与 `sealed_file.dart`）。
//
// ★ 禁止用 `formatVersion` 表达「这份备份加没加密」：加密是**容器**的事，
//   同一个 payload 既可以明文写在 `.json` 里，也可以封进 `.heita`。把它写进
//   payload 就等于承认「加密过的那份数据本身不一样」，而那是假的 —— 解出来
//   还是同一张表。

/// 备份/恢复过程中的用户可读错误。
///
/// 全部是「文件不对」这类可预期的问题，界面直接把 `message` 弹出来即可，
/// 不要显示堆栈。
class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
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

/// 恢复时只跟着走的设置项。
///
/// `app_name` / `schema_ready` 是种子标记，`ui.*` 是实验开关 —— 这些属于
/// 「这台机器现在的状态」，不该被旧备份覆盖回去。只有「当前用哪个账本」
/// 属于用户数据。
const kRestoredSettingKeys = {'current_ledger_id'};

/// 备份 payload 的读写（不含文件、不含容器）。
abstract final class BackupPayload {
  static const format = 'heita-ledger-backup';
  static const formatVersion = 1;

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

  /// 恢复前的摘要，给确认弹窗用。
  ///
  /// 故意只读 `tables` 的长度，不做任何校验 —— 摘要要能在「文件可能有问题」
  /// 的时候照样给出，否则确认弹窗就没东西可显示。
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

  /// 校验 payload 并取出「表名 → 行」。
  ///
  /// 这里挡的是**整份文件不该被恢复**的那几种情况：不是本应用的备份、格式
  /// 比当前应用新、表结构比当前库新、一条记录都没有。挡下来的目的只有一个：
  /// 别让它去覆盖用户现有的数据。
  static Map<String, List<Map<String, Object?>>> validate(
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
        if (t == 'setting' && !kRestoredSettingKeys.contains(map['k'])) {
          continue; // 见 kRestoredSettingKeys 的说明
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
}
