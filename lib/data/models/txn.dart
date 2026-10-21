import '../../core/local_date.dart';
import 'models.dart';

/// 一笔流水。
///
/// ★ [amountCents] **允许为负**：负数是净额记账（方向反了），不是「金额少了」。
///   所以任何地方都不许 `ABS`，聚合口径见 [TxnSum.bySide]。
/// ★ [periodStart] 是派生值：由 `Period.periodStartOf` 现算，`copyWith` 改了
///   [date] 之后就把它置 null，等 Repo 重算（原版 `Txn.toMap()` 故意不含它）。
/// ★ [debtId] 非空 = 借贷流水，所有金额聚合都要排除（口径 3.5）。
class Txn {
  const Txn({
    this.id,
    this.ledgerId = 0,
    required this.type,
    required this.amountCents,
    this.categoryId,
    this.accountId,
    this.toAccountId,
    required this.date,
    this.periodStart,
    this.note = '',
    this.placeFrom,
    this.placeTo,
    this.person,
    this.subject,
    this.debtId,
    this.templateId,
    this.recurringId,
    required this.createdAt,
  });

  final int? id;
  final int ledgerId;
  final TxnType type;

  /// 单位分。正数 = 正常方向；负数 = 方向反了（净额记账）。
  final int amountCents;

  final int? categoryId;
  final int? accountId;
  final int? toAccountId;

  /// 业务日期（真实发生日），`YYYY-MM-DD`。
  final LocalDate date;

  /// 归属期的第一天。**落库 NOT NULL**，由 Repo 现算。
  final LocalDate? periodStart;

  final String note;

  /// 四个详情字段（挂子分类，全部选填；空串一律落 NULL）。
  final String? placeFrom;
  final String? placeTo;
  final String? person;
  final String? subject;

  /// 非空 = 借贷本金或还款流水（金额聚合一律跳过）。
  final int? debtId;

  final int? templateId;
  final int? recurringId;
  final DateTime createdAt;

  /// 借贷流水（不参与支出/收入聚合）。
  bool get isDebt => debtId != null;

  /// 周期账单补记出来的（明细行上的灰色「周期」小标签）。
  bool get isFromRecurring => recurringId != null;

  /// 转账的对面账户。
  bool get isTransfer => type.isTransfer;

  /// 金额的显示值（借出/借入按方向带符号，方便列表统一渲染）。
  int get signedAmountCents => type.isIncome ? amountCents : -amountCents;

  /// 覆盖 DDL 全部 18 列（`id` 为 null 表示自增）。
  ///
  /// 空串归一成 `null`：不清成 null 的话，「填过又删掉」和「从来没填」在库里
  /// 长成两种样子，按字段筛「有对象的记录」就会漏一半。
  Map<String, Object?> toMap() => <String, Object?>{
    TxnCols.id: id,
    TxnCols.ledgerId: ledgerId,
    TxnCols.type: type.code,
    TxnCols.amountCents: amountCents,
    TxnCols.categoryId: categoryId,
    TxnCols.accountId: accountId,
    TxnCols.toAccountId: toAccountId,
    TxnCols.date: date.iso,
    TxnCols.periodStart: periodStart?.iso,
    TxnCols.note: note,
    TxnCols.placeFrom: _nz(placeFrom),
    TxnCols.placeTo: _nz(placeTo),
    TxnCols.person: _nz(person),
    TxnCols.subject: _nz(subject),
    TxnCols.debtId: debtId,
    TxnCols.templateId: templateId,
    TxnCols.recurringId: recurringId,
    TxnCols.createdAt: createdAt.toIso8601String(),
  };

  static String? _nz(String? v) {
    final String t = (v ?? '').trim();
    return t.isEmpty ? null : t;
  }

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
    id: asIntOrNull(m[TxnCols.id]),
    ledgerId: asInt(m[TxnCols.ledgerId]),
    type: TxnType.parseOrExpense(asStringOrNull(m[TxnCols.type])),
    amountCents: asInt(m[TxnCols.amountCents]),
    categoryId: asIntOrNull(m[TxnCols.categoryId]),
    accountId: asIntOrNull(m[TxnCols.accountId]),
    toAccountId: asIntOrNull(m[TxnCols.toAccountId]),
    date: LocalDate.tryParse(asString(m[TxnCols.date])) ??
        LocalDate.fromDateTime(DateTime(1970)),
    periodStart: LocalDate.tryParse(asString(m[TxnCols.periodStart])),
    note: asString(m[TxnCols.note]),
    placeFrom: asStringOrNull(m[TxnCols.placeFrom]),
    placeTo: asStringOrNull(m[TxnCols.placeTo]),
    person: asStringOrNull(m[TxnCols.person]),
    subject: asStringOrNull(m[TxnCols.subject]),
    debtId: asIntOrNull(m[TxnCols.debtId]),
    templateId: asIntOrNull(m[TxnCols.templateId]),
    recurringId: asIntOrNull(m[TxnCols.recurringId]),
    createdAt: asDateTimeOrNull(m[TxnCols.createdAt]) ?? DateTime(1970),
  );

  /// 改字段。可空外键用 [kUnset] 区分「没传」与「显式清空」。
  ///
  /// ★ 改了 [date] 且没有显式给 `periodStart` → 新的 `periodStart` 变 **null**，
  ///   表示「旧的归属期不再成立，等 Repo 用新日期重算」。这是刻意的：
  ///   直接沿用旧值会让一笔改过日期的流水留在错的那一期里。
  Txn copyWith({
    int? id,
    int? ledgerId,
    TxnType? type,
    int? amountCents,
    Object? categoryId = kUnset,
    Object? accountId = kUnset,
    Object? toAccountId = kUnset,
    LocalDate? date,
    Object? periodStart = kUnset,
    String? note,
    Object? placeFrom = kUnset,
    Object? placeTo = kUnset,
    Object? person = kUnset,
    Object? subject = kUnset,
    Object? debtId = kUnset,
    Object? templateId = kUnset,
    Object? recurringId = kUnset,
    DateTime? createdAt,
  }) {
    final LocalDate? newPeriodStart = periodStart == kUnset
        ? (date == null ? this.periodStart : null)
        : periodStart as LocalDate?;
    return Txn(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      categoryId: categoryId == kUnset ? this.categoryId : categoryId as int?,
      accountId: accountId == kUnset ? this.accountId : accountId as int?,
      toAccountId:
          toAccountId == kUnset ? this.toAccountId : toAccountId as int?,
      date: date ?? this.date,
      periodStart: newPeriodStart,
      note: note ?? this.note,
      placeFrom: placeFrom == kUnset ? this.placeFrom : placeFrom as String?,
      placeTo: placeTo == kUnset ? this.placeTo : placeTo as String?,
      person: person == kUnset ? this.person : person as String?,
      subject: subject == kUnset ? this.subject : subject as String?,
      debtId: debtId == kUnset ? this.debtId : debtId as int?,
      templateId: templateId == kUnset ? this.templateId : templateId as int?,
      recurringId:
          recurringId == kUnset ? this.recurringId : recurringId as int?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 详情四字段的 map 视图（录入面板与 `pruneDetails` 共用）。
  Map<TxnField, String> get detailFields => <TxnField, String>{
    TxnField.from: placeFrom ?? '',
    TxnField.to: placeTo ?? '',
    TxnField.person: person ?? '',
    TxnField.subject: subject ?? '',
  };

  @override
  String toString() =>
      'Txn(#$id ${type.code} $amountCents ${date.iso} cat=$categoryId debt=$debtId)';
}

/// 合计口径（**内存侧**，与 SQL 侧的 `expSum`/`incSum` 必须逐字同口径）。
///
/// 六处必须一致（口径 3.15）：月度合计、筛选合计、饼图/排行、每日趋势、
/// 预算已用、内存侧 [TxnSum.bySide]。少一处，「分项之和 ≠ 合计」。
abstract final class TxnSum {
  /// 某一侧的合计，口径是**交叉归集**：
  /// 支出里记的负数算进收入，收入里记的负数算进支出；转账与借贷都不参与。
  ///
  /// 语义是「这笔钱的方向反了，不是这一侧变少了」：代购代付后对方多给 20，
  /// 记成支出 −20，统计上应该体现为收入多了 20。
  static int bySide(Iterable<Txn> txns, TxnType side) {
    if (side.isTransfer) return 0;
    int sum = 0;
    for (final Txn t in txns) {
      if (t.type.isTransfer) continue;
      // 借贷流水不是收支：借出去的钱不是消费，收回来的也不是收入
      if (t.debtId != null) continue;
      final bool sameSide = t.type == side;
      if (sameSide ? t.amountCents >= 0 : t.amountCents < 0) {
        sum += t.amountCents.abs();
      }
    }
    return sum;
  }

  /// 两侧 + 笔数。笔数**含**借贷流水（用户要在列表里看到它，只是不算金额）。
  static RangeTotals totals(Iterable<Txn> txns) {
    final List<Txn> list = txns is List<Txn> ? txns : txns.toList();
    return RangeTotals(
      expenseCents: bySide(list, TxnType.expense),
      incomeCents: bySide(list, TxnType.income),
      count: list.length,
    );
  }
}
