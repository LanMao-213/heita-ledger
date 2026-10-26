part of '../repo.dart';

// ---------------------------------------------------------------------------
// 设置与账单日：`Repo` 的实现体
//
// 本文件里的函数全部是**库私有**（`part of` 共享 `repo.dart` 的私有作用域），
// 只有 `repo.dart` 的门面方法会调它们。对外签名、文档都在门面里，
// 这里只管 SQL 与事务边界 —— 想找某个方法的取舍说明，看门面那行注释。
// ---------------------------------------------------------------------------

  // ---------------------------------------------------------------- 通用设置
Future<String?> _repoGetSetting(String key) async {
  final db = await Db.open();
  final rows = await db.query('setting', where: 'k = ?', whereArgs: [key]);
  return rows.isEmpty ? null : rows.first['v'] as String;
}

Future<void> _repoSetSetting(String key, String value) async {
  final db = await Db.open();
  await db.insert('setting', {
    'k': key,
    'v': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

  /// 当前账单日，1–31；非法值一律回落到 1。
Future<int> _repoCycleStartDay() async {
  final raw = await _repoGetSetting(Repo.cycleStartDayKey);
  return (int.tryParse(raw ?? '') ?? 1).clamp(1, 31);
}

  // 旧格式备份的行改写（`budget.month` → `period_start` 等）已统一收进
  // `backup_compat.dart` 的 `conformRow`：那里有完整的兼容表、类型对齐与
  // 「未知列丢弃并记账」的规则。这里不再保留第二份实现 ——
  // 同一个规则有两个落点，改一边忘一边就是下一次「换机丢数据」。

  /// 读出全部设置项（键值对），恢复时用来保留机器状态
Future<Map<String, String>> _repoListSettings() async {
  final db = await Db.open();
  final rows = await db.query('setting');
  return {for (final r in rows) r['k'] as String: r['v'] as String};
}
