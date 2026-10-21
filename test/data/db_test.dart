import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/db/schema.dart';
import 'package:heita_ledger/data/models/setting.dart';
import 'package:sqflite/sqflite.dart';

import '../support/db_fixture.dart';

/// 连接层、清空/回滚、全量替换、账本指针自愈。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  test('onCreate 建好一本账本、一个默认账户、完整两级分类与两个必需设置', () async {
    expect(await Db.rowCount(Tables.ledger), 1);
    expect(await Db.rowCount(Tables.account), 1);
    expect(await Db.rowCount(Tables.category), 15 + 73);
    expect(await Db.readSetting(SettingKeys.currentLedgerId), '1');
    expect(await Db.readSetting(SettingKeys.cycleStartDay), '1');
    // 配色与触感**不在播种里写**：播种不该覆盖用户偏好，缺省由 boot 兜
    expect(await Db.readSetting(SettingKeys.themePalette), isNull);
    expect(await Db.readSetting(SettingKeys.uiHaptics), isNull);
  });

  test('open 是幂等的：连续两次返回同一实例，不重复播种', () async {
    final Database first = await Db.open();
    final Database second = await Db.open();
    expect(identical(first, second), isTrue);
    expect(await Db.rowCount(Tables.category), 15 + 73);
  });

  test('I17：wipeAllData 中途抛异常 → 整体回滚，表与行都还在', () async {
    final int ledgers = await Db.rowCount(Tables.ledger);
    final int categories = await Db.rowCount(Tables.category);
    final Database db = await Db.database();
    await db.insert(Tables.txn, <String, Object?>{
      'ledger_id': 1,
      'type': 'expense',
      'amount_cents': -100,
      'date': '2026-10-16',
      'period_start': '2026-10-15',
      'created_at': '2026-10-16T10:00:00.000',
    });
    expect(await Db.rowCount(Tables.txn), 1);

    // 打桩：删完之后、播种之前炸掉
    Db.wipeAllDataFaultForTest = (DatabaseExecutor _) async {
      throw StateError('打桩故障');
    };

    await expectLater(Db.wipeAllData(), throwsA(isA<StateError>()));

    expect(await Db.rowCount(Tables.txn), 1, reason: '删除必须被回滚');
    expect(await Db.rowCount(Tables.ledger), ledgers);
    expect(await Db.rowCount(Tables.category), categories);
  });

  test('wipeAllData 成功后只剩一本账本、分类是完整两级、用户偏好保留', () async {
    await Db.writeSetting(SettingKeys.themePalette, 'aurora');
    await Db.writeSetting(SettingKeys.uiHaptics, '0');

    await Db.wipeAllData();

    expect(await Db.rowCount(Tables.ledger), 1);
    expect(await Db.rowCount(Tables.category), 15 + 73);
    expect(await Db.rowCount(Tables.account), 1);
    // 偏好留着（清账目不该顺手把配色抹掉）
    expect(await Db.readSetting(SettingKeys.themePalette), 'aurora');
    expect(await Db.readSetting(SettingKeys.uiHaptics), '0');
    // 当前账本指针被覆盖成新账本（id 会递增，AUTOINCREMENT 不复用旧 id）
    final int newLedgerId = (await (await Db.database()).query(
      Tables.ledger,
      columns: <String>['id'],
    )).single['id']! as int;
    expect(await Db.readSetting(SettingKeys.currentLedgerId), '$newLedgerId');
  });

  test('I13（局部）：dump → 清空 → replaceAll → 10 表行数与关键列逐项相等', () async {
    final Database db = await Db.database();
    // 造一点跨表数据
    final int catId = (await db.query(
      Tables.category,
      columns: <String>['id'],
      limit: 1,
    )).first['id']! as int;
    await db.insert(Tables.debt, <String, Object?>{
      'ledger_id': 1,
      'direction': 'out',
      'counterparty': '张三',
      'amount_cents': 500000,
      'date': '2026-10-10',
      'due_date': '2026-11-30',
      'count_in_budget': 0,
      'note': '',
      'created_at': '2026-10-10T09:00:00.000',
    });
    await db.insert(Tables.txn, <String, Object?>{
      'ledger_id': 1,
      'type': 'expense',
      'amount_cents': -3850,
      'category_id': catId,
      'date': '2026-10-16',
      'period_start': '2026-10-15',
      'note': '午饭',
      'debt_id': 1,
      'created_at': '2026-10-16T12:00:00.000',
    });

    final Map<String, List<Map<String, Object?>>> dump =
        <String, List<Map<String, Object?>>>{
          for (final String table in Tables.all) table: await db.query(table),
        };
    final Map<String, int> before = <String, int>{
      for (final String table in Tables.all) table: dump[table]!.length,
    };

    await Db.replaceAll(dump);

    for (final String table in Tables.all) {
      expect(await Db.rowCount(table), before[table], reason: '$table 行数不一致');
    }
    final List<Map<String, Object?>> txns = await db.query(Tables.txn);
    expect(txns.single['amount_cents'], -3850);
    expect(txns.single['note'], '午饭');
    expect(txns.single['debt_id'], 1);
    expect((await db.query(Tables.debt)).single['counterparty'], '张三');
  });

  test('replaceAll 父表先插：payload 里顺序被打乱也不撞外键', () async {
    final Database db = await Db.database();
    final List<Map<String, Object?>> categories = await db.query(
      Tables.category,
    );
    final List<Map<String, Object?>> ledgers = await db.query(Tables.ledger);

    await Db.replaceAll(<String, List<Map<String, Object?>>>{
      // 故意先给子表、后给父表
      Tables.category: categories,
      Tables.ledger: ledgers,
    });

    expect(await Db.rowCount(Tables.category), categories.length);
    expect(await Db.rowCount(Tables.ledger), 1);
  });

  test('ensureCurrentLedgerId 自愈：指针指错 → 回第一本并写回', () async {
    await Db.writeSetting(SettingKeys.currentLedgerId, '9999');
    final int id = await Db.ensureCurrentLedgerId();
    expect(id, 1);
    expect(await Db.readSetting(SettingKeys.currentLedgerId), '1');
  });

  test('ensureCurrentLedgerId 自愈：一本账本都没有 → 建一本并播种', () async {
    final Database db = await Db.database();
    await db.delete(Tables.category);
    await db.delete(Tables.account);
    await db.delete(Tables.ledger);
    expect(await Db.rowCount(Tables.ledger), 0);

    final int id = await Db.ensureCurrentLedgerId();

    expect(id, greaterThan(0));
    expect(await Db.rowCount(Tables.ledger), 1);
    expect(await Db.rowCount(Tables.category), 15 + 73);
    expect(await Db.readSetting(SettingKeys.currentLedgerId), '$id');
  });

  test('rebuildSeed 幂等：已有分类的账本不再补种', () async {
    final int ledgerId = await Db.ensureCurrentLedgerId();
    final int before = await Db.rowCount(Tables.category);

    final result = await Db.rebuildSeed(ledgerId);

    expect(result.topCount, 0, reason: '不重复补种');
    expect(result.subCount, before);
    expect(await Db.rowCount(Tables.category), before);
  });

  test('rebuildSeed 兜底：把分类全删掉后能补回完整两级', () async {
    final int ledgerId = await Db.ensureCurrentLedgerId();
    final Database db = await Db.database();
    await db.delete(Tables.category);

    final result = await Db.rebuildSeed(ledgerId);

    expect(result.topCount, 15);
    expect(result.subCount, 73);
    expect(await Db.rowCount(Tables.category), 15 + 73);
  });

  test('readSetting 缺失返回 null、writeSetting 覆盖写', () async {
    expect(await Db.readSetting('nope.nope'), isNull);

    await Db.writeSetting(SettingKeys.cycleStartDay, '5');
    expect(await Db.readSetting(SettingKeys.cycleStartDay), '5');
    await Db.writeSetting(SettingKeys.cycleStartDay, '15');
    expect(await Db.readSetting(SettingKeys.cycleStartDay), '15');
    expect(await Db.rowCount(Tables.setting), lessThan(10));
  });
}
