// Excel 导入 / 导出的列序自检。
//
// 这里钉的是「列对不对」，不是「文件能不能打开」：
// 1) 导出的列顺序必须和 headers 一一对应 —— 差一列就会整表错位，
//    而且错得安静（金额被读成账户名，用户在 Excel 里未必看得出来）；
// 2) 一级 / 子分类分两列写，回来时能正确落回两级结构；
// 3) 旧版 6 列文件（没有「子分类」「出发地」等列）照样能导入，
//    缺的列按空串处理，不能整张表报错。
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/category_seed.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/excel_service.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_excel.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 把二维文本写成 xlsx，返回文件路径（避开 path_provider 的平台通道）
String _writeXlsx(String name, List<List<String>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value = TextCellValue(
        rows[r][c],
      );
    }
  }
  final file = File(p.join(Directory.systemTemp.path, name));
  file.writeAsBytesSync(excel.save()!);
  return file.path;
}

void main() {
  late int ledgerId;

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
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  test('导出行与表头一一对应（子分类与四个详情字段都各占一列）', () async {
    final acc = await Repo.insertAccount(const Account(id: 0, name: '现金'));
    final topId = await Repo.insertCategory(
      Category(id: 0, ledgerId: ledgerId, type: TxnType.expense, name: '出行'),
    );
    final subId = await Repo.insertCategory(
      Category(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        name: '公共交通',
        parentId: topId,
      ),
    );
    final top = Category(
      id: topId,
      ledgerId: ledgerId,
      type: TxnType.expense,
      name: '出行',
    );
    final sub = Category(
      id: subId,
      ledgerId: ledgerId,
      type: TxnType.expense,
      name: '公共交通',
      parentId: topId,
    );
    final byId = {top.id: top, sub.id: sub};

    final row = ExcelService.exportRow(
      Txn(
        id: 1,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 650,
        date: '2026-10-12',
        categoryId: sub.id,
        accountId: acc,
        note: '早高峰',
        placeFrom: '家',
        placeTo: '公司',
      ),
      byId,
      {acc: '现金'},
    );

    expect(row.length, ExcelService.headers.length, reason: '列数必须和表头一致');
    for (var i = 0; i < ExcelService.headers.length; i++) {
      final h = ExcelService.headers[i];
      final v = row[i];
      if (h == '分类') expect(v, '出行');
      if (h == '子分类') expect(v, '公共交通');
      if (h == '金额') expect(v, '6.50');
      if (h == '出发地') expect(v, '家');
      if (h == '目的地') expect(v, '公司');
      if (h == '对象' || h == '名称') expect(v, isEmpty);
    }
  });

  test('导入新版 13 列：两级分类与详情字段都落库', () async {
    final path = _writeXlsx('heita_new_format.xlsx', [
      ExcelService.headers,
      // 列序必须跟 headers 走：账户之后多了一列「转入账户」（1.7.2 为转账补的）
      ['2026-10-12', '支出', '人情', '红包份子', '200.00', '现金', '',
        '', '', '', '张三', '', ''],
    ]);

    final r = await ExcelService.importFile(ledgerId, path);
    expect(r.imported, 1);
    expect(r.skipped, 0);

    final cats = await Repo.listCategories(ledgerId);
    final gift = cats.firstWhere((c) => c.name == '人情');
    final sub = cats.firstWhere((c) => c.name == '红包份子');
    expect(sub.parentId, gift.id, reason: '子分类要挂在「人情」下面');

    final rows = await Repo.listTxns(ledgerId: ledgerId, month: '2026-10');
    expect(rows.single.categoryId, sub.id);
    expect(rows.single.person, '张三');
    expect(rows.single.amountCents, 20000);
  });

  test('导入旧版 6 列：缺的列当空，不会整表失败', () async {
    final path = _writeXlsx('heita_old_format.xlsx', [
      ['日期', '类型', '分类', '金额', '账户', '备注'],
      ['2026-10-13', '支出', '餐饮', '12.00', '现金', '午饭'],
    ]);

    final r = await ExcelService.importFile(ledgerId, path);
    expect(r.imported, 1);
    expect(r.skipped, 0);

    final rows = await Repo.listTxns(ledgerId: ledgerId, month: '2026-10');
    expect(rows.single.note, '午饭');
    expect(rows.single.person, isNull);
    expect(rows.single.placeFrom, isNull);
  });

  test('表头认不出时按旧列序兜底，不整表报错', () async {
    final path = _writeXlsx('heita_no_header.xlsx', [
      ['随便', '写点', '什么', '金额', '账户', '备注'],
      ['2026-10-14', '支出', '餐饮', '8.00', '现金', '豆浆'],
    ]);

    final r = await ExcelService.importFile(ledgerId, path);
    expect(r.imported, 1);
    final rows = await Repo.listTxns(ledgerId: ledgerId, month: '2026-10');
    expect(rows.single.amountCents, 800);
    expect(rows.single.note, '豆浆');
  });

  test('子分类名重名但父级不同时，按父级名认人', () async {
    // 造两个同名子分类挂在两个不同的一级下
    final a = await Repo.insertCategory(
      Category(id: 0, ledgerId: ledgerId, type: TxnType.expense, name: '甲类'),
    );
    final b = await Repo.insertCategory(
      Category(id: 0, ledgerId: ledgerId, type: TxnType.expense, name: '乙类'),
    );
    await Repo.insertCategory(
      Category(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        name: '其他项',
        parentId: a,
      ),
    );
    final target = await Repo.insertCategory(
      Category(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        name: '其他项',
        parentId: b,
      ),
    );

    final path = _writeXlsx('heita_dup_sub.xlsx', [
      ExcelService.headers,
      ['2026-10-15', '支出', '乙类', '其他项', '9.00', '', '', '', '', '', ''],
    ]);
    await ExcelService.importFile(ledgerId, path);

    final rows = await Repo.listTxns(ledgerId: ledgerId, month: '2026-10');
    expect(rows.single.categoryId, target, reason: '不能认成「甲类 / 其他项」');
  });

  test('往返等价：支出/收入/负数/转账 导出再导入后语义与余额都不变', () async {
    // 这条用例存在的理由：此前导出侧只测 `exportRow` 的列形状、导入侧只测
    // **手写的行数组**，两侧从未在同一份数据上交接 —— 于是「少一列」「类型
    // 词表不一致」「符号约定不同」这类不对称在结构上不可能被发现。
    // 1.7.2 修的两个缺陷（转账降级成支出、负数被静默丢弃）就是这么长期共存的。
    // 这里让导出的真实输出直接喂给导入，任何不对称都会当场变红。
    final cash = await Repo.insertAccount(
      Account(id: 0, name: '现金', kind: AccountKind.cash, sortOrder: 1),
    );
    final bank = await Repo.insertAccount(
      Account(id: 0, name: '银行卡', kind: AccountKind.debit, sortOrder: 2),
    );

    final cats = await Repo.listCategories(ledgerId);
    final expTop = cats.firstWhere(
      (c) => c.type == TxnType.expense && c.parentId == null,
    );
    final incTop = cats.firstWhere(
      (c) => c.type == TxnType.income && c.parentId == null,
    );

    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 1234,
        date: '2026-10-12',
        categoryId: expTop.id,
        accountId: cash,
        note: '午饭',
      ),
    );
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.income,
        amountCents: 500000,
        date: '2026-10-10',
        categoryId: incTop.id,
        accountId: bank,
        note: '工资',
      ),
    );
    // 负数：退款冲正。导入侧旧实现 `amountCents <= 0` 直接跳过，往返即消失
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: -300,
        date: '2026-10-13',
        categoryId: expTop.id,
        accountId: cash,
        note: '退款冲正',
      ),
    );
    // 转账：双向。旧实现只导出转出侧、导入一律当支出
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.transfer,
        amountCents: 10000,
        date: '2026-10-14',
        accountId: cash,
        toAccountId: bank,
        note: '存钱',
      ),
    );

    final byId = {
      for (final c in await Repo.listCategories(
        ledgerId,
        includeArchived: true,
      ))
        c.id: c,
    };
    final accNames = {
      for (final a in await Repo.listAccounts(includeArchived: true)) a.id: a.name,
    };
    final exported = (await Repo.txnForExport(ledgerId: ledgerId))
        .map((t) => ExcelService.exportRow(t, byId, accNames))
        .toList();
    expect(exported.length, 4);

    final before = {
      for (final a in await Repo.listAccounts()) a.name: a.balanceCents,
    };

    // 清库重建 = 模拟「换机后导入到一台新装的应用」
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
    await Db.open();
    final freshLedger = await Repo.currentLedgerId();

    final path = _writeXlsx('heita_roundtrip.xlsx', [
      ExcelService.headers,
      ...exported,
    ]);
    final r = await ExcelService.importFile(freshLedger, path);

    expect(r.imported, 4, reason: '负数与转账都不该被丢掉');
    expect(r.skipped, 0);

    final rows = await Repo.listTxns(ledgerId: freshLedger, month: '2026-10');
    expect(rows.length, 4);

    final transfer = rows.firstWhere((t) => t.type == TxnType.transfer);
    expect(transfer.toAccountId, isNotNull, reason: '转入账户必须原样回来');
    expect(transfer.amountCents, 10000);

    final refund = rows.firstWhere((t) => t.note == '退款冲正');
    expect(refund.amountCents, -300, reason: '负数流水不能在往返中消失');

    final after = {
      for (final a in await Repo.listAccounts()) a.name: a.balanceCents,
    };
    expect(after, before, reason: '两个账户的余额都要与导出前完全一致');
  });

  test('字段表与导出列保持同步', () {
    // 四个详情字段各占表里一列，漏一个就静默丢数据
    for (final f in TxnField.values) {
      expect(
        ExcelService.headers.contains(f.label),
        isTrue,
        reason: '${f.label} 没有出现在导出表头里',
      );
    }
    // 只查详情字段是不够的：**类型维度**同样会漏。转账在 1.7.2 之前没有
    // 转入侧列、`_parseType` 也不认「转账」，往返一次就变成一条普通支出 ——
    // 而这条用例当时是绿的，因为它压根没看 TxnType。
    for (final t in TxnType.values) {
      expect(
        ExcelService.exportRow(
          Txn(
            id: 0,
            ledgerId: 1,
            type: t,
            amountCents: 100,
            date: '2026-10-12',
          ),
          const {},
          const {},
        )[1],
        t.label,
        reason: '类型列必须写出 ${t.label}',
      );
    }
  });
}
