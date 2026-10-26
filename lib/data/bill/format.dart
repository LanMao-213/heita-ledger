part of '../bill_csv.dart';

// ---------------------------------------------------------------------------
// 列名关键词表与金额/时间识别
//
// 库私有（`part of` 与 `bill_csv.dart` 共享私有作用域）；对外只暴露
// `BillCsv.parse` / `parseAmount` / `parseDate` / `markDuplicates` 四个入口，
// 门面在 `bill_csv.dart` 里。
// ---------------------------------------------------------------------------

  /// 表头关键词 → 逻辑列。用「包含」匹配而不是精确相等：
  /// 支付宝和微信的表头叫法不同，同一家在改版后也会变。
const _colDate = ['交易时间', '交易创建时间', '交易日期', '时间'];

const _colAmount = ['金额', '金额(元)', '金额（元）'];

const _colDir = ['收/支', '收支', '收/支类型'];

const _colCounterparty = ['交易对方', '对方', '商户名称'];

const _colNote = ['商品说明', '商品', '备注', '交易备注'];

const _colPayMethod = ['收/付款方式', '支付方式', '付款方式'];

const _colStatus = ['交易状态', '当前状态', '状态'];

const _colCategory = ['交易分类', '交易类型', '分类'];

  /// 这些状态的行不进账本：钱没真正发生，或者已经退回去了。
const _deadStatus = ['交易关闭', '已关闭', '已全额退款', '退款成功', '支付失败'];

  /// 金额解析：`¥32.00` / `-32.00` / `1,234.56` / `32.00元` 都要能认。
  ///
  /// 返回**带符号**的分值；认不出来返回 null（调用方据此判为说明行）。
int? _parseAmount(String raw) {
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
(String, String)? _parseDate(String raw) {
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
