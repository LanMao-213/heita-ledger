import 'package:heita_ledger/data/db/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 数据层测试的统一夹具。
///
/// 三条纪律（架构设计 §7.4）：
/// 1. 一律用 **内存库**（`inMemoryDatabasePath`）—— 原版共用文件名在 Windows 上
///    删不掉文件，测试互相污染；
/// 2. 每个 test 前 `open`、后 `close`；
/// 3. 平台通道不碰（这里只跑 SQLite）。
Future<void> openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  Db.fileName = inMemoryDatabasePath;
  await Db.close();
  await Db.open();
}

/// 收尾：关库 + 清掉故障注入 + 把文件名恢复（避免影响同进程里别的测试文件）。
Future<void> closeTestDb() async {
  Db.wipeAllDataFaultForTest = null;
  await Db.close();
  Db.fileName = 'heita_ledger.db';
}
