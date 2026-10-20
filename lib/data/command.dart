import 'package:sqflite/sqflite.dart';

import 'db.dart';

/// 是否在写入后校验不变量。
///
/// `dart.vm.product` 在 release 构建里是 true，所以这个常量在正式包里恒为 false，
/// 编译器会把 [Verifier] 里整段代码消掉 —— **用户手上那个包一分钱性能不花**。
/// `flutter test` 与 debug 构建里为 true，于是「记账顺手对一次账」在开发期
/// 天天发生，问题在写出来的当天就暴露。
const bool kVerifyWrites = !bool.fromEnvironment('dart.vm.product');

/// 一次写操作的作用域。
///
/// 业务代码只能通过它改数据，**拿不到 `Database`** —— 拿不到就开不了事务、
/// 也嵌套不了事务。这是「单一写入网关」的落点：事务边界只有 [WriteGateway.run]
/// 一处，业务层没有机会忘记它。
///
/// 注意这里**暴露 `query`**：像「这条规则的这一期是否已经补过」这种幂等判断
/// 必须在事务内读，否则并发/重入时会漏。读不影响事务安全性。
class WriteScope {
  const WriteScope(this._txn);

  final Transaction _txn;

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) => _txn.insert(
    table,
    values,
    conflictAlgorithm: conflictAlgorithm,
  );

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) => _txn.update(table, values, where: where, whereArgs: whereArgs);

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) => _txn.delete(table, where: where, whereArgs: whereArgs);

  Future<int> rawUpdate(String sql, [List<Object?>? args]) =>
      _txn.rawUpdate(sql, args);

  Future<int> rawInsert(String sql, [List<Object?>? args]) =>
      _txn.rawInsert(sql, args);

  Future<int> rawDelete(String sql, [List<Object?>? args]) =>
      _txn.rawDelete(sql, args);

  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _txn.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? args,
  ]) => _txn.rawQuery(sql, args);
}

/// 一个写操作。
///
/// 约定：`apply` 里只写业务语义，**不要**再判断事务、不要再开连接。
/// 需要「先回滚旧值再写新值」这种多步操作，全部写在同一个 `apply` 里。
abstract class Command<T> {
  /// 在事务内执行。抛异常 = 整次写入回滚。
  Future<T> apply(WriteScope w);

  /// 提交后的自检。只在 debug / 测试里真正执行（见 [kVerifyWrites]）。
  ///
  /// 位置说明：它跑在事务**提交之后**。因为它只产生警告、不回滚，
  /// 放进事务里除了延长持锁时间没有任何收益（见 [Verifier] 的注释）。
  Future<void> verify(Verifier v) async {}
}

/// 不变量校验器。
///
/// 设计上「**警告而不阻断**」不是偷懒：用户手机上真实存在的库可能已经带着
/// 1.4.4 之前的漂移，如果校验失败就抛异常，那次记账会直接失败 —— 等于用
/// 一个历史问题卡住用户当下要办的事，比问题本身更糟。
/// 所以这里只收集警告：debug 下打印、测试里由用例断言为空。
/// 机械证据来自测试（CI 会红），用户不会被挡住。
///
/// ★ 因为它**不阻断**，所以校验发生在**事务提交之后**（见 [WriteGateway.run]）。
///   放进事务里只会延长持锁时间，还平白多两次查询 —— 而那两次查询恰好会让
///   界面测试的「点保存 → 等一会儿 → 断言」变得不稳定。既然不打算回滚，
///   就没有理由占着事务。
class Verifier {
  Verifier(this._db);

  final Database _db;

  /// 校验某个账户的余额是否满足 `balance = opening + 流水合计`。
  ///
  /// 这条恒等式的权威定义在 `Integrity._balanceSql`，这里只做单账户版本 ——
  /// 每次写入都全表扫一遍不值得，而单账户的聚合有索引。
  Future<void> checkBalance(int? accountId) async {
    if (!kVerifyWrites || accountId == null) return;

    final rows = await _db.query(
      'account',
      columns: const ['balance_cents', 'opening_cents'],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final flow = await _db.rawQuery('''
      SELECT COALESCE(SUM(CASE
        WHEN t.type = 'income'                                THEN  t.amount_cents
        WHEN t.type = 'expense'                               THEN -t.amount_cents
        WHEN t.type = 'transfer' AND t.account_id    = ?      THEN -t.amount_cents
        WHEN t.type = 'transfer' AND t.to_account_id = ?      THEN  t.amount_cents
        ELSE 0 END), 0) AS s
      FROM txn t WHERE t.account_id = ? OR t.to_account_id = ?
    ''', [accountId, accountId, accountId, accountId]);

    final stored = rows.first['balance_cents'] as int;
    final expected =
        (rows.first['opening_cents'] as int) +
        ((flow.first['s'] as int?) ?? 0);
    if (stored != expected) {
      WriteGateway.warn(
        '余额不一致 account=$accountId：账面 $stored，按流水应为 $expected',
      );
    }
  }
}

/// 单一写入网关。
///
/// 所有会改动数据的操作都必须从这里过：`run` 负责开事务、调 `apply`、
/// 校验，任一步抛异常则整体回滚。这样「忘记开事务」在结构上就不成立了 ——
/// 业务层根本拿不到 `Database`。
abstract final class WriteGateway {
  /// 本次写入产生的校验警告。只在 debug / 测试里非空。
  static final List<String> warnings = <String>[];

  static Future<T> run<T>(Command<T> command) async {
    warnings.clear();
    // 库通常已经开着（应用启动时就开了）。能同步拿到就不要多走一次 await：
    // 在 testWidgets 的假时钟里，每次多余的异步跳转都要额外 pump 才推进。
    final db = Db.cached ?? await Db.open();
    final result = await db.transaction((txn) async {
      final scope = WriteScope(txn);
      return command.apply(scope);
    });

    // 校验放在**提交之后**：它只产生警告、不回滚，占着事务没有收益，
    // 反而延长持锁时间、拖慢「点保存到落库」这一段。
    if (kVerifyWrites) {
      await command.verify(Verifier(db));
    }

    if (warnings.isNotEmpty) {
      // debug 构建里能看见；release 里 kVerifyWrites 为 false，永远不会走到这
      for (final w in warnings) {
        // ignore: avoid_print
        print('[WriteGateway] $w');
      }
    }
    return result;
  }

  static void warn(String message) {
    if (kVerifyWrites) warnings.add(message);
  }
}
