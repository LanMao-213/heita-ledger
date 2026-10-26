part of '../bill_csv.dart';

// ---------------------------------------------------------------------------
// 解析主流程（表头识别、行切分、列对齐）
//
// 库私有（`part of` 与 `bill_csv.dart` 共享私有作用域）；对外只暴露
// `BillCsv.parse` / `parseAmount` / `parseDate` / `markDuplicates` 四个入口，
// 门面在 `bill_csv.dart` 里。
// ---------------------------------------------------------------------------

  /// 解析字节流。
  ///
  /// 抛 [BillParseException] 的三种情况：编码、找不到表头、没有可导入行。
BillParseResult _parse(List<int> bytes) {
  final (text, encoding) = _decode(bytes);
  final records = _splitCsvRecords(text);
  if (records.isEmpty) {
    throw BillParseException(BillParseError.empty, '这个文件是空的');
  }

  // --- 找表头：前 30 条记录里找同时含「金额」和时间列的那一条 ---
  var headerIdx = -1;
  for (var i = 0; i < records.length && i < 30; i++) {
    final cells = records[i].cells;
    if (_findCol(cells, _colAmount) >= 0 && _findCol(cells, _colDate) >= 0) {
      headerIdx = i;
      break;
    }
  }
  if (headerIdx < 0) {
    throw BillParseException(
      BillParseError.header,
      '没找到表头（需要含「交易时间」和「金额」两列）。\n'
          '请确认导出的是「支付宝 → 账单导出」或「微信 → 账单 → 导出」的 CSV。',
    );
  }

  final header = records[headerIdx].cells;
  final idxDate = _findCol(header, _colDate);
  final idxAmount = _findCol(header, _colAmount);
  final idxDir = _findCol(header, _colDir);
  final idxCounterparty = _findCol(header, _colCounterparty);
  final idxNote = _findCol(header, _colNote);
  final idxPayMethod = _findCol(header, _colPayMethod);
  final idxStatus = _findCol(header, _colStatus);
  final idxCategory = _findCol(header, _colCategory);

  // 来源要从**表头之前的说明区**判断：「支付宝」「微信」这两个词写在
  // 文件首行，不在表头里 —— 只看表头会一律判成 unknown。
  final source = _detectSource(
    records.take(headerIdx + 1).map((r) => r.cells.join(' ')).join('|'),
    header: header,
  );

  final rows = <BillRow>[];
  final warnings = <String>[];
  var skipped = 0;

  for (var i = headerIdx + 1; i < records.length; i++) {
    final record = records[i];
    final rawCells = record.cells;
    if (rawCells.every((c) => c.trim().isEmpty)) continue;

    // 表头在文件里重复出现（支付宝分月导出会这样）
    if (_findCol(rawCells, _colAmount) >= 0 &&
        _findCol(rawCells, _colDate) >= 0) {
      continue;
    }

    // ★ 列数对齐：见 [_fitToHeader] 的注释 —— 不做这一步，
    //   商品说明里一个没加引号的逗号就会让整行错位并被静默丢掉。
    final cells = _fitToHeader(rawCells, header.length, idxNote, idxCounterparty);

    final amountRaw = _cell(cells, idxAmount);
    final dateRaw = _cell(cells, idxDate);
    final dirRaw = _cell(cells, idxDir);
    final statusRaw = _cell(cells, idxStatus);

    // 说明行：金额和时间都不像数据
    final parsedAmount = _parseAmount(amountRaw);
    final parsedDate = _parseDate(dateRaw);
    if (parsedAmount == null || parsedDate == null) {
      skipped++;
      continue;
    }

    final lineNo = record.lineNo;

    // 「不计收支」的行（转账、还款、余额宝收益等）不进账本
    if (dirRaw.contains('不计')) {
      skipped++;
      continue;
    }

    if (_deadStatus.any(statusRaw.contains)) {
      skipped++;
      continue;
    }

    final type = _resolveType(dirRaw, parsedAmount);
    rows.add(
      BillRow(
        lineNo: lineNo,
        date: parsedDate.$1,
        time: parsedDate.$2,
        amountCents: parsedAmount.abs(),
        type: type,
        counterparty: _cell(cells, idxCounterparty),
        note: _cell(cells, idxNote),
        payMethod: _cell(cells, idxPayMethod),
        rawAmount: amountRaw,
        // 收入默认不算入：黑塔有收入分类，但账单里的「收入」经常是
        // 退款 / 转账 / 理财赎回，混进收入会污染收支结构。
        // 默认关 + 单独一档让用户勾，是这里唯一正确的默认值。
        include: type == TxnType.expense,
      ),
    );

    if (idxDir < 0 && dirRaw.isEmpty) {
      // 靠金额符号推方向：这种情况要提示，因为符号未必可靠
      if (warnings.length < 3) {
        warnings.add('第 $lineNo 行没有「收/支」列，已按金额符号判断方向');
      }
    }
    if (idxCategory < 0 && warnings.isEmpty) {
      warnings.add('没找到「交易分类」列，分类将按关键词猜，猜不中记为未分类');
    }
  }

  if (rows.isEmpty) {
    throw BillParseException(
      BillParseError.empty,
      '文件里没有可导入的支出或收入记录（跳过 $skipped 行）。\n'
          '如果这份账单全是「不计收支」的转账，它本来就不该进消费账。',
    );
  }

  return BillParseResult(
    rows: rows,
    source: source,
    skippedLines: skipped,
    headerLine: headerIdx + 1,
    encoding: encoding,
    warnings: warnings,
  );
}

// ------------------------------------------------------------------ 编码

BillSource _detectSource(String preamble, {List<String>? header}) {
  final joined = '$preamble|${header?.join('|') ?? ''}';
  if (joined.contains('支付宝')) return BillSource.alipay;
  if (joined.contains('微信')) return BillSource.wechat;
  return BillSource.unknown;
}

int _findCol(List<String> header, List<String> keys) {
  for (var i = 0; i < header.length; i++) {
    final h = header[i].trim().replaceAll('"', '');
    for (final k in keys) {
      if (h == k) return i;
    }
  }
  // 退一步：包含匹配（表头可能写成「金额(元)」或「交易时间 」）
  for (var i = 0; i < header.length; i++) {
    final h = header[i].trim().replaceAll('"', '');
    for (final k in keys) {
      if (h.contains(k)) return i;
    }
  }
  return -1;
}

  /// 取一格的值。
  ///
  /// ★ 只 trim，**不再全局replaceAll('"')**：结构性的引号已经由
  ///   [_splitCsvRecords] 吃掉，`""` 也已还原成一个字面量引号。
  ///   再全局删一遍会把**合法的引号**一起删掉 ——
  ///   商品说明写成 `他说"好"的` 会变成 `他说好的`，而且用户永远发现不了。
String _cell(List<String> cells, int idx) {
  if (idx < 0 || idx >= cells.length) return '';
  return cells[idx].trim();
}

  /// 方向：优先看「收/支」列，其次看金额符号。
TxnType _resolveType(String dirRaw, int signedAmount) {
  if (dirRaw.contains('支出') || dirRaw.contains('付款')) {
    return TxnType.expense;
  }
  if (dirRaw.contains('收入') || dirRaw.contains('收款')) return TxnType.income;
  return signedAmount < 0 ? TxnType.expense : TxnType.income;
}

  /// 全文按 RFC4180 切成「记录」，而不是按 `\n` 切成「行」。
  ///
  /// ★ 为什么要整篇扫而不是逐行扫：引号内的**换行**属于字段内容。
  ///   支付宝 / 微信导出的「商品说明」偶尔带换行（多行备注），
  ///   逐行切会把一条记录劈成两条残行 —— 两条都解析失败，**静默丢一笔真账**。
  ///   整篇扫描一次就能正确吃下跨行字段，同时不牺牲原有能力
  ///   （引号包裹、`""` 转义、字段内逗号）。
  ///
  /// ★ 每条记录带 `lineNo`：跨行记录会让「行号」与「记录序号」不再相等，
  ///   而 [BillRow.lineNo] 是给用户报「第 N 行有问题」用的，必须是**原文行号**。
  ///   所以扫描时单独维护行计数器，引号内换行也要推进它。
  ///
  /// 没有引 csv 包（见 pubspec 的「零新依赖」约定），但账单里的
  /// 「商品说明」经常带逗号，所以必须处理引号，不能直接 `split(',')`。
List<_CsvRecord> _splitCsvRecords(String text) {
  final out = <_CsvRecord>[];
  var buf = StringBuffer();
  var cells = <String>[];
  var inQuote = false;
  var line = 1;
  var recordLine = 1;
  var i = 0;
  final n = text.length;

  void endField() {
    cells.add(buf.toString());
    buf = StringBuffer();
  }

  void endRecord() {
    endField();
    out.add(_CsvRecord(cells, recordLine));
    cells = <String>[];
    recordLine = line;
  }

  while (i < n) {
    final ch = text[i];

    if (inQuote) {
      if (ch == '"') {
        if (i + 1 < n && text[i + 1] == '"') {
          buf.write('"');
          i += 2;
        } else {
          inQuote = false;
          i++;
        }
      } else if (ch == '\r' || ch == '\n') {
        // 引号内的换行是字段内容，但行号必须继续推进
        if (ch == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
        i++;
        buf.write('\n');
        line++;
      } else {
        buf.write(ch);
        i++;
      }
      continue;
    }

    if (ch == '"') {
      inQuote = true;
      i++;
    } else if (ch == ',') {
      endField();
      i++;
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
      i++;
      line++;
      endRecord();
    } else {
      buf.write(ch);
      i++;
    }
  }

  // 末尾没有换行收尾的最后一条
  if (buf.isNotEmpty || cells.isNotEmpty) {
    endField();
    out.add(_CsvRecord(cells, recordLine));
  }
  return out;
}

  /// 把一条记录的列数对齐到表头列数。
  ///
  /// ★ 这一步是「丢账」与「不丢账」的分界。支付宝 / 微信**不保证给字段加引号**，
  ///   而「商品说明」「交易对方」里完全可能有逗号。出现一个没加引号的逗号，
  ///   这一条就会多切出几列，**后面所有列整体右移** ——
  ///   金额列读到的是「支出」这种文字，[parseAmount] 返回 null，
  ///   整行被当成说明行丢掉。而它其实是一笔真账。
  ///
  /// 处理办法（与业界通行做法一致）：多出来的列**并回唯一可能含逗号的列**
  /// （优先「商品说明」，其次「交易对方」）；少列则补空串
  /// （容忍行尾空字段被省略）。两种情况都保持列数 = 表头列数，
  /// 后面所有按下标取值的地方才安全。
List<String> _fitToHeader(
  List<String> row,
  int headerSize,
  int noteIdx,
  int counterpartyIdx,
) {
  if (row.length == headerSize) return row;
  if (row.length < headerSize) {
    return [...row, ...List.filled(headerSize - row.length, '')];
  }
  final mergeAt = noteIdx >= 0 && noteIdx < row.length
      ? noteIdx
      : (counterpartyIdx >= 0 && counterpartyIdx < row.length
            ? counterpartyIdx
            : headerSize - 1);
  final extra = row.length - headerSize;
  final out = <String>[];
  for (var idx = 0; idx < row.length; idx++) {
    if (idx < mergeAt) {
      out.add(row[idx]);
    } else if (idx == mergeAt) {
      out.add(row.sublist(mergeAt, mergeAt + extra + 1).join(','));
    } else if (idx > mergeAt + extra) {
      out.add(row[idx]);
    }
  }
  return out;
}

// ------------------------------------------------------------- 重复判定


/// 一条 CSV 记录：切好的字段 + 它在原文里的**起始行号**（1 起）。
///
/// 单独一个类而不是 `List<String>`，只因为 [BillRow.lineNo] 要报原文行号；
/// 引号内换行会让「记录序号」与「行号」错开，两者必须分开记。
class _CsvRecord {
  _CsvRecord(this.cells, this.lineNo);

  final List<String> cells;
  final int lineNo;
}
