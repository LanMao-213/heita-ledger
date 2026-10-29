import 'models.dart';

/// 「按当前进度，预计什么时候达成」—— 纯函数，输入流水，输出一句可判定的结论。
///
/// 为什么不是一个 `String?`（算不出就返回 null）：**「算不出来」和「算出来是
/// 2031 年」是两件完全不同的事**，界面必须能分开表达。把两者都压成 null，
/// 用户看到的就是一句沉默 —— 而沉默在「我存了三个月怎么没反应」的场景里
/// 会被读成 bug。
enum GoalEtaState {
  /// 已达成（`saved >= target`）。
  done,

  /// 一条流水都没有 —— 老目标或刚建的目标。此时没有速率可言，
  /// 界面应该说「存过一笔之后才会有预计时间」，而不是给个假日期。
  noFlow,

  /// 有流水，但净额 ≤ 0（取出的比存进的多）。速率是 0 或负数，
  /// 外推只会得到「永远达不成」，那不是一个预计时间。
  noRate,

  /// 能外推，且落在合理时间范围内。
  estimated,

  /// 能外推，但按这个速率要 50 年以上 —— 数学上成立，实际上等于达不成。
  /// 单独一档是为了不说「预计 2150 年达成」这种像玩笑的话。
  unreachable,
}

/// 预计达成时间的结果。
class GoalEta {
  const GoalEta({
    required this.state,
    this.etaMonth,
    this.monthlyRateCents = 0,
    this.monthsNeeded = 0,
  });

  final GoalEtaState state;

  /// `YYYY-MM`，仅 [GoalEtaState.estimated] 时有值。
  final String? etaMonth;

  /// 月均净存入（分）。取整到分，可能为 0。
  final int monthlyRateCents;

  /// 还差几个月，仅 [GoalEtaState.estimated] 时有意义。
  final int monthsNeeded;

  bool get hasEta => state == GoalEtaState.estimated;
}

/// 超过这个月数（50 年）就不再称为「预计达成」。
const int _unreachableMonths = 600;

/// 计算预计达成时间。
///
/// [today] 是 `YYYY-MM-DD`，由调用方传入而不是内部取 `DateTime.now()`：
/// 纯函数才好测，而且「今天」在一屏里只该有一个来源。
///
/// ## 速率怎么算
///
/// 取**观察窗口内全部流水的净额 ÷ 窗口月数**，窗口 = 最早一条流水的月份 到
/// 今天所在月份（含两端）。几个刻意的选择：
///
/// - **用净额而不是只加存入**：只算存入会把「存了又取」的人算成储蓄高手，
///   预计时间比现实乐观得多，而这张卡片的全部价值就在于它别撒谎。
/// - **窗口从最早流水算起，不截取「最近 N 个月」**：目标流水本来就稀疏
///   （一个月一两笔），截取近期反而更容易被单笔大额带偏。
/// - **不足一个月按一个月算**：刚存第一笔的人也应该立刻看到一个预计时间，
///   否则他会以为功能坏了。代价是首月估算偏保守（速率被摊薄），可接受。
GoalEta projectGoal({
  required int targetCents,
  required int savedCents,
  required List<GoalFlow> flows,
  required String today,
}) {
  if (savedCents >= targetCents && targetCents > 0) {
    return const GoalEta(state: GoalEtaState.done);
  }
  if (targetCents <= 0) {
    return const GoalEta(state: GoalEtaState.done);
  }
  if (flows.isEmpty) {
    return const GoalEta(state: GoalEtaState.noFlow);
  }

  final earliest = flows
      .map((f) => f.date)
      .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  final windowMonths = _monthsBetween(earliest, today);
  final net = flows.fold<int>(0, (sum, f) => sum + f.cents);
  if (net <= 0) {
    return GoalEta(state: GoalEtaState.noRate, monthlyRateCents: net);
  }

  final rate = net ~/ windowMonths;
  if (rate <= 0) {
    // 净额为正但摊到每个月不足 1 分（极端情况：窗口很长、总额很小）
    return GoalEta(state: GoalEtaState.noRate, monthlyRateCents: rate);
  }

  final remain = targetCents - savedCents;
  if (remain <= 0) return const GoalEta(state: GoalEtaState.done);
  final monthsNeeded = (remain + rate - 1) ~/ rate; // 向上取整
  if (monthsNeeded > _unreachableMonths) {
    return GoalEta(
      state: GoalEtaState.unreachable,
      monthlyRateCents: rate,
      monthsNeeded: monthsNeeded,
    );
  }
  return GoalEta(
    state: GoalEtaState.estimated,
    etaMonth: _addMonths(_monthOf(today), monthsNeeded),
    monthlyRateCents: rate,
    monthsNeeded: monthsNeeded,
  );
}

/// [from] 到 [to] 之间跨了多少个月（含两端，最小 1）。
///
/// 例：`2026-10-01` → `2026-10-29` = 1；`2026-08-15` → `2026-10-01` = 3。
int _monthsBetween(String from, String to) {
  final a = _monthOf(from);
  final b = _monthOf(to);
  final diff = (b.year - a.year) * 12 + (b.month - a.month) + 1;
  return diff < 1 ? 1 : diff;
}

({int year, int month}) _monthOf(String date) {
  final y = int.tryParse(date.substring(0, 4)) ?? 1970;
  final m = int.tryParse(date.substring(5, 7)) ?? 1;
  return (year: y, month: m);
}

/// `YYYY-MM` 往后推 [months] 个月。
String _addMonths(({int year, int month}) from, int months) {
  final total = from.year * 12 + (from.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  return '$y-${m.toString().padLeft(2, '0')}';
}
