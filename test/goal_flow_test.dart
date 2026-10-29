// 储蓄目标流水（v10）的自检。
//
// 这张表存在的唯一理由：让「预计何时达成」有速率可算。所以这里最该钉住的不是
// "能存进去"，而是两个容易把账算错的点：
//   1) 取钱取到下限时，**流水金额必须等于实际变化量**（想取 500 只剩 300 就记 -300）。
//      否则 Σ(flow) 与 saved_cents 分叉，外推会基于一个不存在的余额。
//   2) 删目标要连流水一起删，否则留下永远清不掉的孤儿行（清空数据也带不走它）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_goal_flow.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<int> _newGoal({int target = 100000, int monthly = 0}) => Repo.insertGoal(
  SavingGoal(id: 0, name: '相机', targetCents: target, monthlyCents: monthly),
);

Future<int> _savedOf(int goalId) async {
  final g = (await Repo.listGoals()).firstWhere((e) => e.id == goalId);
  return g.savedCents;
}

/// 直接往库里塞一条「带 account_id 的目标流水」。
///
/// 为什么测试要绕开 `addFunds` 自己写：1.6.0 起 `addFunds` **不再接受
/// accountId**（那个参数只写 id、不改账户余额，等于在账本里造一条假事实）。
/// 但老库里**已经存在**这样的行 —— 那时它们是从 UI 写进去的。于是「账户被删
/// 之后这些老行怎么办」仍然必须成立，而它只能靠直写 SQL 复现。
Future<void> _insertLegacyFlow(int goalId, int accountId, int cents) async {
  final db = await Db.open();
  await db.insert('goal_flow', {
    'goal_id': goalId,
    'date': '2026-10-01',
    'cents': cents,
    'account_id': accountId,
    'note': '老行',
  });
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

  test('存入：saved_cents 与流水同时落，金额一致', () async {
    final id = await _newGoal();
    await Repo.addFunds(id, 20000, date: '2026-10-01', note: '奖金');

    expect(await _savedOf(id), 20000);
    final flows = await Repo.listGoalFlows(id);
    expect(flows, hasLength(1));
    expect(flows.single.cents, 20000);
    expect(flows.single.date, '2026-10-01');
    // 1.6.0 起恒写 NULL：存钱不是账户流水，账户余额一分没动
    expect(
      flows.single.accountId,
      isNull,
      reason: '目标流水不该带账户 id —— 写进去等于说「钱从这个账户挪走了」，'
          '而账户余额并没有变',
    );
    expect(flows.single.note, '奖金');
    expect(flows.single.isDeposit, isTrue);
  });

  test('取出超过已存：余额归 0，流水只记实际差额（不是 -请求额）', () async {
    final id = await _newGoal();
    await Repo.addFunds(id, 30000, date: '2026-10-01');
    await Repo.addFunds(id, -50000, date: '2026-10-02'); // 只想剩下 0，不是 -20000

    expect(await _savedOf(id), 0);
    final flows = await Repo.listGoalFlows(id);
    expect(flows.first.cents, -30000, reason: '流水必须等于实际变化量，否则 Σ(flow) 与 saved 分叉');
  });

  test('金额为 0 不写流水（否则流水里全是噪声行）', () async {
    final id = await _newGoal();
    await Repo.addFunds(id, 0, date: '2026-10-01');

    expect(await _savedOf(id), 0);
    expect(await Repo.listGoalFlows(id), isEmpty);
  });

  test('已取到 0 之后再取：不产生 0 元流水', () async {
    final id = await _newGoal();
    await Repo.addFunds(id, -1000, date: '2026-10-01'); // 余额本来就是 0

    expect(await Repo.listGoalFlows(id), isEmpty);
  });

  test('流水按日期倒序（最近在前）', () async {
    final id = await _newGoal();
    await Repo.addFunds(id, 10000, date: '2026-08-01');
    await Repo.addFunds(id, 20000, date: '2026-10-01');
    await Repo.addFunds(id, 5000, date: '2026-09-01');

    final dates = (await Repo.listGoalFlows(id)).map((f) => f.date).toList();
    expect(dates, ['2026-10-01', '2026-09-01', '2026-08-01']);
  });

  test('删目标连流水一起删（不留孤儿行）', () async {
    final id = await _newGoal();
    await Repo.addFunds(id, 10000, date: '2026-10-01');
    expect(await Repo.listGoalFlows(id), hasLength(1));

    await Repo.deleteGoal(id);
    expect(await Repo.listGoals(), isEmpty);
    expect(
      await Repo.listGoalFlows(id),
      isEmpty,
      reason: 'goal_flow.goal_id 是软关联，没有外键级联，必须手动删干净',
    );
  });

  test('目标被删后再存钱：静默退出，不写孤儿流水', () async {
    final id = await _newGoal();
    await Repo.deleteGoal(id);

    await Repo.addFunds(id, 10000, date: '2026-10-01');
    expect(await Repo.listGoalFlows(id), isEmpty);
  });

  test('monthly_cents 能存能读（v10 新列）', () async {
    final id = await _newGoal(monthly: 50000);
    final g = (await Repo.listGoals()).firstWhere((e) => e.id == id);
    expect(g.monthlyCents, 50000);
  });

  // 「没有流水的账户」可以从 UI 直删（有流水的走合并），但目标流水不是账户流水 ——
  // 「没有流水」这个前提管不到它。不置空就会留一个指向已删账户的 id。
  test('直删账户后，目标流水的 account_id 被置空，流水本身保留', () async {
    final accId = await Repo.insertAccount(
      const Account(id: 0, name: '共用钱包'),
    );
    final id = await _newGoal();
    await Repo.addFunds(id, 10000, date: '2026-10-01');
    // 老库里确实有带 account_id 的行，这里直写复现它
    await _insertLegacyFlow(id, accId, 5000);
    expect(
      (await Repo.listGoalFlows(id)).where((f) => f.accountId == accId),
      hasLength(1),
    );

    await Repo.deleteAccount(accId);

    final flows = await Repo.listGoalFlows(id);
    expect(flows, hasLength(2), reason: '删账户不该连带删掉储蓄目标的存钱记录');
    expect(
      flows.where((f) => f.accountId != null),
      isEmpty,
      reason: '不能留悬空 id 指向已删账户',
    );
    expect(flows.fold<int>(0, (a, f) => a + f.cents), 15000);
  });
}
