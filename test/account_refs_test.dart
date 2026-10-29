// 「账户被删之后，指着它的那些列怎么办」—— 一张登记表 + 一条 schema 守卫。
//
// ## 它防的是什么
//
// 账户没有外键约束（见 `db.dart`），所以「账户没了」这件事**不会有任何报错**：
// 库里只是多出几个指向不存在 id 的列。它们不会崩、不会写日志，只会在某个页面
// 读到的时候显示一个空账户名，或者在体检里报一条对不上的账 —— 通常是几个月后
// 才被发现，那时已经不知道该改哪一处了。
//
// 已经踩过的两次：
//   1. `txn.account_id` 直接删账户 → 孤儿流水（1.5.x 之前）；
//   2. `goal_flow.account_id` 没人清 → QA 提的 P3（`plan_page` 不读这列，
//      所以谁都不知道）。
//
// 两次的根因是同一条：**「账户被删要清哪些列」是一份手写名单，加表时靠记性。**
// 所以这里不测「某个函数被调用了」，而是扫**建完库之后真实的结构**：
//
//   PRAGMA table_info 里凡是叫 `account_id` / `to_account_id` 的列，
//   必须在 `kAccountRefPlan` 里登记过；登记过但库里没有这一列，也红。
//
// 这条守卫的价值不在今天（今天是全绿的），在于「将来加一张带账户列的表」时
// 它会替记性出一次错。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/schema_diff.dart';

const _dbName = 'test_account_refs.db';

/// 名字像账户引用的两列。口径写死在这里，不跟实现走 ——
/// 实现了什么就查什么的守卫，永远能自己给自己发许可。
const _accountRefColumns = {'account_id', 'to_account_id'};

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 建好库（含迁移）再读出结构。
Future<SchemaSnapshot> _schema() async {
  final db = await Db.open();
  return SchemaSnapshot.read(db);
}

/// 库里实际存在的「账户引用」列，形如 `txn.account_id`。
Future<Set<String>> _refsInSchema() async {
  final schema = await _schema();
  final out = <String>{};
  for (final table in schema.tables.entries) {
    for (final column in table.value.keys) {
      if (_accountRefColumns.contains(column)) {
        out.add('${table.key}.$column');
      }
    }
  }
  return out;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  group('登记表 ↔ 库结构 双向一致', () {
    test('库里每一处账户引用都在 kAccountRefPlan 里登记过', () async {
      final onDisk = await _refsInSchema();
      expect(
        onDisk,
        isNotEmpty,
        reason: '一处账户引用都没扫到 —— 守卫自己失效了（Db.open 没建表？）',
      );
      final missing = onDisk.difference(kAccountRefPlan.keys.toSet());
      expect(
        missing,
        isEmpty,
        reason: '这些列指向账户，但没人登记「账户被删之后它怎么办」：'
            '${missing.join('、')}\n'
            '请加进 lib/data/repo/account.dart 的 kAccountRefPlan：'
            '历史流水 → repoint；「默认记到哪 / 从哪个账户挪的钱」→ detach；'
            '账户自身的数据 → cascade；核对过不是账户引用 → unrelated。',
      );
    });

    test('登记表里没有库里不存在的列（防止改名后留下幽灵条目）', () async {
      final onDisk = await _refsInSchema();
      final ghost = kAccountRefPlan.keys.toSet().difference(onDisk);
      expect(
        ghost,
        isEmpty,
        reason: '登记了但库里没这一列（改名了？）：${ghost.join('、')}',
      );
    });

    test('四类处置都有名字，且当前生效的只有 repoint 与 detach', () {
      // 四类是「登记时能选的全部答案」。今天用到两类，另两类是给将来加表的人
      // 准备的位置 —— 没有名字，他只能把列顺手塞进 detach，那就又变成猜。
      expect(AccountRefAction.values, hasLength(4));
      expect(
        kAccountRefPlan.values.toSet(),
        {AccountRefAction.repoint, AccountRefAction.detach},
        reason: '出现了 cascade / unrelated 的登记 —— 请确认这两类真的有对应的'
            '清理代码（cascade 要有人删数据，unrelated 不用清）',
      );
    });
  });

  group('唯一来源', () {
    test('account.dart 里只剩一处「置空名单」：kAccountRefPlan', () {
      final src = File('lib/data/repo/account.dart').readAsStringSync();
      // 手写表名列表的样子：`for (final table in ['recurring', ...`
      final handwritten = RegExp(
        r"for\s*\(\s*final\s+table\s+in\s*\[",
      ).hasMatch(src);
      expect(
        handwritten,
        isFalse,
        reason: '出现第二份手写表名名单 —— 加表时必然漏一处，请从 kAccountRefPlan 派生',
      );
      expect(
        src.contains('_detachAccountRefs('),
        isTrue,
        reason: '置空逻辑必须走 _detachAccountRefs，不要在事务里另写 update',
      );
      // 合并路径 + 直删路径各调一次（定义体本身不算）
      final calls = RegExp(r'await _detachAccountRefs\(').allMatches(src).length;
      expect(
        calls,
        2,
        reason: '合并（mergeAccount）与直删（deleteAccount）两条路径都必须调用它，'
            '实际调用 $calls 次',
      );
    });
  });

  group('行为：两条路径都按登记表清', () {
    test('合并账户时，detach 类的列被置空（不是改挂）', () async {
      final from = await Repo.insertAccount(const Account(id: 0, name: '旧钱包'));
      final to = await Repo.insertAccount(const Account(id: 0, name: '新钱包'));
      final goal = await Repo.insertGoal(const SavingGoal(id: 0, name: '相机', targetCents: 100000));
      // 老库里确实存在带 account_id 的目标流水（1.6.0 之前 UI 写的）
      final db = await Db.open();
      await db.insert('goal_flow', {
        'goal_id': goal,
        'date': '2026-10-01',
        'cents': 5000,
        'account_id': from,
        'note': '老行',
      });

      await Repo.mergeAccount(from: from, to: to);

      final row = (await db.query('goal_flow')).single;
      expect(
        row['account_id'],
        isNull,
        reason: '目标流水不是账户流水，并过去等于编造「你从这个账户取过钱」',
      );
      expect(row['cents'], 5000, reason: '目标流水本身必须留着');
    });

    test('直删账户时，同一份名单生效', () async {
      final acc = await Repo.insertAccount(const Account(id: 0, name: '临时卡'));
      final goal = await Repo.insertGoal(const SavingGoal(id: 0, name: '相机', targetCents: 100000));
      final db = await Db.open();
      await db.insert('goal_flow', {
        'goal_id': goal,
        'date': '2026-10-01',
        'cents': 5000,
        'account_id': acc,
        'note': '老行',
      });

      await Repo.deleteAccount(acc);

      expect((await db.query('goal_flow')).single['account_id'], isNull);
    });
  });
}
