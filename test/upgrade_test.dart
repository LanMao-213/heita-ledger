// 分类种子与升级迁移的自检。
//
// 这里钉的是「装到老手机上才会出事、本机怎么点都正常」的事：
// 1) v3 补进来的「提成」在 v6 要降级成「奖金」的子分类 —— 老用户的一级
//    列表里不该再多出一个和奖金同质的位置；
// 2) 降级不能重复：用户可能早就自建过一个叫「提成」的分类，
//    重复会在筛选和统计里各算一半，界面上两个同名项很难看出问题；
// 3) 老账本原本没有支出分类时，升级要能补齐整套支出两级结构。
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

/// 一级收入分类名（不含子分类）
Future<List<String>> _topIncomeNames() async {
  final db = await Db.open();
  final rows = await db.query(
    'category',
    columns: ['name'],
    where: "type = 'income' AND parent_id IS NULL",
    orderBy: 'sort_order, id',
  );
  return rows.map((r) => r['name'] as String).toList();
}

/// 某个一级分类下的子分类名
Future<List<String>> _subNames(String parent, {String type = 'income'}) async {
  final db = await Db.open();
  final rows = await db.rawQuery(
    'SELECT c.name AS name FROM category c '
    'JOIN category p ON p.id = c.parent_id '
    'WHERE c.type = ? AND p.name = ? AND p.parent_id IS NULL '
    'ORDER BY c.sort_order, c.id',
    [type, parent],
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

  test('全新安装：收入 6 个一级，提成收进奖金', () async {
    final tops = await _topIncomeNames();
    expect(tops, ['工资', '奖金', '兼职', '理财', '红包', '其他']);
    expect(await _subNames('奖金'), contains('提成'));
    expect(tops, isNot(contains('提成')), reason: '提成不该再占一个一级位置');
  });

  test('老库升级：老的一级「提成」降级成奖金子分类', () async {
    await _makeV2Db();
    final tops = await _topIncomeNames();
    expect(tops, ['工资', '奖金', '兼职', '理财', '红包', '其他']);
    expect(await _subNames('奖金'), contains('提成'));
  });

  test('老库已有自建的「提成」：降级后只有一个', () async {
    // 用户早就在最后自己加过一个「提成」
    await _makeV2Db(extra: [('提成', 'bonus', 6)]);
    final tops = await _topIncomeNames();
    final bonusSubs = await _subNames('奖金');

    expect(bonusSubs.where((n) => n == '提成').length, 1, reason: '出现了两个「提成」');
    expect(tops, isNot(contains('提成')));
  });

  test('老账本没有支出分类：升级后补齐 9 个一级与子分类', () async {
    await _makeV2Db();
    final db = await Db.open();
    final rows = await db.query(
      'category',
      columns: ['name'],
      where: "type = 'expense' AND parent_id IS NULL",
      orderBy: 'sort_order, id',
    );
    final tops = rows.map((r) => r['name'] as String).toList();
    expect(tops, ['餐饮', '出行', '居家', '购物', '健康', '娱乐', '人情', '成长', '其他']);
    expect(await _subNames('居家', type: 'expense'), contains('话费网费'));
  });

  test('从老库升上来会置位「该提示一次」，全新安装不会', () async {
    // 全新库：onCreate 不走迁移分支
    Db.upgradedToTwoLevel = false;
    await Db.open();
    expect(Db.upgradedToTwoLevel, isFalse);

    // 老库：onUpgrade 里 oldVersion < 6 才会置位
    await Db.close();
    await _makeV2Db();
    Db.upgradedToTwoLevel = false;
    await Db.open();
    expect(Db.upgradedToTwoLevel, isTrue);
  });
}
