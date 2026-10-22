// 新建账本的分类种子自检。
//
// 1.4.x 里 `Repo.insertLedger` 自己抄了一份「名称 + 图标」的二元组常量，
// 没有 parent 概念 —— 新建出来的账本只有一级分类，用户记一笔时选不到
// 「正餐 / 公共交通」这种子分类。主账本却是两级的，这个差异只在新建账本上
// 复现，用老库怎么点都看不出来。
//
// 所以这里不写死「应该有 49 个子分类」就完事，而是**和主账本逐项比**：
// 新建账本必须和首启账本长得一模一样（名字、图标、sort_order、层级、类型），
// 差一个都算 bug。数字断言只作为兜底（种子表被误删时能直接看出少了什么）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/category_seed.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_ledger_seed.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<void> _freshDb() async {
  await Db.close();
  Db.fileName = _dbName;
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();
  await Db.open();
}

/// 把一个账本的分类摊平成「可逐行比对」的字符串列表。
///
/// 每行带上：类型、层级、父级名、名称、图标、sort_order。
/// 子分类紧跟在父级后面（`orderBy: type, sort_order, id` + 按 parent 归组），
/// 所以列表相等 = 结构、顺序、图标全部一致。
Future<List<String>> _tree(int ledgerId) async {
  final db = await Db.open();
  final rows = await db.query(
    'category',
    where: 'ledger_id = ?',
    whereArgs: [ledgerId],
    orderBy: 'type, sort_order, id',
  );
  final byId = {
    for (final r in rows) r['id'] as int: r,
  };
  final lines = <String>[];
  for (final type in ['expense', 'income']) {
    final tops = rows.where(
      (r) => r['type'] == type && r['parent_id'] == null,
    );
    for (final t in tops) {
      lines.add(
        '$type|一级|${t['name']}|${t['icon']}|${t['sort_order']}',
      );
      final subs = rows.where(
        (r) => r['type'] == type && r['parent_id'] == t['id'],
      );
      for (final s in subs) {
        lines.add(
          '$type|子|${t['name']}/${s['name']}|${s['icon']}'
          '|${s['sort_order']}|parent存在=${byId.containsKey(s['parent_id'])}',
        );
      }
    }
  }
  return lines;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  test('新建账本的两级分类与主账本逐项一致', () async {
    await _freshDb();
    final mainId = await Repo.currentLedgerId();
    final newId = await Repo.insertLedger(
      const Ledger(id: 0, name: '旅行账本', sortOrder: 1),
    );
    expect(newId, isNot(mainId));

    final mainTree = await _tree(mainId);
    final newTree = await _tree(newId);

    // 先钉住主账本的实际规模：支出 9 个一级 / 49 个子，收入 6 个一级 / 24 个子
    int count(String type, String level) => mainTree
        .where((l) => l.startsWith('$type|$level|'))
        .length;
    expect(count('expense', '一级'), 9, reason: '支出应是一级 9 个');
    expect(count('expense', '子'), 49, reason: '支出应是子分类 49 个');
    expect(count('income', '一级'), 6, reason: '收入应是一级 6 个');
    expect(count('income', '子'), 24, reason: '收入应是子分类 24 个');

    // 逐项相等：这行不等的话，失败信息里能直接看出是哪个分类缺了/错了
    expect(newTree, mainTree, reason: '新建账本必须和主账本长得一模一样');

    // 兜底：种子表里的每个一级/子分类都真的落库了（防止两边同时错）
    final flat = newTree.join('\n');
    for (final cat in kExpenseSeed) {
      expect(flat, contains('|${cat.name}|${cat.icon}|'));
      for (final sub in cat.subs) {
        expect(
          flat,
          contains('|${cat.name}/${sub.name}|${sub.icon}|'),
          reason: '缺了子分类「${cat.name}/${sub.name}」',
        );
      }
    }
    for (final cat in kIncomeSeed) {
      for (final sub in cat.subs) {
        expect(
          flat,
          contains('|${cat.name}/${sub.name}|${sub.icon}|'),
          reason: '缺了收入子分类「${cat.name}/${sub.name}」',
        );
      }
    }
  });

  test('子分类挂在同账本、同类型的一级分类下', () async {
    await _freshDb();
    final ledgerId = await Repo.insertLedger(
      const Ledger(id: 0, name: '旅行账本', sortOrder: 1),
    );
    final db = await Db.open();
    final rows = await db.query(
      'category',
      where: 'ledger_id = ?',
      whereArgs: [ledgerId],
    );
    final byId = {
      for (final r in rows) r['id'] as int: r,
    };
    final subs = rows.where((r) => r['parent_id'] != null).toList();
    expect(subs, isNotEmpty, reason: '没有子分类 = 又退回成一級了');

    for (final s in subs) {
      final parent = byId[s['parent_id'] as int];
      expect(parent, isNotNull, reason: '子分类「${s['name']}」的 parent_id 指空了');
      expect(
        parent!['ledger_id'],
        ledgerId,
        reason: '子分类「${s['name']}」挂到了别的账本的分类下',
      );
      expect(
        parent['type'],
        s['type'],
        reason: '子分类「${s['name']}」跨了类型（支出挂到收入下）',
      );
      expect(
        parent['parent_id'],
        isNull,
        reason: '「${s['name']}」的父级自己也是子分类 —— 只允许两级',
      );
      expect(s['ledger_id'], ledgerId);
    }

    // 「正餐」「公共交通」这些用户天天点的子分类必须真的可选
    final names = rows.map((r) => r['name']).toList();
    expect(names, containsAll(['餐饮', '正餐', '出行', '公共交通']));
  });
}
