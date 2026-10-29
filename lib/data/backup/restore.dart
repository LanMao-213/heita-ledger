import '../backup_compat.dart';
import '../db.dart';
import '../integrity.dart';
import '../repo.dart';
import 'payload.dart';

/// 覆盖式恢复：**校验 → 一个事务里整库替换 → 认一次余额基准**。
///
/// 为什么不放在 `payload.dart`：那一层是纯数据（结构、校验、摘要），不写库。
/// 这个函数会写库、会跑迁移、会改余额基准 —— 是 IO，单独一个文件。
///
/// 调用方务必先弹二次确认，并留一份 `writeSnapshot` —— 这是覆盖式写入。
///
/// [report] 可选：记录「旧字段被忽略 / 换名 / 类型纠正」。老备份里有一列
/// 现表已经没有时，以前会整次失败（`no such column`），现在只丢那一列并记账。
Future<Map<String, int>> restoreBackup(
  Map<String, Object?> payload, {
  ConformReport? report,
}) async {
  final tables = BackupPayload.validate(payload);

  // 机器状态类的设置（应用名、实验开关）既不从备份恢复，也不能被清掉：
  // 先记下来，和回填放在同一个事务里补回去。
  final current = await Repo.listSettings();
  final keep = <String, String>{
    for (final e in current.entries)
      if (!kRestoredSettingKeys.contains(e.key)) e.key: e.value,
  };

  // 旧备份里的分类是扁平的一套（交通 / 通讯 / 医疗…）。灌进新库之后，
  // 走一遍升级迁移把它们并进两级体系 —— 否则恢复出来的账本在分类管理页里
  // 是「9 个一级、0 个子分类」，而且再也不会被自动修正。
  //
  // ★ 必须和「灌行」在**同一个事务里**（1.5.0 修正）。以前是恢复函数返回
  //   之后再单独调 `Db.upgradeRestoredData()`：那时灌行已经提交，迁移一旦
  //   中途失败，就是「账目进来了、分类只升了一半」，而调用方拿到异常后会对
  //   用户说「恢复失败，数据未改动」—— 那句话在当时是假的。现在交给
  //   `afterLoad`，在提交之前跑完，抛异常则整次覆盖一起回滚。
  final sv = payload['schemaVersion'];
  final needsUpgrade = sv is int && sv < Db.schemaVersion;

  final Map<String, int> counts;
  try {
    counts = await Repo.replaceTables(
      tables,
      keepSettings: keep,
      report: report,
      afterLoad: needsUpgrade
          ? (txn) => Db.migrateTwoLevelCategories(txn)
          : null,
    );
  } on BackupFieldException catch (e) {
    // 事务已回滚，数据未被改动 —— 把技术错误翻成用户能读懂的一句话
    throw BackupException(e.message);
  }

  // v7 及以前的备份里没有 `opening_cents`，灌进新库后全是默认值 0，
  // 「余额 = 期初 + 流水」会当场不成立 —— 但账本其实是对的：老库里的
  // 「余额」本来就是用户手填的绝对值。这里把它认成新基准，
  // 恢复完立刻自洽，不然第一次体检会报一堆假问题。
  await Integrity.adoptCurrentBalances();

  return counts;
}
