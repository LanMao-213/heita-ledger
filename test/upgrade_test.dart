// 分类种子与升级迁移的自检。
//
// 这里钉的是两件「装到老手机上才会出事、本机怎么点都正常」的事：
// 1) 老库升级要能补上后加的「提成」分类，否则老用户永远没有这一类；
// 2) 补的时候不能重复插 —— 用户可能早就自建过一个叫「提成」的分类，
//    插重了会在筛选和统计里各算一半，而且界面上两个同名项很难看出问题。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_upgrade.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// v2 时代的收入分类（没有「提成」）
const _v2Income = [
  ('工资', 'salary', 0),
  ('奖金', 'bonus', 1),
  ('兼职', 'parttime', 2),
  ('理财', 'invest', 3),
  ('红包', 'redpacket', 4),
  ('其他', 'more', 5),
];

/// 造一个 v2 的老库。只建 onUpgrade 会碰到的两张表。
Future<void> _makeV2Db({List<(String, String, int)> extra = const []}) async {
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();

  final db = await databaseFactory.openDatabase(
    await _dbPath(),
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE ledger (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT NOT NULL,
            icon        TEXT NOT NULL DEFAULT 'book',
            sort_order  INTEGER NOT NULL DEFAULT 0,
            archived    INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute('''
          CREATE TABLE category (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            ledger_id   INTEGER NOT NULL,
            type        TEXT    NOT NULL,
            name        TEXT    NOT NULL,
            icon        TEXT    NOT NULL DEFAULT 'more',
            parent_id   INTEGER,
            sort_order  INTEGER NOT NULL DEFAULT 0,
            archived    INTEGER NOT NULL DEFAULT 0
          )''');
        await db.insert('ledger', {
          'name': '老账本',
          'icon': 'book',
          'sort_order': 0,
          'archived': 0,
          'created_at': '',
        });
        for (final (name, icon, order) in [..._v2Income, ...extra]) {
          await db.insert('category', {
            'ledger_id': 1,
            'type': 'income',
            'name': name,
            'icon': icon,
            'sort_order': order,
            'archived': 0,
          });
        }
      },
    ),
  );
  await db.close();
}

Future<List<String>> _incomeNames() async {
  final db = await Db.open();
  final rows = await db.query(
    'category',
    columns: ['name'],
    where: "type = 'income'",
    orderBy: 'sort_order, id',
  );
  return rows.map((r) => r['name'] as String).toList();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 与其它测试文件各用各的库文件，避免并行时互相干扰
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  test('全新安装：收入 7 类，提成紧跟在奖金后面', () async {
    final names = await _incomeNames();
    expect(names, ['工资', '奖金', '提成', '兼职', '理财', '红包', '其他']);
  });

  test('老库升级：补上提成，且「其他」仍在最后', () async {
    await _makeV2Db();
    final names = await _incomeNames();
    expect(names, ['工资', '奖金', '提成', '兼职', '理财', '红包', '其他']);
  });

  test('老库已有自建的「提成」：不重复插入', () async {
    // 用户早就在最后自己加过一个「提成」
    await _makeV2Db(extra: [('提成', 'bonus', 6)]);
    final names = await _incomeNames();

    expect(names.where((n) => n == '提成').length, 1, reason: '出现了两个「提成」');
    expect(names, ['工资', '奖金', '兼职', '理财', '红包', '其他', '提成'],
        reason: '用户自建的那条应保持原位，不能被新种子顶掉');
  });
}
