import '../../core/local_date.dart';
import 'models.dart';

/// 周期账单规则。
///
/// `interval` / `end_date` 在原版是「有列无入口」的半套字段；新库补齐表单控件，
/// 所以这两列**必须真实生效**（[advanceDate] 与 [isDue] 都看它们）。
class Recurring {
  const Recurring({
    this.id,
    this.ledgerId = 0,
    required this.type,
    required this.amountCents,
    this.categoryId,
    this.accountId,
    this.note = '',
    this.freq = RecurFreq.monthly,
    this.interval = 1,
    required this.nextRunDate,
    this.endDate,
    this.enabled = true,
  });

  final int? id;
  final int ledgerId;
  final TxnType type;
  final int amountCents;
  final int? categoryId;
  final int? accountId;
  final String note;
  final RecurFreq freq;

  /// 间隔倍数（每月 = 1，每两月 = 2，最多 12）。
  final int interval;

  /// 下次该触发的日期。
  final LocalDate nextRunDate;

  /// 截止日（含）：`runDate > endDate` 就停。
  final LocalDate? endDate;

  final bool enabled;

  /// 这笔规则本应触发的日期是否已到（补记的判断条件）。
  bool isDue(LocalDate today) {
    if (!enabled) return false;
    if (nextRunDate > today) return false;
    final LocalDate? end = endDate;
    if (end != null && nextRunDate > end) return false;
    return true;
  }

  /// 下一次的日期。
  LocalDate nextAfter(LocalDate from) => advanceDate(from, freq, interval);

  /// 频率推进：**monthly 必须月末对齐**。
  ///
  /// `1-31 + 1 月 → 2-28/29`（而不是溢出到 3-03）：`LocalDate.addMonths` 内部
  /// 把日号收拢到目标月月末。`yearly` 走 `+12n 月`，同样保住「同月同日」并
  /// 把 2-29 在平年收拢到 2-28。
  static LocalDate advanceDate(LocalDate from, RecurFreq freq, int interval) {
    final int n = interval < 1 ? 1 : interval;
    switch (freq) {
      case RecurFreq.daily:
        return from.addDays(n);
      case RecurFreq.weekly:
        return from.addDays(7 * n);
      case RecurFreq.monthly:
        return from.addMonths(n);
      case RecurFreq.yearly:
        return from.addMonths(12 * n);
    }
  }

  Recurring copyWith({
    int? id,
    int? ledgerId,
    TxnType? type,
    int? amountCents,
    Object? categoryId = kUnset,
    Object? accountId = kUnset,
    String? note,
    RecurFreq? freq,
    int? interval,
    LocalDate? nextRunDate,
    Object? endDate = kUnset,
    bool? enabled,
  }) {
    return Recurring(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      categoryId: categoryId == kUnset ? this.categoryId : categoryId as int?,
      accountId: accountId == kUnset ? this.accountId : accountId as int?,
      note: note ?? this.note,
      freq: freq ?? this.freq,
      interval: interval ?? this.interval,
      nextRunDate: nextRunDate ?? this.nextRunDate,
      endDate: endDate == kUnset ? this.endDate : endDate as LocalDate?,
      enabled: enabled ?? this.enabled,
    );
  }

  /// 覆盖 DDL 全部 12 列。
  Map<String, Object?> toMap() => <String, Object?>{
    RecurringCols.id: id,
    RecurringCols.ledgerId: ledgerId,
    RecurringCols.type: type.code,
    RecurringCols.amountCents: amountCents,
    RecurringCols.categoryId: categoryId,
    RecurringCols.accountId: accountId,
    RecurringCols.note: note,
    RecurringCols.freq: freq.code,
    RecurringCols.interval: interval,
    RecurringCols.nextRunDate: nextRunDate.iso,
    RecurringCols.endDate: endDate?.iso,
    RecurringCols.enabled: boolToInt(enabled),
  };

  factory Recurring.fromMap(Map<String, Object?> m) => Recurring(
    id: asIntOrNull(m[RecurringCols.id]),
    ledgerId: asInt(m[RecurringCols.ledgerId]),
    type: TxnType.parseOrExpense(asStringOrNull(m[RecurringCols.type])),
    amountCents: asInt(m[RecurringCols.amountCents]),
    categoryId: asIntOrNull(m[RecurringCols.categoryId]),
    accountId: asIntOrNull(m[RecurringCols.accountId]),
    note: asString(m[RecurringCols.note]),
    freq: RecurFreq.parseOrMonthly(asStringOrNull(m[RecurringCols.freq])),
    interval: asInt(m[RecurringCols.interval], 1),
    nextRunDate:
        LocalDate.tryParse(asString(m[RecurringCols.nextRunDate])) ??
        LocalDate.fromDateTime(DateTime(1970)),
    endDate: LocalDate.tryParse(asString(m[RecurringCols.endDate])),
    enabled: asBool(m[RecurringCols.enabled], fallback: true),
  );

  @override
  String toString() =>
      'Recurring(#$id ${freq.code}/$interval next=${nextRunDate.iso} enabled=$enabled)';
}
