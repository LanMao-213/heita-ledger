import '../../core/local_date.dart';
import '../models/debt.dart';

/// 「某个人的未结清往来」汇总。
///
/// 用户要的是「谁欠我多少 / 我欠谁多少」，这个问题的主语是**人**，不是单笔借款。
/// 台账按笔列也能查到，但要先在心里把同一个人的几笔加起来 —— 那正是这个类替用户做的事。
///
/// 只汇总**未结清**的：已结清的钱不构成「欠」，混进来会让净额永远不为零。
class PersonDebts {
  PersonDebts(this.name, List<Debt> debts)
    : debts = List<Debt>.unmodifiable(
        // 进详情要按时间顺序看：先借的在前，后面才是陆续还的
        <Debt>[...debts]..sort((Debt a, Debt b) => a.date.compareTo(b.date)),
      );

  /// 对方名字（已 trim）。空名字归到「未填对方」一组，**不丢弃**。
  final String name;

  /// 这个人的未结清往来，按发生日正序。
  final List<Debt> debts;

  int get count => debts.length;

  /// 这个人欠我多少（借出未还部分）。
  int receivableCents(RepaidIndex index) {
    int sum = 0;
    for (final Debt d in debts) {
      if (!d.isReceivable) continue;
      sum += d.remainingCents(index);
    }
    return sum;
  }

  /// 我欠这个人多少（借入未还部分）。
  int payableCents(RepaidIndex index) {
    int sum = 0;
    for (final Debt d in debts) {
      if (d.isReceivable) continue;
      sum += d.remainingCents(index);
    }
    return sum;
  }

  /// 净额：正数 = 对方净欠我，负数 = 我净欠对方。
  ///
  /// 同一个人既借又还的场面很常见（他借我 5000，我后来借他 2000），
  /// 两边分开报会让他看起来同时「欠我 5000」和「我欠他 2000」。
  int netCents(RepaidIndex index) =>
      receivableCents(index) - payableCents(index);

  /// 既有借出又有借入 —— 界面上要提示净额是怎么来的（副行写「借出 X · 借入 Y」）。
  bool isMixed(RepaidIndex index) =>
      receivableCents(index) > 0 && payableCents(index) > 0;

  /// 最近的一个应还日；都没约定返回 `null`。日期本身可比较，不用转字符串。
  LocalDate? get nearestDue {
    LocalDate? min;
    for (final Debt d in debts) {
      final LocalDate? due = d.dueDate;
      if (due == null) continue;
      if (min == null || due < min) min = due;
    }
    return min;
  }

  /// 这个人的逾期天数：取最严重的那笔；没有逾期返回 `null`。
  int? overdueDays({LocalDate? today}) {
    int? worst;
    for (final Debt d in debts) {
      final int? o = d.overdueDays(today: today);
      if (o == null) continue;
      if (worst == null || o > worst) worst = o;
    }
    return worst;
  }

  bool isOverdue({LocalDate? today}) => overdueDays(today: today) != null;

  /// 只有一笔时，点进去就是那笔的详情，不必再套一层列表。
  Debt? get single => count == 1 ? debts.first : null;
}

/// 按对方合并未结清往来，并排好显示顺序。
///
/// 排序规则（依次比较）：
/// 1. 有逾期的在前 —— 该催的排最上面，比按金额排更有用；
/// 2. 应还日近的在前，没约定日期的垫底（不是急事）；
/// 3. 净额绝对值大的在前 —— 同样都到期时，先看钱多的；
/// 4. 名字，保证顺序稳定（否则同一份数据每次打开顺序都可能变）。
List<PersonDebts> groupDebtsByCounterparty(
  Iterable<Debt> debts, {
  RepaidIndex? repaid,
  LocalDate? today,
}) {
  final RepaidIndex index = repaid ?? RepaidIndex.empty;
  final Map<String, List<Debt>> buckets = <String, List<Debt>>{};
  for (final Debt d in debts) {
    if (d.isClosed) continue;
    final String raw = d.counterparty.trim();
    buckets.putIfAbsent(raw.isEmpty ? '未填对方' : raw, () => <Debt>[]).add(d);
  }

  final List<PersonDebts> groups = <PersonDebts>[
    for (final MapEntry<String, List<Debt>> e in buckets.entries)
      PersonDebts(e.key, e.value),
  ];

  groups.sort((PersonDebts a, PersonDebts b) {
    final int? ao = a.overdueDays(today: today);
    final int? bo = b.overdueDays(today: today);
    if (ao != bo) {
      if (ao == null) return 1;
      if (bo == null) return -1;
      return bo.compareTo(ao); // 逾期更久的在前
    }
    final LocalDate? ad = a.nearestDue;
    final LocalDate? bd = b.nearestDue;
    if (ad != bd) {
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }
    final int byAmount =
        b.netCents(index).abs().compareTo(a.netCents(index).abs());
    if (byAmount != 0) return byAmount;
    return a.name.compareTo(b.name);
  });

  return groups;
}
