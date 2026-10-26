import 'category_seed.dart';

part 'models/fmt.dart';
part 'models/ledger.dart';
part 'models/txn.dart';
part 'models/plan.dart';
part 'models/stats.dart';

/// 空白字符串一律落库为 NULL。
///
/// 不清成 NULL 的话，「填过又删掉」和「从来没过」在库里长成两种样子
/// （空串 / NULL），后面按字段筛选「有对象的记录」就会漏掉一半。
String? _nz(String? v) {
  final t = (v ?? '').trim();
  return t.isEmpty ? null : t;
}
