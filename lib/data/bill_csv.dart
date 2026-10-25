/// 支付宝 / 微信账单 CSV 解析。
///
/// ## 为什么单独一层
///
/// 这三个理由决定了它必须是**纯函数**、不碰数据库也不碰 UI：
/// 1. 账单格式脏得超出想象（表头中英混排、说明行、金额带 ¥ 与千分位、
///    收/支列有空值），出错的方式有几十种，只有纯函数才测得起；
/// 2. 解析结果要**给用户逐行过目**，所以它不能边解析边写库；
/// 3. 同一份文件可能被导两次 —— 判定重复的逻辑必须能脱离数据库单测。
///
/// ## 编码：这里有一条**明确的取舍**
///
/// 支付宝导出的 CSV 常见 GBK，而 Dart 标准库只有 utf8 / latin1 / ascii，
/// **没有 GBK 编解码**。项目红线之一是「不新增依赖」，所以本版的处理是：
///
/// - 支持 UTF-8（含 BOM）、UTF-16LE/BE（含 BOM）；
/// - 探测到字节像 GBK（有 >0x7F 且非合法 UTF-8 序列）时**明确报错**，
///   并给出可操作的指引（用 Excel 另存为 UTF-8 CSV），
/// - **绝不**用 `allowMalformed` 硬解 —— 那样会把「锟斤拷」写进用户的账本，
///   是最坏的失败模式：用户看到乱码时，数据已经进库了。
///
/// 这条取舍写在 [BillParseError.encoding] 的文案里，用户看得见。
library;

import 'dart:convert';

import 'models.dart';

/// 账单来源。决定表头怎么认、字段怎么取。
enum BillSource {
  alipay('支付宝'),
  wechat('微信'),
  unknown('未知来源');

  const BillSource(this.label);
  final String label;
}

/// 解析失败的原因分类。UI 据此给不同指引，不把技术细节丢给用户。
///
/// 编码问题细分成三类，是因为**要跟用户说的话完全不同**：
/// 「这是 GBK，去另存为 UTF-8」「这是 Excel 文件不是 CSV」「这是 UTF-16」。
/// 一句笼统的「编码不对」，用户没法照着做 —— 诊断越准，用户越可能自己解决。
enum BillParseError {
  /// 不像 UTF-8，也认不出具体是什么编码（兜底）
  encoding,

  /// 字节特征符合 GBK / GB18030（中文 Windows 与旧版支付宝导出常见）
  encodingGbk,

  /// 无 BOM 的 UTF-16
  encodingUtf16,

  /// 根本不是 CSV：xlsx（zip 包装）、PDF、二进制等
  notCsv,

  /// 找不到表头（不是账单文件，或格式完全不同）
  header,

  /// 文件里没有任何可导入的行
  empty,
}

/// 解码成功时识别出的编码。
///
/// 过目页顶部会显示它 —— 对用户是「文件被认出来了」，不是黑箱；
/// 对真机验证是数据来源：跑几份真实账单就知道到底多少份是 GBK。
enum BillEncoding {
  utf8('UTF-8'),
  utf8Bom('UTF-8（带 BOM）'),
  utf16Le('UTF-16 LE'),
  utf16Be('UTF-16 BE');

  const BillEncoding(this.label);

  final String label;
}

class BillParseException implements Exception {
  BillParseException(this.error, this.message);

  final BillParseError error;
  final String message;

  @override
  String toString() => message;
}

/// 一行账单。
///
/// [include] 与 [suspectedDuplicate] 是**给用户看的两个状态**，解析层只负责
/// 给出「建议值」，最终算不算入由用户在预览页决定 —— 这是「算入权」的落点：
/// 系统可以建议，但不能替用户决定。
class BillRow {
  BillRow({
    required this.lineNo,
    required this.date,
    required this.time,
    required this.amountCents,
    required this.type,
    required this.counterparty,
    required this.note,
    required this.payMethod,
    required this.rawAmount,
    this.include = true,
    this.suspectedDuplicate = false,
    this.duplicateScore = 0,
    this.skipReason,
  });

  /// 源文件里的行号（含表头行），报错定位用
  final int lineNo;

  /// `YYYY-MM-DD`
  final String date;

  /// `HH:mm`，没有就是空串
  final String time;

  /// **永远是正数**；方向看 [type]
  final int amountCents;

  final TxnType type;

  /// 交易对方（商户 / 个人）
  final String counterparty;

  /// 商品说明 / 交易备注
  final String note;

  /// 收/付款方式（「余额宝」「招商银行储蓄卡(1234)」…）
  final String payMethod;

  /// 金额原文，解析失败时给用户看「到底是哪一格不对」
  final String rawAmount;

  /// 用户是否选择**算入**（导入）。
  bool include;

  /// 疑似与已有记录重复。只做提示，默认 [include] 仍为 true ——
  /// 误判成重复而默认排除，用户会丢一笔真账且很难发现。
  bool suspectedDuplicate;

  /// 重复打分，仅用于排序展示与文案（≥80 视为确定性重复）
  int duplicateScore;

  /// 非空表示这行在解析阶段就被排除了（附原因），不进预览的勾选列表
  final String? skipReason;

  bool get skipped => skipReason != null;

  /// 明细里显示的一句话：对方 + 商品说明
  String get summary {
    final parts = <String>[
      if (counterparty.isNotEmpty) counterparty,
      if (note.isNotEmpty) note,
    ];
    return parts.isEmpty ? '（无对方信息）' : parts.join(' · ');
  }
}

/// 解析产物。
class BillParseResult {
  BillParseResult({
    required this.rows,
    required this.source,
    required this.skippedLines,
    required this.headerLine,
    required this.encoding,
    this.warnings = const [],
  });

  /// 可导入的行（含 [BillRow.skipped] 为 true 的，UI 要展示「为什么跳过了」）
  final List<BillRow> rows;

  final BillSource source;

  /// 被跳过的行数（说明行、不计收支、已关闭交易…）
  final int skippedLines;

  /// 表头所在行号（从 1 开始）
  final int headerLine;

  /// 实际被识别成的编码。给过目页的状态行用。
  final BillEncoding encoding;

  /// 非致命提示（未知列、金额为空等），展示在预览页顶部
  final List<String> warnings;

  /// 真正可导入的行
  List<BillRow> get importable => rows.where((r) => !r.skipped).toList();

  int get expenseTotalCents => importable
      .where((r) => r.type == TxnType.expense)
      .fold(0, (s, r) => s + r.amountCents);

  int get incomeTotalCents => importable
      .where((r) => r.type == TxnType.income)
      .fold(0, (s, r) => s + r.amountCents);
}

/// 账单 CSV 解析器。全部静态纯函数，无状态。
abstract final class BillCsv {
  /// 表头关键词 → 逻辑列。用「包含」匹配而不是精确相等：
  /// 支付宝和微信的表头叫法不同，同一家在改版后也会变。
  static const _colDate = ['交易时间', '交易创建时间', '交易日期', '时间'];
  static const _colAmount = ['金额', '金额(元)', '金额（元）'];
  static const _colDir = ['收/支', '收支', '收/支类型'];
  static const _colCounterparty = ['交易对方', '对方', '商户名称'];
  static const _colNote = ['商品说明', '商品', '备注', '交易备注'];
  static const _colPayMethod = ['收/付款方式', '支付方式', '付款方式'];
  static const _colStatus = ['交易状态', '当前状态', '状态'];
  static const _colCategory = ['交易分类', '交易类型', '分类'];

  /// 这些状态的行不进账本：钱没真正发生，或者已经退回去了。
  static const _deadStatus = ['交易关闭', '已关闭', '已全额退款', '退款成功', '支付失败'];

  /// 解析字节流。
  ///
  /// 抛 [BillParseException] 的三种情况：编码、找不到表头、没有可导入行。
  static BillParseResult parse(List<int> bytes) {
    final (text, encoding) = _decode(bytes);
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) {
      throw BillParseException(BillParseError.empty, '这个文件是空的');
    }

    // --- 找表头：前 30 行里找同时含「金额」和时间字段的那一行 ---
    var headerIdx = -1;
    for (var i = 0; i < lines.length && i < 30; i++) {
      final line = lines[i];
      if (!line.contains(',')) continue;
      final hasAmount = _colAmount.any(line.contains);
      final hasDate = _colDate.any(line.contains);
      if (hasAmount && hasDate) {
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

    final header = _splitCsvLine(lines[headerIdx]);
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
      lines.take(headerIdx + 1).join('|'),
      header: header,
    );

    final rows = <BillRow>[];
    final warnings = <String>[];
    var skipped = 0;

    for (var i = headerIdx + 1; i < lines.length; i++) {
      final raw = lines[i];
      if (raw.trim().isEmpty) continue;

      final cells = _splitCsvLine(raw);
      // 表头在文件里重复出现（支付宝分月导出会这样）
      if (_findCol(cells, _colAmount) >= 0 && _findCol(cells, _colDate) >= 0) {
        continue;
      }

      final amountRaw = _cell(cells, idxAmount);
      final dateRaw = _cell(cells, idxDate);
      final dirRaw = _cell(cells, idxDir);
      final statusRaw = _cell(cells, idxStatus);

      // 说明行：金额和时间都不像数据
      final parsedAmount = parseAmount(amountRaw);
      final parsedDate = parseDate(dateRaw);
      if (parsedAmount == null || parsedDate == null) {
        skipped++;
        continue;
      }

      final lineNo = i + 1;

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

  /// 解码字节流，返回 (正文, 识别出的编码)。见文件头「编码」一节的取舍说明。
  static (String, BillEncoding) _decode(List<int> bytes) {
    // 必须在解码**之前**排掉已知的非 CSV 格式：xlsx 与 PDF 的文件头
    // 都是纯 ASCII，UTF-8 解码不会失败 —— 等失败再猜就永远猜不到它们。
    _rejectKnownFormats(bytes);

    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return (_utf8Strict(bytes.sublist(3)), BillEncoding.utf8Bom);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return (
        _decodeUtf16(bytes.sublist(2), littleEndian: true),
        BillEncoding.utf16Le,
      );
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return (
        _decodeUtf16(bytes.sublist(2), littleEndian: false),
        BillEncoding.utf16Be,
      );
    }
    return (_utf8Strict(bytes), BillEncoding.utf8);
  }

  /// 严格 UTF-8 解码：失败就抛**带诊断的错误**，绝不 `allowMalformed`。
  ///
  /// 为什么不做容错解码：Dart 没有内置 GBK 编解码，容错解出来的是一串
  /// 「锟斤拷」，而**乱码一旦写进账本就几乎挑不出来**。宁可明确失败，
  /// 让用户去转一次码 —— 失败是可恢复的，脏数据不是。
  static String _utf8Strict(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw _sniffEncoding(bytes);
    }
  }

  /// xlsx 是 zip 包装（`PK\x03\x04`），PDF 有 `%PDF` 头。
  ///
  /// 两者的文件头都是 ASCII，**能被 UTF-8 正常解码**，所以这一步必须在
  /// 解码之前做。等解码失败再去猜，永远猜不到 —— 解码根本不会失败。
  static void _rejectKnownFormats(List<int> bytes) {
    if (_startsWith(bytes, const [0x50, 0x4B, 0x03, 0x04]) ||
        _startsWith(bytes, const [0x50, 0x4B, 0x05, 0x06])) {
      throw BillParseException(
        BillParseError.notCsv,
        '这是一个 Excel 工作簿（.xlsx），不是 CSV 文件。\n'
        '请在 Excel / WPS 里点「另存为」，格式选「CSV UTF-8（逗号分隔）」，'
        '再把那个 .csv 拿过来导入。',
      );
    }
    if (_startsWith(bytes, const [0x25, 0x50, 0x44, 0x46])) {
      throw BillParseException(
        BillParseError.notCsv,
        '这是一个 PDF，不是 CSV。\n'
        '请导入支付宝 / 微信导出的 .csv 账单文件。',
      );
    }
  }

  /// 认一下「到底为什么解不了」，并给出**能照着做**的指引。
  ///
  /// 在 UTF-8 解码失败之后调用（已知格式已在 [_rejectKnownFormats] 排掉）。
  /// 因为合法 UTF-8 根本走不到这里，误判只可能发生在「GBK 被说成 UTF-16」
  /// 这类次要分支，不会把能读的文件判成坏文件。
  static BillParseException _sniffEncoding(List<int> bytes) {
    if (bytes.isEmpty) {
      return BillParseException(BillParseError.empty, '这个文件是空的');
    }

    // --- 含 0x00：无 BOM 的 UTF-16，或者干脆是二进制 ---
    final head = bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes;
    var zeros = 0;
    var evenZero = 0;
    for (var i = 0; i < head.length; i++) {
      if (head[i] == 0) {
        zeros++;
        if (i.isEven) evenZero++;
      }
    }
    if (zeros > 0) {
      // 判据是「零字节是否挤在同一侧」，不是「零字节多不多」：
      // UTF-16 里 ASCII 字符（数字、逗号、引号）的高字节恒为 0，
      // 必然全落在偶数位或全落在奇数位。GBK 与 UTF-8 的文本里没有 0x00。
      final lopsided = evenZero > zeros * 0.9 || evenZero < zeros * 0.1;
      if (lopsided && zeros >= 4) {
        return BillParseException(
          BillParseError.encodingUtf16,
          '这个文件像是 UTF-16 编码。\n'
          '请在 Excel / WPS 里另存为「CSV UTF-8（逗号分隔）」后再导入。',
        );
      }
      if (zeros > head.length ~/ 8) {
        return BillParseException(
          BillParseError.notCsv,
          '这个文件里有大量二进制内容，看起来不是 CSV。\n'
          '请确认选的是支付宝 / 微信导出的 .csv 账单。',
        );
      }
    }

    // --- GBK 特征：0x81–0xFE 引导 + 0x40–0xFE 尾随，成对出现 ---
    if (_looksLikeGbk(head)) {
      return BillParseException(
        BillParseError.encodingGbk,
        '这个文件是 GBK 编码（中文 Windows 与旧版支付宝导出常见），'
        'App 目前只读 UTF-8。\n\n'
        '【有电脑】用 Excel 或 WPS 打开 → 另存为 → 选'
        '「CSV UTF-8（逗号分隔）」→ 传回手机再导入。\n'
        '【只有手机】暂时没有可靠办法在手机上转码。可以试试在支付宝里'
        '重新导出，看有没有 UTF-8 选项。\n\n'
        '这不会影响你已经导入的记录，也不会改动任何余额。\n'
        '—— 我们不硬解，因为乱码一旦写进账本就很难挑出来了。',
      );
    }

    return BillParseException(
      BillParseError.encoding,
      '这个文件不是 UTF-8 编码，App 目前只读 UTF-8 / UTF-16。\n'
      '请用 Excel / WPS 另存为「CSV UTF-8（逗号分隔）」后再导入。\n'
      '—— 我们不硬解，因为乱码一旦写进账本就很难挑出来了。',
    );
  }

  /// GBK 双字节特征：引导字节 0x81–0xFE，尾随字节 0x40–0xFE（不含 0x7F）。
  ///
  /// 只看比例不要求 100% —— 账单里混着 ASCII（数字、逗号、引号）是正常的。
  static bool _looksLikeGbk(List<int> b) {
    var pairs = 0;
    var leaders = 0;
    var i = 0;
    while (i < b.length) {
      final cur = b[i];
      if (cur < 0x80) {
        i++;
        continue;
      }
      leaders++;
      if (cur <= 0xFE && i + 1 < b.length) {
        final next = b[i + 1];
        if (next >= 0x40 && next <= 0xFE && next != 0x7F) {
          pairs++;
          i += 2;
          continue;
        }
      }
      i++;
    }
    return leaders > 0 && pairs * 2 >= leaders;
  }

  static bool _startsWith(List<int> b, List<int> prefix) {
    if (b.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (b[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _decodeUtf16(List<int> b, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      units.add(
        littleEndian ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]),
      );
    }
    return String.fromCharCodes(units);
  }

  // ------------------------------------------------------------------ 字段

  static BillSource _detectSource(String preamble, {List<String>? header}) {
    final joined = '$preamble|${header?.join('|') ?? ''}';
    if (joined.contains('支付宝')) return BillSource.alipay;
    if (joined.contains('微信')) return BillSource.wechat;
    return BillSource.unknown;
  }

  static int _findCol(List<String> header, List<String> keys) {
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

  static String _cell(List<String> cells, int idx) {
    if (idx < 0 || idx >= cells.length) return '';
    return cells[idx].trim().replaceAll('"', '');
  }

  /// 金额解析：`¥32.00` / `-32.00` / `1,234.56` / `32.00元` 都要能认。
  ///
  /// 返回**带符号**的分值；认不出来返回 null（调用方据此判为说明行）。
  static int? parseAmount(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll('¥', '').replaceAll('￥', '').replaceAll('元', '');
    s = s.replaceAll(',', '').replaceAll(' ', '');
    if (s.isEmpty) return null;
    final neg = s.startsWith('-');
    if (neg || s.startsWith('+')) s = s.substring(1);
    if (s.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;
    final dot = s.indexOf('.');
    int cents;
    if (dot < 0) {
      cents = int.parse(s) * 100;
    } else {
      final yuan = int.parse(s.substring(0, dot));
      final fracStr = s.substring(dot + 1).padRight(2, '0');
      cents = yuan * 100 + int.parse(fracStr);
    }
    return neg ? -cents : cents;
  }

  /// 日期解析：`2026-10-01 12:30:00` / `2026/10/1` / `2026-10-01`。
  static (String, String)? parseDate(String raw) {
    var s = raw.trim().replaceAll('"', '');
    if (s.isEmpty) return null;
    s = s.replaceAll('/', '-');
    final m = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?',
    ).firstMatch(s);
    if (m == null) return null;
    final y = m.group(1)!;
    final mo = m.group(2)!.padLeft(2, '0');
    final d = m.group(3)!.padLeft(2, '0');
    final date = '$y-$mo-$d';
    final hh = m.group(4);
    final mm = m.group(5);
    final time = hh == null ? '' : '${hh.padLeft(2, '0')}:$mm';
    return (date, time);
  }

  /// 方向：优先看「收/支」列，其次看金额符号。
  static TxnType _resolveType(String dirRaw, int signedAmount) {
    if (dirRaw.contains('支出') || dirRaw.contains('付款')) {
      return TxnType.expense;
    }
    if (dirRaw.contains('收入') || dirRaw.contains('收款')) return TxnType.income;
    return signedAmount < 0 ? TxnType.expense : TxnType.income;
  }

  /// 简易 CSV 行拆分：支持双引号包裹与引号内逗号 / 换行。
  ///
  /// 没有引 csv 包（见 pubspec 的「零新依赖」约定），但账单里的
  /// 「商品说明」经常带逗号，所以必须处理引号，不能直接 `split(',')`。
  static List<String> _splitCsvLine(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (ch == ',' && !inQuote) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString());
    return out;
  }

  // ------------------------------------------------------------- 重复判定

  /// 给每行和已有记录打分，标出「疑似重复」。
  ///
  /// ## 为什么不是「金额相等就算重复」
  ///
  /// 每天一杯 32 元的咖啡、每周一次 50 元的停车费 —— 金额天然会重复。
  /// 单靠金额判重，会把正常消费误判成重复账，而**误判的代价是不对称的**：
  /// 少导入一笔，用户丢的是钱；多导入一笔，用户随手删掉就行。
  ///
  /// 所以这里用多维打分，并且**默认不排除**（只标黄提示）。
  ///
  /// 分档：[score] ≥ 80 视为确定性重复（金额完全相等 + 同日 + 同方向），
  /// 55–79 视为疑似，其余不打标。
  static void markDuplicates(List<BillRow> rows, List<Txn> existing) {
    if (existing.isEmpty) return;

    // 按金额分桶：个人账本几千条，线性扫也够快，但分桶能让「同金额」先聚起来
    final byAmount = <int, List<Txn>>{};
    for (final t in existing) {
      byAmount.putIfAbsent(t.amountCents, () => []).add(t);
    }

    for (final r in rows) {
      if (r.skipped) continue;
      var best = 0;
      final candidates = <Txn>[
        ...?byAmount[r.amountCents],
        // 差 1 元以内也算候选（账单四舍五入 / 手续费）
        for (final e in byAmount.entries)
          if ((e.key - r.amountCents).abs() <= 100) ...e.value,
      ];
      for (final t in candidates) {
        var score = 0;
        if (t.amountCents == r.amountCents) {
          score += 40;
        } else if ((t.amountCents - r.amountCents).abs() <= 100) {
          score += 20;
        }
        if (t.date == r.date) {
          score += 30;
        } else if (_dayGap(t.date, r.date) <= 1) {
          score += 20;
        }
        if (t.type == r.type) score += 10;
        if (t.accountId != null) score += 0; // 账户要等用户选定后才有意义
        final noteHit = r.counterparty.isNotEmpty &&
            t.note.isNotEmpty &&
            (t.note.contains(r.counterparty) || r.note.contains(t.note));
        if (noteHit) score += 10;
        if (score > best) best = score;
      }
      r.duplicateScore = best;
      // ≥80 才算「确定性重复」，且仍然只标黄 —— 是否排除由用户勾
      r.suspectedDuplicate = best >= 55;
    }
  }

  static int _dayGap(String a, String b) {
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) return 999;
    return da.difference(db).inDays.abs();
  }
}
