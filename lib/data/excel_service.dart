import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';
import 'models.dart';
import 'repo.dart';

/// Excel 账单导入 / 导出。
///
/// 列顺序（也用于导入识别，第一行是表头）：
///   日期 | 类型 | 分类 | 金额 | 账户 | 备注
///
/// ★ 金额在表里用**元**（人类读写友好），进出数据库时立刻转成**分**。
/// ★ 日期用 `YYYY-MM-DD` 文本，避免 Excel 按地区改成斜杠格式后解析失败。
abstract final class ExcelService {
  static const headers = ['日期', '类型', '分类', '金额', '账户', '备注'];

  /// 导出当前账本全部记录，返回生成的文件路径。
  static Future<String> exportAll(int ledgerId, {String? ledgerName}) async {
    final excel = Excel.createExcel();
    final sheetName = '账单';
    // 默认生成的 Sheet1 改名，多余的删掉，保证只有一个表
    excel.rename(excel.getDefaultSheet()!, sheetName);
    final sheet = excel[sheetName];

    // 表头
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
    }

    final cats = <int, String>{};
    for (final c in await Repo.listCategories(
      ledgerId,
      includeArchived: true,
    )) {
      cats[c.id] = c.name;
    }
    final accs = <int, String>{};
    for (final a in await Repo.listAccounts(includeArchived: true)) {
      accs[a.id] = a.name;
    }

    final db = await Db.open();
    final rows = await db.query(
      'txn',
      where: 'ledger_id = ?',
      whereArgs: [ledgerId],
      orderBy: 'date ASC, id ASC',
    );

    var r = 1;
    for (final row in rows) {
      final t = Txn.fromMap(row);
      final values = <String>[
        t.date,
        t.type.label,
        t.categoryId == null ? '' : (cats[t.categoryId] ?? ''),
        (t.amountCents / 100).toStringAsFixed(2),
        t.accountId == null ? '' : (accs[t.accountId] ?? ''),
        t.note,
      ];
      for (var c = 0; c < values.length; c++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
        );
        cell.value = TextCellValue(values[c]);
      }
      r++;
    }

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('生成 Excel 失败');
    }

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(RegExp(r'[:\-T]'), '');
    final name = '${ledgerName ?? '账本'}-$stamp.xlsx';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 调起系统分享，让用户把账单发到微信 / 邮件 / 存到网盘。
  static Future<void> share(String path, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: _xlsxMime)],
        text: text,
      ),
    );
  }

  /// 让用户挑一个 xlsx 导入，返回导入统计。
  static Future<ImportResult?> pickAndImport(int ledgerId) async {
    // file_picker 13.x：静态方法直接返回 List<PlatformFile>，无 FilePickerResult
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (files.isEmpty) return null;
    final path = files.first.path;
    if (path == null) return null;
    return importFile(ledgerId, path);
  }

  /// 导入一个 xlsx 文件。
  ///
  /// 未知分类 / 未知账户的处理策略：**自动创建**。
  /// 理由：导入的账目不能因为分类没建好就丢掉，用户要的是「数据进来」，
  /// 分不清的分类事后再合并即可（这也是 PRD 待定问题里我给的默认值）。
  static Future<ImportResult> importFile(int ledgerId, String path) async {
    final bytes = File(path).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw StateError('文件里没有工作表');
    }

    final sheet = excel.tables[excel.tables.keys.first]!;
    if (sheet.maxRows <= 1) return const ImportResult(0, 0, 0, 0, []);

    final cats = <String, int>{};
    for (final c in await Repo.listCategories(
      ledgerId,
      includeArchived: true,
    )) {
      cats['${c.type.code}|${c.name}'] = c.id;
    }
    final accs = <String, int>{};
    for (final a in await Repo.listAccounts(includeArchived: true)) {
      accs[a.name] = a.id;
    }

    var imported = 0;
    var skipped = 0;
    var newCats = 0;
    var newAccs = 0;
    final problems = <String>[];

    for (var r = 1; r < sheet.maxRows; r++) {
      final cells = sheet.row(r);
      String at(int i) =>
          i < cells.length ? (cells[i]?.value?.toString() ?? '').trim() : '';

      final rawDate = at(0);
      final rawType = at(1);
      final rawCat = at(2);
      final rawAmount = at(3);
      final rawAcc = at(4);
      final note = at(5);

      // 整行空白直接跳过（导出文件末尾常有空行）
      if (rawDate.isEmpty && rawType.isEmpty && rawAmount.isEmpty) continue;

      final date = _normalizeDate(rawDate);
      if (date == null) {
        skipped++;
        problems.add('第 ${r + 1} 行：日期「$rawDate」无法识别');
        continue;
      }

      final type = _parseType(rawType);
      final amountCents = Fmt.parseCents(rawAmount.replaceAll('¥', ''));
      if (amountCents <= 0) {
        skipped++;
        problems.add('第 ${r + 1} 行：金额「$rawAmount」无效');
        continue;
      }

      // 分类：名称 + 类型 唯一定位；找不到就建
      int? categoryId;
      if (rawCat.isNotEmpty) {
        final key = '${type.code}|$rawCat';
        categoryId = cats[key];
        if (categoryId == null) {
          categoryId = await Repo.insertCategory(
            Category(
              id: 0,
              ledgerId: ledgerId,
              type: type,
              name: rawCat,
              icon: 'more',
              sortOrder: 999,
            ),
          );
          cats[key] = categoryId;
          newCats++;
        }
      }

      // 账户：按名称找；找不到就建
      int? accountId;
      if (rawAcc.isNotEmpty) {
        accountId = accs[rawAcc];
        if (accountId == null) {
          accountId = await Repo.insertAccount(
            Account(
              id: 0,
              name: rawAcc,
              kind: AccountKind.other,
              sortOrder: 999,
            ),
          );
          accs[rawAcc] = accountId;
          newAccs++;
        }
      }

      await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: ledgerId,
          type: type,
          amountCents: amountCents,
          date: date,
          categoryId: categoryId,
          accountId: accountId,
          note: note,
        ),
      );
      imported++;
    }

    return ImportResult(imported, skipped, newCats, newAccs, problems);
  }

  static TxnType _parseType(String raw) {
    final s = raw.trim();
    if (s.contains('收') || s.toLowerCase() == 'income') return TxnType.income;
    return TxnType.expense;
  }

  /// 兼容 `2026-10-16` / `2026/10/16` / `20261016` / Excel 序列号
  static String? _normalizeDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final direct = DateTime.tryParse(s);
    if (direct != null) return Fmt.date(direct);

    final m = RegExp(r'^(\d{4})[/.\-年]?(\d{1,2})[/.\-月]?(\d{1,2})')
        .firstMatch(s);
    if (m != null) {
      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        return Fmt.date(DateTime(y, mo, d));
      }
    }
    return null;
  }

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
}

class ImportResult {
  const ImportResult(
    this.imported,
    this.skipped,
    this.newCategories,
    this.newAccounts,
    this.problems,
  );

  final int imported;
  final int skipped;
  final int newCategories;
  final int newAccounts;
  final List<String> problems;

  String get summary {
    final parts = <String>['成功导入 $imported 条'];
    if (skipped > 0) parts.add('跳过 $skipped 条');
    if (newCategories > 0) parts.add('新建 $newCategories 个分类');
    if (newAccounts > 0) parts.add('新建 $newAccounts 个账户');
    return parts.join('，');
  }
}
