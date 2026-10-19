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

  test('导入新版 11 列：两级分类与详情字段都落库', () async {
    final path = _writeXlsx('heita_new_format.xlsx', [
      ExcelService.headers,
      ['2026-10-12', '支出', '人情', '红包份子', '200.00', '现金', '', '', '', '张三', ''],
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

  test('字段表与导出列保持同步', () {
    // 四个详情字段各占表里一列，漏一个就静默丢数据
    for (final f in TxnField.values) {
      expect(
        ExcelService.headers.contains(f.label),
        isTrue,
        reason: '${f.label} 没有出现在导出表头里',
      );
    }
  });
}
