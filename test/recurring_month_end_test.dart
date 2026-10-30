// 周期账单「月末漂移」的回归网（1.7.2 修）。
//
// 缺陷长什么样：`_advance` 拿「已经被 clamp 过的 next_run_date」当递推基数。
// 1-31 的月付规则走到 2 月被 clamp 成 2-28，之后每一期都从 28 号推 ——
// 3-31、5-31、7-31 这些本该在月末的账，永久落在 28 号。
//
// 为什么以前没被发现：旧测试里 `nextRunDate` 只出现 4 次，全部是**造夹具时的赋值**，
// 没有任何一条断言过它的值；`lifecycle_catchup_test` 只数「插了几笔」。
// 单步（1-31 → 2-28）看起来完全正确，**连续推才会暴露**，所以这里一次推 12 期。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_recurring_month_end.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<List<String>> _datesOf(int ruleId) async {
  final db = await Db.open();
  final rows = await db.query(
    'txn',
    columns: ['date'],
    where: 'recurring_id = ?',
    whereArgs: [ruleId],
    orderBy: 'date',
  );
  return rows.map((r) => r['date'] as String).toList();
}

void main() {
  late int ledgerId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
    await Db.open();
    ledgerId = await Repo.currentLedgerId();
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  test('1-31 的月付规则连推 12 期：每个大月都要回到 31 号', () async {
    final ruleId = await Repo.insertRecurring(
      RecurringRule(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 100000,
        note: '房租',
        freq: 'monthly',
        interval: 1,
        nextRunDate: '2026-01-31',
      ),
    );

    final created = await Repo.runDueRecurring(
      ledgerId,
      now: DateTime(2026, 12, 31),
    );
    expect(created, 12, reason: '2026 全年 12 期');

    expect(
      await _datesOf(ruleId),
      [
        '2026-01-31',
        '2026-02-28', // 短月按月末对齐，不是溢出到 3 月
        '2026-03-31', // ← 旧实现从这里开始永久停在 28
        '2026-04-30',
        '2026-05-31',
        '2026-06-30',
        '2026-07-31',
        '2026-08-31',
        '2026-09-30',
        '2026-10-31',
        '2026-11-30',
        '2026-12-31',
      ],
      reason: '2 月被 clamp 成 28 之后，下一个大月必须回到 31',
    );
  });

  test('已经漂到 28 的存量规则：靠最早一笔流水把锚点纠正回 31', () async {
    // 造一条「历史上已经漂过一次」的规则：1-31 记过一笔，next_run_date 已是 2-28。
    // 没有锚点时，后续会一直从 28 推 —— 这正是线上老数据的形态。
    final ruleId = await Repo.insertRecurring(
      RecurringRule(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 100000,
        note: '房租',
        freq: 'monthly',
        interval: 1,
        nextRunDate: '2026-02-28',
      ),
    );
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 100000,
        date: '2026-01-31',
        note: '房租',
        recurringId: ruleId,
      ),
    );

    await Repo.runDueRecurring(ledgerId, now: DateTime(2026, 3, 31));

    expect(
      await _datesOf(ruleId),
      ['2026-01-31', '2026-02-28', '2026-03-31'],
      reason: '锚点从最早的 1-31 反推，3 月必须回到 31 而不是 28',
    );
  });

  test('29/30/1 号规则各自保持自己的日子', () async {
    final cases = <String, List<String>>{
      '2026-01-29': ['2026-01-29', '2026-02-28', '2026-03-29'],
      '2026-01-30': ['2026-01-30', '2026-02-28', '2026-03-30'],
      '2026-01-01': ['2026-01-01', '2026-02-01', '2026-03-01'],
    };
    for (final entry in cases.entries) {
      await Db.close();
      final f = File(await _dbPath());
      if (f.existsSync()) f.deleteSync();
      await Db.open();
      ledgerId = await Repo.currentLedgerId();

      final ruleId = await Repo.insertRecurring(
        RecurringRule(
          id: 0,
          ledgerId: ledgerId,
          type: TxnType.expense,
          amountCents: 1000,
          note: entry.key,
          freq: 'monthly',
          interval: 1,
          nextRunDate: entry.key,
        ),
      );
      await Repo.runDueRecurring(ledgerId, now: DateTime(2026, 3, 31));
      expect(await _datesOf(ruleId), entry.value, reason: '起始日 ${entry.key}');
    }
  });
}
