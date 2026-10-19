import 'models.dart';

/// 「某个人的未结清往来」汇总。
///
/// 用户要的是「谁欠我多少 / 我欠谁多少」，这个问题的主语是**人**，不是单笔借款。
/// 台账按笔列也能查到，但要先在心里把同一个人的几笔加起来 —— 那正是这个类要替他做的事。
///
/// 只汇总**未结清**的：已结清的钱不构成「欠」，混进来会让净额永远不为零。
class PersonDebts {
  PersonDebts(this.name, List<Debt> debts)
    : debts = List.unmodifiable(
        // 进详情要按时间顺序看：先借的在前，后面才是陆续还的
        [...debts]..sort((a, b) => a.date.compareTo(b.date)),
      );

  /// 对方名字（已 trim）。空名字归到「未填对方」一组，不丢弃。
  final String name;

  /// 这个人的未结清往来，按发生日正序
  final List<Debt> debts;

  int get count => debts.length;

  /// 这个人欠我多少（借出未还部分）
  int get receivableCents => debts
      .where((d) => d.direction.isReceivable)
      .fold(0, (a, d) => a + d.remainingCents);

  /// 我欠这个人多少（借入未还部分）
  int get payableCents => debts
      .where((d) => !d.direction.isReceivable)
      .fold(0, (a, d) => a + d.remainingCents);

  /// 净额：正数 = 对方净欠我，负数 = 我净欠对方。
  ///
  /// 同一个人既借又还的场面很常见（他借我 5000，我后来借他 2000），
  /// 两边分开报会让他看起来同时「欠我 5000」和「我欠他 2000」。
  int get netCents => receivableCents - payableCents;

  /// 既有借出又有借入 —— 界面上要提示净额是怎么来的
  bool get isMixed => receivableCents > 0 && payableCents > 0;

  /// 最近的一个还款日（`YYYY-MM-DD`）。都没约定返回 null。
  ///
  /// 字符串直接比大小：ISO 日期的字典序就是时间序，不用再解析。
  String? get nearestDue {
    String? min;
    for (final d in debts) {
      final due = d.dueDate;
      if (due == null || due.isEmpty) continue;
      if (min == null || due.compareTo(min) < 0) min = due;
    }
    return min;
  }

  /// 这个人的逾期天数：取最严重的那笔；没有逾期返回 null。
  int? get overdueDays {
    int? worst;
    for (final d in debts) {
      final o = d.overdueDays;
      if (o == null) continue;
      if (worst == null || o > worst) worst = o;
    }
    return worst;
  }

  bool get isOverdue => overdueDays != null;

  /// 只有一笔时，点进去就是那笔的详情，不必再套一层列表
  Debt? get single => count == 1 ? debts.first : null;
}

/// 按对方合并未结清往来，并排好显示顺序。
///
/// 排序规则（依次比较）：
/// 1. 有逾期的在前 —— 该催的排最上面，比按金额排更有用；
/// 2. 到期日近的在前，没约定日期的垫底（不是急事）；
/// 3. 净额大的在前 —— 同样都到期时，先看钱多的；
/// 4. 名字，保证顺序稳定（否则同一份数据每次打开顺序都可能变）。
List<PersonDebts> groupDebtsByCounterparty(Iterable<Debt> debts) {
  final buckets = <String, List<Debt>>{};
  for (final d in debts) {
    if (d.isClosed) continue;
    final raw = d.counterparty.trim();
    buckets.putIfAbsent(raw.isEmpty ? '未填对方' : raw, () => []).add(d);
  }

  final groups = [
    for (final e in buckets.entries) PersonDebts(e.key, e.value),
  ];

  groups.sort((a, b) {
    final ao = a.overdueDays, bo = b.overdueDays;
    if (ao != bo) {
      if (ao == null) return 1;
      if (bo == null) return -1;
      return bo.compareTo(ao); // 逾期更久的在前
    }
    final ad = a.nearestDue, bd = b.nearestDue;
    if (ad != bd) {
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }
    final byAmount = b.netCents.abs().compareTo(a.netCents.abs());
    if (byAmount != 0) return byAmount;
    return a.name.compareTo(b.name);
  });

  return groups;
}
