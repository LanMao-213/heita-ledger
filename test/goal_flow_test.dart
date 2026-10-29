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
    await Repo.addFunds(id, 20000, date: '2026-10-01', accountId: 7, note: '奖金');

    expect(await _savedOf(id), 20000);
    final flows = await Repo.listGoalFlows(id);
    expect(flows, hasLength(1));
    expect(flows.single.cents, 20000);
    expect(flows.single.date, '2026-10-01');
    expect(flows.single.accountId, 7);
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
}
