import 'db.dart';
import 'models.dart';

/// 数据体检 —— 把「界面不说、数据已经不对」变成一句能看懂的结论。
///
/// 为什么需要：账户余额靠 `Repo._applyBalanceDelta` **增量**维护。增量维护的
/// 特点是一旦漏一次就永久偏离，而账本里没有任何地方会对账 —— 用户只会觉得
/// 「我明明没花这么多」，却说不出哪里错。
///
/// 1.4.2 修的那三个 bug 全部属于同一家族（清空半截提交、账本指向已删行、
/// 记完看不到），这一条是家族里最难被发现的一个：因为数字本身不会报错。
///
/// 这里的每个检查都**只读**，唯一的写操作是 [recalcBalances]，且必须由用户
/// 在「数据安全」页明确点一次才执行 —— 自动化修复不放在启动路径上。
abstract final class Integrity {
  /// 全量体检。任何一项不通过都会进 [IntegrityReport.issues]。
  static Future<IntegrityReport> check() async {
    final db = await Db.open();
    final issues = <IntegrityIssue>[];

    final txnCount = _scalar(await db.rawQuery('SELECT COUNT(*) AS n FROM txn'));
    final accountCount = _scalar(
      await db.rawQuery('SELECT COUNT(*) AS n FROM account'),
    );

    // 1. 余额对账：`balance_cents` vs `opening_cents + 流水合计`
    final drift = await db.rawQuery(_balanceSql);
    for (final row in drift) {
      issues.add(
        IntegrityIssue(
          kind: IntegrityKind.balanceDrift,
          detail:
              '${row['name']}：账面 ${Fmt.money(row['stored'] as int)}，'
              '按期初 + 流水应为 ${Fmt.money(row['expected'] as int)}',
        ),
      );
    }

    // 2. 孤儿引用：软关联被删了对象之后留下的悬空 id
    for (final (column, table, label) in _orphanChecks) {
      final n = _scalar(
        await db.rawQuery(
          'SELECT COUNT(*) AS n FROM txn t WHERE t.$column IS NOT NULL '
          'AND NOT EXISTS (SELECT 1 FROM $table x WHERE x.id = t.$column)',
        ),
      );
      if (n > 0) {
        issues.add(
          IntegrityIssue(
            kind: IntegrityKind.orphanRef,
            detail: '$n 笔流水的$label指向了不存在的记录',
            affected: n,
          ),
        );
      }
    }

    // 3. 归属期：周期归集的所有查询都按 period_start 过滤，
    //    空值等于「这笔账在任何一期里都看不到」
    final noPeriod = _scalar(
      await db.rawQuery(
        'SELECT COUNT(*) AS n FROM txn WHERE period_start IS NULL',
      ),
    );
    if (noPeriod > 0) {
      issues.add(
        IntegrityIssue(
          kind: IntegrityKind.missingPeriod,
          detail: '$noPeriod 笔流水没有归属期，在周期视图里查不到',
          affected: noPeriod,
        ),
      );
    }

    // 4. 借贷：已还超过本金（口径见 docs/借贷往来-设计.md——
    //    本金方向借出记 expense、还款记 income，借入相反）
    final over = await db.rawQuery(_debtOverSql);
    for (final row in over) {
      issues.add(
        IntegrityIssue(
          kind: IntegrityKind.debtOverRepaid,
          detail:
              '${row['counterparty']}：本金 ${Fmt.money(row['amount_cents'] as int)}，'
              '已还 ${Fmt.money(row['repaid'] as int)}',
        ),
      );
    }

    // 5. 账本引用：ledger 是连带删除的，正常不会留下孤儿；
    //    留下来说明有一次删除绕过了外键（比如老版本的半截事务）
    final noLedger = _scalar(
      await db.rawQuery(
        'SELECT COUNT(*) AS n FROM txn t WHERE NOT EXISTS '
        '(SELECT 1 FROM ledger l WHERE l.id = t.ledger_id)',
      ),
    );
    if (noLedger > 0) {
      issues.add(
        IntegrityIssue(
          kind: IntegrityKind.missingLedger,
          detail: '$noLedger 笔流水挂在已删除的账本上',
          affected: noLedger,
        ),
      );
    }

    return IntegrityReport(
      issues: issues,
      checkedTxns: txnCount,
      checkedAccounts: accountCount,
    );
  }

  /// 按「期初 + 流水合计」重算每个账户的余额，返回真正被修正的账户数。
  ///
  /// 只在用户手动点「重算余额」时调用。算法与 [Repo._applyBalanceDelta] 里
  /// 增量维护的公式**必须逐字对应**（收入 +、支出 −、转账转出 − 转入 +），
  /// 否则重算本身会变成新的漂移源。
  ///
  /// 注意：重算**不会动 `opening_cents`**。期初是用户手填的基准，任何自动流程
  /// 都不该改它 —— 一旦改了，"余额对不对"又变成不可判定。
  static Future<int> recalcBalances() async {
    final db = await Db.open();
    final drift = await db.rawQuery(_balanceSql);
    if (drift.isEmpty) return 0;

    await db.transaction((txn) async {
      for (final row in drift) {
        await txn.update(
          'account',
          {'balance_cents': row['expected']},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
    return drift.length;
  }

  /// 把当前余额「认下来」当成新的基准 —— 期初 = 余额 − 流水合计。
  ///
  /// 两个调用点：
  /// 1. **备份恢复之后**。老备份里没有 `opening_cents`（v7 及以前），灌进新库
  ///    之后全是 0，`opening + 流水` 立刻对不上余额 —— 但它其实是对的，
  ///    因为老库里「余额」本来就是用户手填的绝对值。这里认一次基准，
  ///    让恢复完的账本立刻处于自洽状态。
  /// 2. 迁移 v7→v8 的回填（那条写在 `Db._addOpeningBalanceColumn` 里，
  ///    不在这里，因为迁移阶段还没有 Repo 可用）。
  static Future<int> adoptCurrentBalances() async {
    final db = await Db.open();
    final rows = await db.rawQuery('''
      SELECT a.id AS id, a.balance_cents AS stored,
             COALESCE((
               SELECT SUM(CASE
                 WHEN t.type = 'income'                                THEN  t.amount_cents
                 WHEN t.type = 'expense'                               THEN -t.amount_cents
                 WHEN t.type = 'transfer' AND t.account_id    = a.id   THEN -t.amount_cents
                 WHEN t.type = 'transfer' AND t.to_account_id = a.id   THEN  t.amount_cents
                 ELSE 0 END)
               FROM txn t
               WHERE t.account_id = a.id OR t.to_account_id = a.id
             ), 0) AS flow
      FROM account a
    ''');
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.update(
          'account',
          {'opening_cents': (row['stored'] as int) - (row['flow'] as int)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
    return rows.length;
  }

  /// 只取**不一致**的账户。`expected` 的 CASE 与 `_applyBalanceDelta` 一一对应：
  /// 收入加、支出减、转账在转出端减、在转入端加。
  ///
  /// 注意 `amount_cents` 允许为负（键盘行首打 `-` 就是负数），所以这里
  /// 不做 `ABS`、也不判断正负 —— 增量维护当初怎么加减，这里就怎么加减。
  static const _balanceSql = '''
    SELECT a.id AS id, a.name AS name,
           a.balance_cents AS stored,
           a.opening_cents + COALESCE((
             SELECT SUM(CASE
               WHEN t.type = 'income'                              THEN  t.amount_cents
               WHEN t.type = 'expense'                             THEN -t.amount_cents
               WHEN t.type = 'transfer' AND t.account_id   = a.id  THEN -t.amount_cents
               WHEN t.type = 'transfer' AND t.to_account_id = a.id THEN  t.amount_cents
               ELSE 0 END)
             FROM txn t
             WHERE t.account_id = a.id OR t.to_account_id = a.id
           ), 0) AS expected
    FROM account a
    WHERE expected <> a.balance_cents
    ORDER BY a.id
  ''';

  /// 借贷：已还 > 本金。方向决定哪一侧的流水算「还款」。
  static const _debtOverSql = '''
    SELECT d.id AS id, d.counterparty AS counterparty,
           d.amount_cents AS amount_cents,
           COALESCE((
             SELECT SUM(t.amount_cents) FROM txn t
             WHERE t.debt_id = d.id
               AND t.type = CASE WHEN d.direction = 'out' THEN 'income' ELSE 'expense' END
           ), 0) AS repaid
    FROM debt d
    WHERE repaid > d.amount_cents
  ''';

  /// 软关联列 → 被引用的表 → 中文说法。`debt_id` 也在内：
  /// 删借贷时流水会一起处理，但老版本中断的写入可能留下悬空引用。
  static const _orphanChecks = <(String, String, String)>[
    ('category_id', 'category', '分类'),
    ('account_id', 'account', '账户'),
    ('to_account_id', 'account', '转入账户'),
    ('debt_id', 'debt', '借贷'),
  ];

  static int _scalar(List<Map<String, Object?>> rows) =>
      (rows.isEmpty ? 0 : (rows.first['n'] as int?) ?? 0);
}

/// 体检发现的单条问题。
class IntegrityIssue {
  const IntegrityIssue({
    required this.kind,
    required this.detail,
    this.affected = 1,
  });

  final IntegrityKind kind;

  /// 给用户看的一句话，已包含金额/数量
  final String detail;

  /// 受影响的行数（账户不一致按 1 个账户算）
  final int affected;
}

/// 问题分类。label 直接用于界面，不再在 UI 层写 switch。
enum IntegrityKind {
  balanceDrift('账户余额与流水不一致', true),
  orphanRef('流水指向了不存在的记录', false),
  missingPeriod('流水缺少归属期', false),
  debtOverRepaid('借贷已还超过本金', false),
  missingLedger('流水挂在已删除的账本上', false);

  const IntegrityKind(this.label, this.fixable);

  final String label;

  /// 能否靠「重算余额」这一类自动修复解决。只有余额漂移可以。
  final bool fixable;
}

/// 一次体检的结果。
class IntegrityReport {
  const IntegrityReport({
    required this.issues,
    required this.checkedTxns,
    required this.checkedAccounts,
  });

  final List<IntegrityIssue> issues;
  final int checkedTxns;
  final int checkedAccounts;

  bool get ok => issues.isEmpty;

  /// 有可自动修复的项（目前只有余额漂移）
  bool get hasFixable => issues.any((i) => i.kind.fixable);

  /// 「检查了 1,204 笔流水、4 个账户」/「发现 2 项问题」
  String get summary => ok
      ? '检查了 $checkedTxns 笔流水、$checkedAccounts 个账户，没有发现问题'
      : '检查了 $checkedTxns 笔流水、$checkedAccounts 个账户，发现 ${issues.length} 项问题';
}
