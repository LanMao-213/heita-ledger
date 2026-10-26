part of '../bill_csv.dart';

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
    this.certainDuplicate = false,
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

  /// **确定性**重复：日 + 分 + 对方 三要素与库里某条记录完全相等（指纹级相同）。
  ///
  /// 与 [suspectedDuplicate] 的区别不是"更严重"，而是**判据不同**：
  /// - [suspectedDuplicate] 是模糊打分（≥55），怕误杀，所以默认保留；
  /// - 本标记是精确命中，且**命中即抵扣一条**（同一条库记录不会被两行同时认领），
  ///   所以可以为它翻转默认值：[include] 默认置 false。
  ///
  /// 典型场景：同一份账单被导两次 —— 第二次每一行都成为确定性重复，
  /// 默认全部不勾，用户一键完成"这次没有新账"。想强行再导一遍，
  /// 仍可手动勾回来（系统给建议，不替用户决定）。
  bool certainDuplicate;

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
