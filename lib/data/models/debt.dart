import '../../core/local_date.dart';
import 'models.dart';

/// 一笔借贷往来（本金）。
///
/// ★ `repaid_cents` **不落库**：已还金额每次按 `txn.debt_id` 现算（[RepaidIndex]）。
///   存成字段迟早就和流水对不上，而「还剩多少」正是这套功能最核心的数字。
class Debt {
  const Debt({
    this.id,
    this.ledgerId = 0,
    required this.direction,
    required this.counterparty,
    required this.amountCents,
    this.accountId,
    required this.date,
    this.dueDate,
    this.countInBudget = false,
    this.closedAt,
    this.note = '',
    required this.createdAt,
  });

  final int? id;
  final int ledgerId;
  final DebtDirection direction;

  /// 对方（已 trim；空名字在分组时归到「未填对方」而不是丢弃）。
  final String counterparty;

  /// 本金，**必须 > 0**（DDL 有 CHECK）。
  final int amountCents;

  final int? accountId;

  /// 借出/借入发生日。
  final LocalDate date;

  /// 约定还款日，可空。
  final LocalDate? dueDate;

  /// 借入是否算进本期预算的「可用额度」。**借出恒为 false**（数据层强改）。
  final bool countInBudget;

  /// 结清时间；null = 未结清。
  final DateTime? closedAt;

  final String note;
  final DateTime createdAt;

  bool get isClosed => closedAt != null;

  /// 借出 = 应收。
  bool get isReceivable => direction.isReceivable;

  /// 已还（按流水现算，不落库）。
  int repaidCents(RepaidIndex index) => index.repaidFor(this);

  /// 剩余。**`clamp(0, 本金)`**：多还 100 显示 0，不是 −100。
  int remainingCents(RepaidIndex index) {
    if (isClosed) return 0;
    final int left = amountCents - repaidCents(index);
    if (left <= 0) return 0;
    return left > amountCents ? amountCents : left;
  }

  /// 逾期天数：未结清 + 有应还日 + 今天已过应还日 → 天数；否则 null。
  int? overdueDays({LocalDate? today}) {
    final LocalDate? due = dueDate;
    if (isClosed || due == null) return null;
    final LocalDate now = today ?? LocalDate.today();
    if (now <= due) return null;
    return now.diffDays(due);
  }

  Debt copyWith({    int? id,
    int? ledgerId,
    DebtDirection? direction,
    String? counterparty,
    int? amountCents,
    Object? accountId = kUnset,
    LocalDate? date,
    Object? dueDate = kUnset,
    bool? countInBudget,
    Object? closedAt = kUnset,
    String? note,
    DateTime? createdAt,
  }) {
    return Debt(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      direction: direction ?? this.direction,
      counterparty: counterparty ?? this.counterparty,
      amountCents: amountCents ?? this.amountCents,
      accountId: accountId == kUnset ? this.accountId : accountId as int?,
      date: date ?? this.date,
      dueDate: dueDate == kUnset ? this.dueDate : dueDate as LocalDate?,
      countInBudget: countInBudget ?? this.countInBudget,
      closedAt: closedAt == kUnset ? this.closedAt : closedAt as DateTime?,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 覆盖 DDL 全部 12 列。
  Map<String, Object?> toMap() => <String, Object?>{
    DebtCols.id: id,
    DebtCols.ledgerId: ledgerId,
    DebtCols.direction: direction.code,
    DebtCols.counterparty: counterparty.trim(),
    DebtCols.amountCents: amountCents,
    DebtCols.accountId: accountId,
    DebtCols.date: date.iso,
    DebtCols.dueDate: dueDate?.iso,
    DebtCols.countInBudget: boolToInt(countInBudget),
    DebtCols.closedAt: closedAt?.toIso8601String(),
    DebtCols.note: note,
    DebtCols.createdAt: createdAt.toIso8601String(),
  };

  factory Debt.fromMap(Map<String, Object?> m) => Debt(
    id: asIntOrNull(m[DebtCols.id]),
    ledgerId: asInt(m[DebtCols.ledgerId]),
    direction: DebtDirection.parseOrOut(asStringOrNull(m[DebtCols.direction])),
    counterparty: asString(m[DebtCols.counterparty]),
    amountCents: asInt(m[DebtCols.amountCents]),
    accountId: asIntOrNull(m[DebtCols.accountId]),
    date: LocalDate.tryParse(asString(m[DebtCols.date])) ??
        LocalDate.fromDateTime(DateTime(1970)),
    dueDate: LocalDate.tryParse(asString(m[DebtCols.dueDate])),
    countInBudget: asBool(m[DebtCols.countInBudget]),
    closedAt: asDateTimeOrNull(m[DebtCols.closedAt]),
    note: asString(m[DebtCols.note]),
    createdAt: asDateTimeOrNull(m[DebtCols.createdAt]) ?? DateTime(1970),
  );

  @override
  String toString() =>
      'Debt(#$id ${direction.code} $counterparty $amountCents closed=$isClosed)';
}

/// 「每笔债已还多少」的内存索引。
///
/// 口径：本金流水与还款流水**都**挂 `debt_id`，靠 `type` 区分 ——
/// - 借出（`out`）：本金是 `expense`，还款是 `income` → 已还 = Σ`income`
/// - 借入（`in`）：本金是 `income`，还款是 `expense` → 已还 = Σ`expense`
///
/// 一次查回全部相关流水、循环里算完，避免「每笔债一条 SQL」（往来页 10 笔就是 10 次查询）。
class RepaidIndex {
  const RepaidIndex._(this._incomeByDebt, this._expenseByDebt);

  static const RepaidIndex empty = RepaidIndex._(
    <int, int>{},
    <int, int>{},
  );

  factory RepaidIndex.fromTxns(Iterable<Txn> txns) {
    final Map<int, int> income = <int, int>{};
    final Map<int, int> expense = <int, int>{};
    for (final Txn t in txns) {
      final int? debtId = t.debtId;
      if (debtId == null) continue;
      if (t.type.isIncome) {
        income[debtId] = (income[debtId] ?? 0) + t.amountCents;
      } else if (t.type.isExpense) {
        expense[debtId] = (expense[debtId] ?? 0) + t.amountCents;
      }
    }
    return RepaidIndex._(income, expense);
  }

  final Map<int, int> _incomeByDebt;
  final Map<int, int> _expenseByDebt;

  /// 从 SQL 聚合好的两张表构造（repo 层用一条 GROUP BY 查回来，
  /// 避免把整本账的流水都读进内存）。
  factory RepaidIndex.fromSums({
    Map<int, int> income = const <int, int>{},
    Map<int, int> expense = const <int, int>{},
  }) => RepaidIndex._(income, expense);

  /// 这笔债已还多少（按方向取对应一侧的合计）。
  int repaidFor(Debt debt) {
    final int id = debt.id ?? -1;
    final int sum = debt.direction.isReceivable
        ? (_incomeByDebt[id] ?? 0)
        : (_expenseByDebt[id] ?? 0);
    return sum < 0 ? 0 : sum;
  }

  int repaidForId(int debtId, {required bool receivable}) {
    final int sum = receivable
        ? (_incomeByDebt[debtId] ?? 0)
        : (_expenseByDebt[debtId] ?? 0);
    return sum < 0 ? 0 : sum;
  }

  bool get isEmpty => _incomeByDebt.isEmpty && _expenseByDebt.isEmpty;
}
