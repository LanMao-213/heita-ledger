import 'models.dart';

/// 账户。
///
/// ★ 双列余额（口径 3.4）：
/// - [openingCents] 是**基准**：只有「用户在账户管理里手填当前余额」时才改
///   （反算 `opening = 手填 − 流水合计`）。任何自动流程都不许改它，否则
///   「余额对不对」永远无法判定（原版单列 `balance` 的病因）。
/// - [balanceCents] 是 `opening + 该账户流水合计`，由 `applyBalanceDelta` 增量维护。
class Account {
  const Account({
    this.id,
    required this.name,
    this.kind = AccountKind.cash,
    this.openingCents = 0,
    this.balanceCents = 0,
    this.includeInTotal = true,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final AccountKind kind;
  final int openingCents;
  final int balanceCents;
  final bool includeInTotal;
  final int sortOrder;

  /// 某类流水对余额的**方向符号**：收入 `+1`、支出 `−1`、转账 `0`。
  ///
  /// 转账两端各自处理（转出 −、转入 +），所以这里返回 0，不要拿它算转账。
  static int flowSign(TxnType type) {
    if (type.isIncome) return 1;
    if (type.isTransfer) return 0;
    return -1;
  }

  /// 一条流水对本账户余额的增量（转账请用 `transferDelta`）。
  ///
  /// **不做 `ABS`**：`amountCents` 允许为负（净额记账，方向反了），
  /// 取绝对值会把「退款 20」记成「又花了 20」。
  int deltaFor(TxnType type, int amountCents) => flowSign(type) * amountCents;

  /// 按恒等式算出来的应有余额（体检用）：`opening + Σ流水影响`。
  int expectedBalanceCents(int flowDeltaCents) => openingCents + flowDeltaCents;

  /// 余额是否与恒等式一致。
  bool matchesIdentity(int flowDeltaCents) =>
      balanceCents == expectedBalanceCents(flowDeltaCents);

  Account copyWith({
    int? id,
    String? name,
    AccountKind? kind,
    int? openingCents,
    int? balanceCents,
    bool? includeInTotal,
    int? sortOrder,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      openingCents: openingCents ?? this.openingCents,
      balanceCents: balanceCents ?? this.balanceCents,
      includeInTotal: includeInTotal ?? this.includeInTotal,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// 覆盖 DDL 全部 7 列。
  ///
  /// ★ 改账户属性（名称/类型/计入净资产）时，调用方**必须**先
  /// `copyWith(...).withoutBalances()`，否则会顺手把余额写回去 ——
  /// 1.4.5 真机上就是栽在这里（微信账面 1744、按流水 −3256）。
  Map<String, Object?> toMap() => <String, Object?>{
    AccountCols.id: id,
    AccountCols.name: name,
    AccountCols.kind: kind.code,
    AccountCols.openingCents: openingCents,
    AccountCols.balanceCents: balanceCents,
    AccountCols.includeInTotal: boolToInt(includeInTotal),
    AccountCols.sortOrder: sortOrder,
  };

  /// 只保留「用户可改的属性」，把两列余额从 map 里摘掉。
  ///
  /// `updateAccount` 用它 —— `UPDATE` 语料里不出现 `opening_cents` /
  /// `balance_cents`，就不可能误改（比「记得别写」可靠）。
  Map<String, Object?> attributesOnly() {
    final Map<String, Object?> m = toMap();
    m.remove(AccountCols.openingCents);
    m.remove(AccountCols.balanceCents);
    return m;
  }

  factory Account.fromMap(Map<String, Object?> m) => Account(
    id: asIntOrNull(m[AccountCols.id]),
    name: asString(m[AccountCols.name]),
    kind: AccountKind.parseOrOther(asStringOrNull(m[AccountCols.kind])),
    openingCents: asInt(m[AccountCols.openingCents]),
    balanceCents: asInt(m[AccountCols.balanceCents]),
    includeInTotal: asBool(m[AccountCols.includeInTotal], fallback: true),
    sortOrder: asInt(m[AccountCols.sortOrder]),
  );

  @override
  String toString() => 'Account(#$id $name ${kind.code} $balanceCents)';
}
