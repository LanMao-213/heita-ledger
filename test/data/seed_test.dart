import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/db/schema.dart';
import 'package:heita_ledger/data/db/seeds.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:sqflite/sqflite.dart';

import '../support/db_fixture.dart';

/// 分类种子：**数字必须被钉死**。
///
/// 原版活到 1.4.5 的那个洞就是「新建账本只灌了旧的扁平 10/6 分类，且没有任何
/// 测试钉住计数」。这一组测试就是那个洞的补丁（盘点 b-1 / c-5，不变量 I6 的种子侧）。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  test('支出 9 个一级 / 49 个子分类', () {
    expect(kExpenseSeed.length, 9);
    int subs = 0;
    for (final SeedCat cat in kExpenseSeed) {
      subs += cat.subs.length;
    }
    expect(subs, 49);
  });

  test('收入 6 个一级 / 24 个子分类', () {
    expect(kIncomeSeed.length, 6);
    int subs = 0;
    for (final SeedCat cat in kIncomeSeed) {
      subs += cat.subs.length;
    }
    expect(subs, 24);
  });

  test('一级分类名与顺序固定（改了就是改产品，必须同步改这条断言）', () {
    expect(
      kExpenseSeed.map((SeedCat c) => c.name).toList(),
      <String>['餐饮', '出行', '居家', '购物', '健康', '娱乐', '人情', '成长', '其他'],
    );
    expect(
      kIncomeSeed.map((SeedCat c) => c.name).toList(),
      <String>['工资', '奖金', '兼职', '理财', '红包', '其他'],
    );
    // 「通讯」不该出现在一级里（它是居家/话费网费）
    expect(
      kExpenseSeed.map((SeedCat c) => c.name),
      isNot(contains('通讯')),
    );
  });

  test('建库后库里的计数与种子一致：15 一级 + 73 子', () async {
    final Database db = await Db.database();
    final ledgerId = await Db.ensureCurrentLedgerId();

    final int tops = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.category} '
      'WHERE ledger_id = ? AND parent_id IS NULL',
      <Object?>[ledgerId],
    )).first['c']! as int;
    final int subs = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.category} '
      'WHERE ledger_id = ? AND parent_id IS NOT NULL',
      <Object?>[ledgerId],
    )).first['c']! as int;

    expect(tops, 15);
    expect(subs, 73);

    // 按类型再分一遍：支出 9/49、收入 6/24
    Future<int> countBy(String type, {required bool top}) async {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.category} WHERE ledger_id = ? AND type = ? '
        'AND parent_id IS ${top ? 'NULL' : 'NOT NULL'}',
        <Object?>[ledgerId, type],
      );
      return rows.first['c']! as int;
    }

    expect(await countBy('expense', top: true), 9);
    expect(await countBy('expense', top: false), 49);
    expect(await countBy('income', top: true), 6);
    expect(await countBy('income', top: false), 24);
  });

  test('I6（种子侧）：每个子分类的 parent_id 指向「同账本、同类型、且是一级」的分类', () async {
    final Database db = await Db.database();
    final List<Map<String, Object?>> subs = await db.rawQuery(
      'SELECT s.id, s.ledger_id, s.type, s.parent_id, p.id AS pid, '
      'p.parent_id AS pparent, p.ledger_id AS pledger, p.type AS ptype '
      'FROM ${Tables.category} s '
      'LEFT JOIN ${Tables.category} p ON p.id = s.parent_id '
      'WHERE s.parent_id IS NOT NULL',
    );

    expect(subs.length, 73);
    for (final Map<String, Object?> row in subs) {
      expect(row['pid'], isNotNull, reason: '子分类指向了不存在的父级');
      expect(row['pparent'], isNull, reason: '父级必须是一级（两级硬上限）');
      expect(row['pledger'], row['ledger_id'], reason: '父子必须同账本');
      expect(row['ptype'], row['type'], reason: '父子必须同类型（支出/收入不混）');
    }

    // 没有一个子分类自己又当爹（不允许第三层）
    final int grandparents = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.category} '
      'WHERE parent_id IN (SELECT id FROM ${Tables.category} WHERE parent_id IS NOT NULL)',
    )).first['c']! as int;
    expect(grandparents, 0);
  });

  test('新建第二本账本灌同样完整的两级分类（I6：49 / 24）', () async {
    final Database db = await Db.database();
    final int newLedgerId = await db.insert(Tables.ledger, <String, Object?>{
      'name': '第二本',
      'icon': 'book',
      'sort_order': 1,
      'created_at': '2026-10-21T10:00:00.000',
    });

    final SeedResult result = await seedCategories(db, newLedgerId);

    expect(result.topCount, 15);
    expect(result.subCount, 73);

    final int expenseSubs = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.category} WHERE ledger_id = ? '
      "AND type = 'expense' AND parent_id IS NOT NULL",
      <Object?>[newLedgerId],
    )).first['c']! as int;
    final int incomeSubs = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.category} WHERE ledger_id = ? '
      "AND type = 'income' AND parent_id IS NOT NULL",
      <Object?>[newLedgerId],
    )).first['c']! as int;

    expect(expenseSubs, 49);
    expect(incomeSubs, 24);
  });

  test('sort_order 按同级分组各自从 0 起、连续无洞', () async {
    final Database db = await Db.database();
    final int ledgerId = await Db.ensureCurrentLedgerId();

    final List<Map<String, Object?>> tops = await db.query(
      Tables.category,
      columns: <String>['id', 'sort_order'],
      where: 'ledger_id = ? AND parent_id IS NULL AND type = ?',
      whereArgs: <Object?>[ledgerId, 'expense'],
      orderBy: 'sort_order ASC',
    );
    expect(
      tops.map((Map<String, Object?> r) => r['sort_order']).toList(),
      List<int>.generate(9, (int i) => i),
    );

    final int firstTopId = tops.first['id']! as int;
    final List<Map<String, Object?>> subs = await db.query(
      Tables.category,
      columns: <String>['sort_order'],
      where: 'parent_id = ?',
      whereArgs: <Object?>[firstTopId],
      orderBy: 'sort_order ASC',
    );
    expect(
      subs.map((Map<String, Object?> r) => r['sort_order']).toList(),
      List<int>.generate(6, (int i) => i),
    );
  });

  test('kSubFieldSpecs：地点两端、对象、名称三类详情字段挂对了子分类', () {
    expect(kSubFieldSpecs['公共交通'], <TxnField>[TxnField.from, TxnField.to]);
    expect(kSubFieldSpecs['打车'], <TxnField>[TxnField.from, TxnField.to]);
    expect(kSubFieldSpecs['红包份子'], <TxnField>[TxnField.person]);
    expect(kSubFieldSpecs['课程培训'], <TxnField>[TxnField.subject]);
    // 不需要详情的分类不在表里
    expect(kSubFieldSpecs.containsKey('正餐'), isFalse);
    expect(fieldsOfSub(null), isEmpty);
    expect(fieldsOfSub('用户自建分类'), isEmpty);
  });

  test('pruneDetails：换分类丢掉不认识的字段、同组字段保留、未知一律清空', () {
    final Map<TxnField, String> filled = <TxnField, String>{
      TxnField.from: ' 家 ',
      TxnField.to: '公司',
      TxnField.person: '张三',
      TxnField.subject: '会计',
    };

    // 公共交通只认 from/to
    final Map<TxnField, String> transit = pruneDetails('公共交通', filled);
    expect(transit[TxnField.from], '家', reason: '值要 trim');
    expect(transit[TxnField.to], '公司');
    expect(transit[TxnField.person], '');
    expect(transit[TxnField.subject], '');

    // 同组字段场景切换不丢（公共交通 ⇄ 打车）
    expect(pruneDetails('打车', transit)[TxnField.from], '家');

    // 换了不需要详情的分类 → 全清
    final Map<TxnField, String> meal = pruneDetails('正餐', filled);
    expect(meal.values.every((String v) => v.isEmpty), isTrue);

    // 未知分类 → 全清
    expect(
      pruneDetails('自建', filled).values.every((String v) => v.isEmpty),
      isTrue,
    );
  });

  test('降级表与历史名：通讯→居家/话费网费、提成→奖金/提成、交通/居住/医疗/学习有 legacyNames', () {
    expect(kDemotedCats.length, 2);
    final DemotedCat comm = kDemotedCats.firstWhere(
      (DemotedCat d) => d.oldName == '通讯',
    );
    expect(comm.type, 'expense');
    expect(comm.parentName, '居家');
    expect(comm.newName, '话费网费');
    // 目标子分类必须真的存在，否则迁移会把历史记录挂空
    final SeedCat home = kExpenseSeed.firstWhere(
      (SeedCat c) => c.name == comm.parentName,
    );
    expect(
      home.subs.map((SeedSub s) => s.name),
      contains(comm.newName),
    );

    final Map<String, List<String>> legacy = <String, List<String>>{
      for (final SeedCat c in <SeedCat>[...kExpenseSeed, ...kIncomeSeed])
        if (c.legacyNames.isNotEmpty) c.name: c.legacyNames,
    };
    expect(legacy['出行'], contains('交通'));
    expect(legacy['居家'], contains('居住'));
    expect(legacy['健康'], contains('医疗'));
    expect(legacy['成长'], contains('学习'));
  });
}
