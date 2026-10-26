part of '../repo.dart';

// ---------------------------------------------------------------------------
// 备份与恢复：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  /// 把 10 张表整个读出来（备份用）。行是原始 map，交给上层序列化。
  ///
  /// 老备份（v6 及以前）里没有 `debt` 这一项，恢复时按空表处理 ——
  /// 借贷是 v7 才有的，旧账本本来就没有往来。
Future<Map<String, List<Map<String, Object?>>>> _repoDumpTables() async {
  final db = await Db.open();
  final out = <String, List<Map<String, Object?>>>{};
  for (final t in Repo.backupTables) {
    out[t] = await db.query(t);
  }
  return out;
}

  /// 整库覆盖式回填，返回每张表写入的行数。
  ///
  /// **必须在事务里**：中途任何一张表失败都要整体回滚，
  /// 否则会留下「记账记录已经清了、分类还没回来」的半截库。
  ///
  /// [keepSettings] 是不跟着备份走、但也不该被清掉的设置项
  /// （应用名、实验开关这类「这台机器的状态」），在同一个事务里补回去。
  ///
  /// [report] 可选：把「旧字段被忽略 / 换名 / 类型纠正」记进这份账本，
  /// 界面据此告诉用户「这份备份是哪一年的、有些字段没带过来」。
  /// 不传也能正常恢复 —— 兼容动作照样生效，只是没人记录。
Future<Map<String, int>> _repoReplaceTables(
  Map<String, List<Map<String, Object?>>> data, {
  Map<String, String> keepSettings = const {},
  ConformReport? report,
}) async {
  final db = await Db.open();
  final counts = <String, int>{};
  final ledger = report ?? ConformReport();
  await db.transaction((txn) async {
    for (final t in Repo.backupTables.reversed) {
      await txn.delete(t);
    }
    for (final t in Repo.backupTables) {
      final rows = <Map<String, Object?>>[...?data[t]];
      counts[t] = rows.length;
      if (t == 'setting' && keepSettings.isNotEmpty) {
        for (final e in keepSettings.entries) {
          rows.add({'k': e.key, 'v': e.value});
        }
      }
      // 现表的真实列结构：兼容判断以它为准，而不是靠一份会过期的硬编码清单
      final pragma = await txn.rawQuery('PRAGMA table_info(`$t`)');
      final columns = <String, BackupColumn>{
        for (final c in pragma)
          c['name'] as String: BackupColumn.fromPragma(c),
      };
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          t,
          conformRow(
            table: t,
            row: row,
            columns: columns,
            report: ledger,
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  });
  // 旧备份（v3 及更早）里没有 period_start，回填一次即可；新备份自带，等于空跑
  await _repoBackfillMissingPeriods();
  return counts;
}
