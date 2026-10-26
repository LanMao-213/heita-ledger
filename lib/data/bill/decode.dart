part of '../bill_csv.dart';

// ---------------------------------------------------------------------------
// 字节解码与编码嗅探
//
// 库私有（`part of` 与 `bill_csv.dart` 共享私有作用域）；对外只暴露
// `BillCsv.parse` / `parseAmount` / `parseDate` / `markDuplicates` 四个入口，
// 门面在 `bill_csv.dart` 里。
// ---------------------------------------------------------------------------

  /// 解码字节流，返回 (正文, 识别出的编码)。见文件头「编码」一节的取舍说明。
(String, BillEncoding) _decode(List<int> bytes) {
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
String _utf8Strict(List<int> bytes) {
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
void _rejectKnownFormats(List<int> bytes) {
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
BillParseException _sniffEncoding(List<int> bytes) {
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
bool _looksLikeGbk(List<int> b) {
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

bool _startsWith(List<int> b, List<int> prefix) {
  if (b.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (b[i] != prefix[i]) return false;
  }
  return true;
}

String _decodeUtf16(List<int> b, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < b.length; i += 2) {
    units.add(
      littleEndian ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]),
    );
  }
  return String.fromCharCodes(units);
}

// ------------------------------------------------------------------ 字段
