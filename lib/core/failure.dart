/// 应用级失败类型与**中文文案映射**。
///
/// 为什么不用裸 `Exception`：整套代码的错误最终都要变成一句给用户看的中文。
/// 把「是什么错」和「怎么说」放在一起，就不会出现「启动失败页上写着一串
/// `SqliteException(11) database disk image is malformed`」这种原版事故
/// （M01-F07：一个白屏 + 异常文本，用户无路可走）。
library;

/// 所有可预期失败的基类。
sealed class AppFailure implements Exception {
  const AppFailure(this.detail);

  /// 给开发者看的细节（异常原文、SQL、路径）。**不进 toast**，只在日志与
  /// 「显示数据库路径」这类排查出口里出现。
  final String detail;

  /// 给用户看的一句话。必须能独立成立（用户看不到 detail）。
  String get userText;

  @override
  String toString() => '$runtimeType($detail)';
}

/// 数据库打不开 / 建表失败 / 迁移失败。
final class DbFailure extends AppFailure {
  const DbFailure(super.detail);

  @override
  String get userText => '账本文件打不开，可能是存储空间不足或文件损坏。';
}

/// 库版本比 App 新（用户装过更新的版本又降级回来）。
///
/// ★ 文案里必须明确「不要卸载重装」—— 卸载会清空应用私有目录，账目全丢。
final class DbDowngradeException extends AppFailure {
  const DbDowngradeException(this.dbVersion, this.appVersion)
    : super('db=$dbVersion app=$appVersion');

  final int dbVersion;
  final int appVersion;

  @override
  String get userText => '这份账本来自更新的版本（账本 $dbVersion / 应用 $appVersion）。'
      '账目都还在，请不要卸载重装；装回新版本即可继续使用。';
}

/// 备份/快照相关的失败（格式不对、版本过新、写不下）。
final class BackupFailure extends AppFailure {
  const BackupFailure(super.detail, {required this.userText});

  @override
  final String userText;
}

/// 导入相关的失败（旧版 JSON / Excel 列名对不上、行数据非法）。
final class ImportFailure extends AppFailure {
  const ImportFailure(super.detail, {required this.userText});

  @override
  final String userText;
}

/// 任意异常 → 一句给用户看的中文。
///
/// 唯一入口：页面层不许自己拼 `'$e'`（那就是把异常原文丢给用户）。
String userMessageOf(Object error) {
  if (error is AppFailure) return error.userText;
  return '操作没成功，请重试。';
}

/// 任意异常 → 给开发者看的细节串（日志 / 排查面板用）。
String detailOf(Object error) {
  if (error is AppFailure) return '${error.runtimeType}: ${error.detail}';
  return error.toString();
}
