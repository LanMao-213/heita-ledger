// 明细分页：游标（keyset）vs 偏移量（offset）。
//
// 为什么要这份测试：`period_all_page` 原先用 `offset: _txns.length` 翻页。
// 这个写法在「只读一遍」的场景没问题，但用户是可以**一边翻一边记账**的 ——
// 只要中途插进来一条新流水，整个列表就后移一位：
//
//   第 1 页：[E, D]        （offset 0，取 2 条）
//   插入 F（日期最新）→ [F, E, D, C, B, A]
//   第 2 页：[D, C]        （offset 2）← D 重复了，而本该出现的 B 被跳过
//
// 游标翻页从「上一页最后一条」之后继续取，插入只会影响列表顶部，
// 后面几页完全不受影响。
//
// 这份测试同时钉住两件事：
//   1. 游标翻页的结果与「一次性取完」逐条一致（顺序、条数都对）；
//   2. offset 模式确实会重复（这条是反例，用来解释为什么值得改）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_keyset_paging.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<void> _removeDbFile() async {
  final f = File(await _dbPath());
  if (f.existsSync()) f.deleteSync();
}

Future<int> _ledgerId(Database db) async =>
    (await db.query('ledger')).first['id']! as int;

/// 直接插流水，绕开 `Repo.addTxn` 的余额维护 —— 这里只关心列表顺序。
Future<int> _insertTxn(Database db, int ledgerId, String date, int cents) {
  return db.insert('txn', {
    'ledger_id': ledgerId,
    'type': 'expense',
    'amount_cents': cents,
    'date': date,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await Db.close();
    Db.fileName = _dbName;
    await _removeDbFile();
  });

  tearDown(() async {
    await Db.close();
    await _removeDbFile();
  });

  test('游标翻页：与一次性取完的 id 序列逐条一致', () async {
    await Db.open();
    final db = Db.cached!;
    final id = await _ledgerId(db);

    // 同一天多条 + 跨天，专门覆盖「date 相同要靠 id 破平」这条路径
    await _insertTxn(db, id, '2026-10-01', 100);
    await _insertTxn(db, id, '2026-10-02', 200);
    await _insertTxn(db, id, '2026-10-02', 300);
    await _insertTxn(db, id, '2026-10-03', 400);
    await _insertTxn(db, id, '2026-10-03', 500);

    const from = '2026-10-01';
    const to = '2026-10-31';

    final all = await Repo.rangeListTxns(
      ledgerId: id,
      from: from,
      to: to,
      basis: DateBasis.date,
      limit: 100,
    );
    expect(all.length, 5);

    final paged = <Txn>[];
    String? afterDate;
    int? afterId;
    while (true) {
      final batch = await Repo.rangeListTxns(
        ledgerId: id,
        from: from,
        to: to,
        basis: DateBasis.date,
        limit: 2,
        afterDate: afterDate,
        afterId: afterId,
      );
      if (batch.isEmpty) break;
      paged.addAll(batch);
      afterDate = batch.last.date;
      afterId = batch.last.id;
      if (batch.length < 2) break;
    }

    expect(
      paged.map((t) => t.id).toList(),
      all.map((t) => t.id).toList(),
      reason: '分页取出来的顺序必须和一次性取完完全一致',
    );
  });

  test('游标翻页：中途插入新流水，后续页不重复也不遗漏', () async {
    await Db.open();
    final db = Db.cached!;
    final id = await _ledgerId(db);

    await _insertTxn(db, id, '2026-10-01', 100);
    await _insertTxn(db, id, '2026-10-02', 200);
    await _insertTxn(db, id, '2026-10-03', 300);
    await _insertTxn(db, id, '2026-10-04', 400);

    const from = '2026-10-01';
    const to = '2026-10-31';

    // 第一页取 2 条（最新两天）
    final first = await Repo.rangeListTxns(
      ledgerId: id,
      from: from,
      to: to,
      basis: DateBasis.date,
      limit: 2,
    );
    expect(first.length, 2);

    // 用户这时又记了一笔，日期最新 —— 它排在列表顶部
    await _insertTxn(db, id, '2026-10-05', 500);

    final second = await Repo.rangeListTxns(
      ledgerId: id,
      from: from,
      to: to,
      basis: DateBasis.date,
      limit: 2,
      afterDate: first.last.date,
      afterId: first.last.id,
    );

    final seen = {...first.map((t) => t.id), ...second.map((t) => t.id)};
    expect(
      seen.length,
      first.length + second.length,
      reason: '两页之间不允许出现重复条目',
    );
    expect(
      second.map((t) => t.amountCents).toList(),
      [200, 100],
      reason: '第二页应接着第一页往后取，新插入的那笔不参与',
    );
  });

  test('反例：offset 模式在同一情形下会重复一条', () async {
    await Db.open();
    final db = Db.cached!;
    final id = await _ledgerId(db);

    await _insertTxn(db, id, '2026-10-01', 100);
    await _insertTxn(db, id, '2026-10-02', 200);
    await _insertTxn(db, id, '2026-10-03', 300);
    await _insertTxn(db, id, '2026-10-04', 400);

    const from = '2026-10-01';
    const to = '2026-10-31';

    final first = await Repo.rangeListTxns(
      ledgerId: id,
      from: from,
      to: to,
      basis: DateBasis.date,
      limit: 2,
    );

    await _insertTxn(db, id, '2026-10-05', 500);

    final second = await Repo.rangeListTxns(
      ledgerId: id,
      from: from,
      to: to,
      basis: DateBasis.date,
      limit: 2,
      offset: first.length,
    );

    final overlap = second
        .map((t) => t.id)
        .where((tid) => first.any((t) => t.id == tid))
        .toList();
    expect(
      overlap,
      isNotEmpty,
      reason: '这条反例说明 offset 会重复；如果哪天它不重复了，说明排序变了，'
          '需要重新审视游标条件是否还对得上',
    );
  });
}
