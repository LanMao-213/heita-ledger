// 明细筛选的数据层自检。
//
// 这里最值得钉住的是两件肉眼很难发现的事：
// 1) 转账记录的「账户」归属 —— 漏掉 to_account_id 时，筛账户会凭空少记录，
//    表现是「明明转过账，筛这个账户却看不到」，靠点界面基本发现不了；
// 2) 截断标记 —— 只查 limit 条的话，「正好 500 条」和「还有更多」在调用方
//    无法区分，界面上那句「仅显示前 500 条」就成了空话。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_filter.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  late int ledgerId;
  late int catFood;
  late int catSalary;
  late int accCash;
  late int accBank;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 和各测试文件各用各的库，避免并行时抢同一个文件
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();

    await Db.open();
    ledgerId = await Repo.currentLedgerId();
    catFood = await Repo.insertCategory(Category(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.expense,
      name: '餐饮',
    ));
    catSalary = await Repo.insertCategory(Category(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.income,
      name: '工资',
    ));
    accCash = await Repo.insertAccount(const Account(id: 0, name: '现金'));
    accBank = await Repo.insertAccount(const Account(id: 0, name: '银行卡'));
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  Future<int> add({
    required TxnType type,
    required int cents,
    required String date,
    int? cat,
    int? acc,
    int? toAcc,
    String note = '',
  }) =>
      Repo.insertTxn(Txn(
        id: 0,
        ledgerId: ledgerId,
        type: type,
        amountCents: cents,
        date: date,
        categoryId: cat,
        accountId: acc,
        toAccountId: toAcc,
        note: note,
      ));

  /// 四条记录，覆盖支出/收入/转账、两个账户、两个月份
  Future<void> seed() async {
    await add(type: TxnType.expense, cents: 8000, date: '2026-10-01', cat: catFood, acc: accCash, note: '午饭');
    await add(type: TxnType.expense, cents: 30000, date: '2026-10-05', cat: catFood, acc: accBank, note: '聚餐');
    await add(type: TxnType.income, cents: 1000000, date: '2026-10-10', cat: catSalary, acc: accBank, note: '工资');
    await add(type: TxnType.transfer, cents: 50000, date: '2026-09-20', acc: accBank, toAcc: accCash, note: '取现');
  }

  Future<List<Txn>> query(TxnFilter f, {String? keyword, int? limit}) async {
    final r = await Repo.searchTxns(
      ledgerId: ledgerId,
      keyword: keyword,
      filter: f,
      limit: limit ?? Repo.searchLimit,
    );
    return r.$1;
  }

  test('空条件等价于全量，且不报截断', () async {
    await seed();
    final (items, truncated) =
        await Repo.searchTxns(ledgerId: ledgerId, filter: TxnFilter.none);
    expect(items.length, 4);
    expect(truncated, isFalse);
    // 默认按日期倒序
    expect(items.first.date, '2026-10-10');
    expect(items.last.date, '2026-09-20');
  });

  test('分类筛只命中该分类', () async {
    await seed();
    final hit = await query(TxnFilter(categoryId: catFood));
    expect(hit.length, 2);
    expect(hit.every((t) => t.categoryId == catFood), isTrue);
    // 收入分类是另一条线，互不串味
    expect((await query(TxnFilter(categoryId: catSalary))).length, 1);
  });

  test('账户筛要把转账的转入端也算进来', () async {
    await seed();
    final items = await query(TxnFilter(accountId: accCash));
    expect(items.length, 2);
    expect(items.any((t) => t.type == TxnType.transfer), isTrue);
    expect(items.any((t) => t.note == '午饭'), isTrue);
  });

  test('金额区间两端都含', () async {
    await seed();
    expect((await query(const TxnFilter(minCents: 10000, maxCents: 50000))).length, 2);
    // 端点值本身要命中
    final exact = await query(const TxnFilter(minCents: 8000, maxCents: 8000));
    expect(exact.length, 1);
    expect(exact.first.note, '午饭');
  });

  test('只填一端也能用', () async {
    await seed();
    final big = await query(const TxnFilter(minCents: 30000));
    expect(big.length, 3); // 聚餐 30000、取现 50000、工资 1000000
    final small = await query(const TxnFilter(maxCents: 8000));
    expect(small.length, 1);
  });

  test('时间段两端都含', () async {
    await seed();
    final items =
        await query(const TxnFilter(dateFrom: '2026-10-01', dateTo: '2026-10-10'));
    expect(items.length, 3);
    expect(items.any((t) => t.date == '2026-09-20'), isFalse);
    // 端点那天本身要在结果里
    expect(items.any((t) => t.date == '2026-10-01'), isTrue);
    expect(items.any((t) => t.date == '2026-10-10'), isTrue);
  });

  test('多条件是 AND 叠加', () async {
    await seed();
    final items = await query(TxnFilter(categoryId: catFood, minCents: 10000));
    expect(items.length, 1);
    expect(items.first.note, '聚餐');
  });

  test('收支类型可单独筛', () async {
    await seed();
    expect((await query(const TxnFilter(type: TxnType.income))).length, 1);
    expect((await query(const TxnFilter(type: TxnType.expense))).length, 2);
    expect((await query(const TxnFilter(type: TxnType.transfer))).length, 1);
  });

  test('关键词与筛选叠加，空关键词不影响', () async {
    await seed();
    expect((await query(TxnFilter(categoryId: catFood), keyword: '聚')).length, 1);
    expect((await query(TxnFilter(categoryId: catFood), keyword: '   ')).length, 2);
  });

  test('超出上限时标记截断，正好等于上限时不算截断', () async {
    await seed();
    final over = await Repo.searchTxns(ledgerId: ledgerId, limit: 2);
    expect(over.$1.length, 2);
    expect(over.$2, isTrue);

    final exact = await Repo.searchTxns(ledgerId: ledgerId, limit: 4);
    expect(exact.$1.length, 4);
    expect(exact.$2, isFalse);
  });

  // D20：列表有 500 条上限，但合计不能跟着截。
  //
  // 旧实现是把 filteredTxns 相加当合计，501 笔时界面只有 50000 分（真实 50100），
  // 而条件条上还写着「仅显示前 500 条」—— 两个数字互相矛盾。
  // 现在合计走 Repo.sumFiltered 独立聚合，笔数与金额都是真实值。
  test('超过 500 条：列表截断，但合计覆盖全部', () async {
    final db = await Db.open();
    final batch = db.batch();
    for (var i = 1; i <= 501; i++) {
      batch.insert(
        'txn',
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.expense,
          amountCents: 100,
          date: '2026-09-01',
          categoryId: catFood,
          accountId: accCash,
          note: '第 $i 笔',
        ).toMap(),
      );
    }
    await batch.commit(noResult: true);

    final (items, truncated) = await Repo.searchTxns(ledgerId: ledgerId);
    expect(items.length, Repo.searchLimit);
    expect(truncated, isTrue);

    // 合计与笔数走聚合：501 笔 × 1.00 = 50100 分，一分不少
    final (expense, income, count) = await Repo.sumFiltered(ledgerId: ledgerId);
    expect(expense, 50100);
    expect(income, 0);
    expect(count, 501);

    // 列表相加只有 50000 —— 这正是旧实现会显示的数，别再退回去
    final shown = items.fold<int>(0, (a, t) => a + t.amountCents);
    expect(shown, 50000);
  });

  // 合计换了统计方式，就必须和内存侧同口径，否则「饼图分项之和 ≠ 合计」
  // 那类自相矛盾会以另一种形式回来。
  test('sumFiltered 与 sumBySide 同口径（含转账与负数）', () async {
    await add(
      type: TxnType.expense,
      cents: 30000,
      date: '2026-09-01',
      cat: catFood,
      acc: accCash,
    );
    // 支出里的负数：算进收入
    await add(
      type: TxnType.expense,
      cents: -5000,
      date: '2026-09-02',
      cat: catFood,
      acc: accCash,
    );
    await add(
      type: TxnType.income,
      cents: 1000000,
      date: '2026-09-03',
      cat: catSalary,
      acc: accBank,
    );
    // 收入里的负数：算进支出
    await add(
      type: TxnType.income,
      cents: -2000,
      date: '2026-09-04',
      cat: catSalary,
      acc: accBank,
    );
    // 转账两侧都不参与合计，但算一笔
    await add(
      type: TxnType.transfer,
      cents: 50000,
      date: '2026-09-05',
      acc: accBank,
      toAcc: accCash,
    );

    final (items, _) = await Repo.searchTxns(ledgerId: ledgerId);
    final (expense, income, count) = await Repo.sumFiltered(ledgerId: ledgerId);

    expect(expense, sumBySide(items, TxnType.expense));
    expect(income, sumBySide(items, TxnType.income));
    expect(expense, 32000); // 30000 + |收入里的 −2000|
    expect(income, 1005000); // 1000000 + |支出里的 −5000|
    expect(count, 5);
  });

  test('sumFiltered 跟随筛选条件，不是全表', () async {
    await add(
      type: TxnType.expense,
      cents: 10000,
      date: '2026-09-01',
      cat: catFood,
      acc: accCash,
    );
    await add(
      type: TxnType.expense,
      cents: 20000,
      date: '2026-09-15',
      cat: catFood,
      acc: accCash,
    );
    await add(
      type: TxnType.expense,
      cents: 30000,
      date: '2026-09-30',
      cat: catFood,
      acc: accCash,
    );

    final (expense, _, count) = await Repo.sumFiltered(
      ledgerId: ledgerId,
      filter: const TxnFilter(dateFrom: '2026-09-01', dateTo: '2026-09-15'),
    );
    expect(expense, 30000); // 只有前两笔
    expect(count, 2);
  });
}
