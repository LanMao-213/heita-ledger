// 两级分类之后，筛选与搜索的口径自检。
//
// 这两个坑都很隐蔽：
// 1) 记录一旦挂到子分类（「餐饮 / 正餐」）上，按一级「餐饮」筛选如果只写
//    `category_id = ?`，结果就是 0 条 —— 界面看起来正常，只是「筛了没反应」；
// 2) 关键词只搜备注，就搜不到「对象=张三」这类 v6 详情字段，
//    而用户明明是按名字记的账。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_filter_twolevel.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  late int ledgerId;
  late int catFood;
  late int subMeal;
  late int catGift;
  late int subRedpacket;
  late int acc;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();

    await Db.open();
    ledgerId = await Repo.currentLedgerId();
    acc = await Repo.insertAccount(const Account(id: 0, name: '现金'));

    catFood = await Repo.insertCategory(
      Category(id: 0, ledgerId: ledgerId, type: TxnType.expense, name: '餐饮'),
    );
    subMeal = await Repo.insertCategory(
      Category(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        name: '正餐',
        parentId: catFood,
      ),
    );
    catGift = await Repo.insertCategory(
      Category(id: 0, ledgerId: ledgerId, type: TxnType.expense, name: '人情'),
    );
    subRedpacket = await Repo.insertCategory(
      Category(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        name: '红包份子',
        parentId: catGift,
      ),
    );

    Future<int> add(
      int? cat,
      int cents, {
      String note = '',
      String? person,
      String? subject,
      String? from,
      String? to,
    }) => Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: cents,
        date: '2026-10-0${cents % 9 + 1}',
        categoryId: cat,
        accountId: acc,
        note: note,
        person: person,
        subject: subject,
        placeFrom: from,
        placeTo: to,
      ),
    );

    await add(subMeal, 3000, note: '午饭'); // 子分类
    await add(catFood, 1500, note: '食堂'); // 一级（未细分）
    await add(subRedpacket, 20000, person: '张三');
    await add(subRedpacket, 6600, person: '李四', note: '生日');
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  Future<List<Txn>> query({TxnFilter? f, String? keyword}) async {
    final r = await Repo.searchTxns(
      ledgerId: ledgerId,
      keyword: keyword,
      filter: f,
      limit: Repo.searchLimit,
    );
    return r.$1;
  }

  test('按一级分类筛，子分类的记录一起带上', () async {
    final rows = await query(f: TxnFilter(categoryId: catFood));
    expect(rows.length, 2, reason: '「餐饮」要同时包含 未细分 与 正餐 两条');
    expect(
      rows.every((t) => t.categoryId == catFood || t.categoryId == subMeal),
      isTrue,
    );
  });

  test('按子分类筛，只出这一子分类的记录', () async {
    final rows = await query(f: TxnFilter(categoryId: subMeal));
    expect(rows.length, 1);
    expect(rows.single.note, '午饭');
  });

  test('合计与列表同一口径（子分类也算进一级）', () async {
    final sum = await Repo.sumFiltered(
      ledgerId: ledgerId,
      filter: TxnFilter(categoryId: catFood),
    );
    expect(sum.$1, 4500, reason: '3000 + 1500');
  });

  test('关键词能搜到对象、名称、地点两端', () async {
    expect((await query(keyword: '张三')).length, 1);
    expect((await query(keyword: '李四')).length, 1);
    // 备注照样搜得到
    expect((await query(keyword: '午饭')).length, 1);
    // 搜不到的就是搜不到，不能因为连了 5 个 LIKE 就变成「全都命中」
    expect(await query(keyword: '王五'), isEmpty);
  });
}
