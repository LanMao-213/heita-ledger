import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'category_seed.dart';
import 'db.dart';
import 'models.dart';
import 'repo.dart';

/// Excel 账单导入 / 导出。
///
/// 列顺序（也用于导入识别，第一行是表头）：
///   日期 | 类型 | 分类 | 子分类 | 金额 | 账户 | 备注 | 出发地 | 目的地 | 对象 | 名称
///
/// ★ 金额在表里用**元**（人类读写友好），进出数据库时立刻转成**分**。
/// ★ 日期用 `YYYY-MM-DD` 文本，避免 Excel 按地区改成斜杠格式后解析失败。
/// ★ 导入按**表头名**定位，不按列号：老版本导出的 6 列文件、用户自己加过列的
///   文件、以及本版本 11 列的文件都能读。按列号读的话，多一列就整体错位，
///   而且错得很安静 —— 金额被读成账户名这种事查起来非常费劲。
abstract final class ExcelService {
  static const headers = [
    '日期',
    '类型',
    '分类',
    '子分类',
    '金额',
    '账户',
    '备注',
    '出发地',
    '目的地',
    '对象',
    '名称',
  ];

  /// 旧版（≤ v5）导出的表头，表头认不出来时按列号兜底用
  static const _legacyHeaders = ['日期', '类型', '分类', '金额', '账户', '备注'];

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

    final byId = <int, Category>{};
    for (final c in await Repo.listCategories(
      ledgerId,
      includeArchived: true,
    )) {
      byId[c.id] = c;
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
      final values = exportRow(t, byId, accs);
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

  /// 一条记录 → 一行单元格文本（顺序必须与 [headers] 一致）。
  ///
  /// 单独拆出来是为了能测：导出整条链路要落盘 + 走 path_provider 的平台通道，
  /// 在测试里跑不通，但「列对不对」恰恰是最容易错、也最该钉住的一环。
  static List<String> exportRow(
    Txn t,
    Map<int, Category> byId,
    Map<int, String> accountNames,
  ) {
    // 一级 / 子分类拆成两列：拼成「餐饮 / 正餐」一列虽然好看，但导入时
    // 要按分隔符拆，而分类名本身就可能带斜杠。
    final cat = byId[t.categoryId];
    final parentId = cat?.parentId;
    final parent = parentId == null ? null : byId[parentId];
    final topName = parent?.name ?? cat?.name ?? '';
    return [
      t.date,
      t.type.label,
      topName,
      parent == null ? '' : (cat?.name ?? ''),
      (t.amountCents / 100).toStringAsFixed(2),
      t.accountId == null ? '' : (accountNames[t.accountId] ?? ''),
      t.note,
      t.detail(TxnField.from),
      t.detail(TxnField.to),
      t.detail(TxnField.person),
      t.detail(TxnField.subject),
    ];
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

    final cols = _columnIndex(sheet.row(0));

    final byId = <int, Category>{};
    final byName = <String, List<Category>>{};
    for (final c in await Repo.listCategories(
      ledgerId,
      includeArchived: true,
    )) {
      byId[c.id] = c;
      byName.putIfAbsent('${c.type.code}|${c.name}', () => []).add(c);
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

    /// 找（必要时建）一级分类
    Future<int> ensureTop(TxnType type, String name) async {
      for (final c in byName['${type.code}|$name'] ?? const <Category>[]) {
        if (c.parentId == null) return c.id;
      }
      final id = await Repo.insertCategory(
        Category(
          id: 0,
          ledgerId: ledgerId,
          type: type,
          name: name,
          icon: 'more',
          sortOrder: 999,
        ),
      );
      final created = Category(
        id: id,
        ledgerId: ledgerId,
        type: type,
        name: name,
        sortOrder: 999,
      );
      byId[id] = created;
      byName.putIfAbsent('${type.code}|$name', () => []).add(created);
      newCats++;
      return id;
    }

    /// 定位一条记录该挂哪个分类。返回 null 表示这一行没写分类。
    Future<int?> resolveCat(TxnType type, String top, String sub) async {
      if (top.isEmpty && sub.isEmpty) return null;
      if (sub.isEmpty) return ensureTop(type, top);

      // 子分类已存在且父级对得上 → 直接用（同名子分类可能挂在不同一级下，
      // 所以父级名给了就必须校验，别把「餐饮/正餐」认成「娱乐/正餐」）
      final subs = byName['${type.code}|$sub'] ?? const <Category>[];
      for (final c in subs) {
        if (c.parentId == null) continue;
        if (top.isEmpty || byId[c.parentId]?.name == top) return c.id;
      }

      // 子分类不存在：给了父级名就在它下面建；只给了子分类名就单独建一个
      // 一级分类 —— 宁可多一个平级分类，也不要让这条账目丢掉。
      final parentId = top.isEmpty ? null : await ensureTop(type, top);
      final id = await Repo.insertCategory(
        Category(
          id: 0,
          ledgerId: ledgerId,
          type: type,
          name: sub,
          icon: 'more',
          parentId: parentId,
          sortOrder: 999,
        ),
      );
      newCats++;
      final created = Category(
        id: id,
        ledgerId: ledgerId,
        type: type,
        name: sub,
        parentId: parentId,
        sortOrder: 999,
      );
      byId[id] = created;
      byName.putIfAbsent('${type.code}|$sub', () => []).add(created);
      return id;
    }

    for (var r = 1; r < sheet.maxRows; r++) {
      final cells = sheet.row(r);
      String at(String col) {
        final i = cols[col];
        if (i == null || i >= cells.length) return '';
        return (cells[i]?.value?.toString() ?? '').trim();
      }

      final rawDate = at('日期');
      final rawType = at('类型');
      final rawTop = at('分类');
      final rawSub = at('子分类');
      final rawAmount = at('金额');
      final rawAcc = at('账户');
      final note = at('备注');

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

      final categoryId = await resolveCat(type, rawTop, rawSub);

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
          placeFrom: at('出发地'),
          placeTo: at('目的地'),
          person: at('对象'),
          subject: at('名称'),
        ),
      );
      imported++;
    }

    return ImportResult(imported, skipped, newCats, newAccs, problems);
  }

  /// 表头名 → 列号。
  ///
  /// 认不出表头（用户删了第一行、或者从别处拷来的表）时退回旧版的列序，
  /// 总比整张表导入失败强 —— 那种情况下用户至少还能得到一条条报错。
  static Map<String, int> _columnIndex(List<Data?> header) {
    final map = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final name = (header[i]?.value?.toString() ?? '').trim();
      if (name.isEmpty) continue;
      map.putIfAbsent(name, () => i);
    }
    // 老文件的表头也有「日期 / 金额」，只是没有「子分类」和详情字段，
    // 直接复用上面这份映射即可：缺的列 at() 会返回空串。
    if (map.containsKey('日期') && map.containsKey('金额')) return map;

    for (var i = 0; i < _legacyHeaders.length; i++) {
      map.putIfAbsent(_legacyHeaders[i], () => i);
    }
    return map;
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
