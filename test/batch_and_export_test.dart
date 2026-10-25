// 批量改分类 + 按筛选导出。
//
// 两件事各有一个人为失误的高发点，用测试钉住：
//   1. 批量改分类**不能改余额**（分类不参与余额计算），但很多人下意识会去
//      「顺手更新一下账户」——那一下就把不变量破了；
//   2. 导出**必须和列表同一份条件**。行数对不上是这类功能最典型的投诉。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_batch_export.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

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

  Future<List<int>> seedThree() async {
    await Store.i.boot();
    final s = Store.i;
    final acc = (await Repo.listAccounts()).first;
    final ids = <int>[];
    for (var i = 1; i <= 3; i++) {
      ids.add(
        await Repo.insertTxn(
          Txn(
            id: 0,
            ledgerId: s.ledgerId,
            type: TxnType.expense,
            amountCents: 1000 * i,
            date: '2026-09-0$i',
            accountId: acc.id,
          ),
        ),
      );
    }
    return ids;
  }

  group('批量改分类', () {
    test('三条一起改，返回 3 且余额不变', () async {
      final ids = await seedThree();
      final s = Store.i;
      final before = (await Repo.listAccounts()).first.balanceCents;

      final cats = await Repo.listCategories(s.ledgerId, type: TxnType.expense);
      final target = cats.firstWhere((c) => c.parentId == null);

      final n = await Repo.batchSetCategory(
        ledgerId: s.ledgerId,
        txnIds: ids,
        categoryId: target.id,
      );
      expect(n, 3);

      final after = (await Repo.listAccounts()).first.balanceCents;
      expect(after, before, reason: '分类不参与余额计算，批量改完余额必须一模一样');

      final dumped = await Repo.txnForExport(ledgerId: s.ledgerId);
      expect(dumped.every((t) => t.categoryId == target.id), isTrue);
    });

    test('空列表直接返回 0，不执行 SQL', () async {
      await Store.i.boot();
      final n = await Repo.batchSetCategory(
        ledgerId: Store.i.ledgerId,
        txnIds: const [],
        categoryId: 1,
      );
      expect(n, 0);
    });

    test('别的账本的 id 混进来不会被误改', () async {
      final ids = await seedThree();
      final s = Store.i;
      // 用一个不存在的账本 id 去改，应当一条都不命中
      final n = await Repo.batchSetCategory(
        ledgerId: 99999,
        txnIds: ids,
        categoryId: 1,
      );
      expect(n, 0);

      final dumped = await Repo.txnForExport(ledgerId: s.ledgerId);
      expect(dumped.every((t) => t.categoryId == null), isTrue);
    });

    test('可以清空分类（传 null = 未分类）', () async {
      final ids = await seedThree();
      final s = Store.i;
      await Repo.batchSetCategory(
        ledgerId: s.ledgerId,
        txnIds: ids,
        categoryId: 1,
      );
      await Repo.batchSetCategory(
        ledgerId: s.ledgerId,
        txnIds: ids,
        categoryId: null,
      );
      final dumped = await Repo.txnForExport(ledgerId: s.ledgerId);
      expect(dumped.every((t) => t.categoryId == null), isTrue);
    });
  });

  group('按筛选导出', () {
    test('无筛选 = 全部', () async {
      await seedThree();
      final all = await Repo.txnForExport(ledgerId: Store.i.ledgerId);
      expect(all.length, 3);
    });

    test('日期区间筛选只命中区间内的', () async {
      await seedThree();
      final part = await Repo.txnForExport(
        ledgerId: Store.i.ledgerId,
        filter: const TxnFilter(dateFrom: '2026-09-02', dateTo: '2026-09-03'),
      );
      expect(part.length, 2);
      expect(part.map((t) => t.date), ['2026-09-02', '2026-09-03']);
    });

    test('导出行数与列表行数一致（同一份 WHERE）', () async {
      await seedThree();
      const f = TxnFilter(type: TxnType.expense);
      final (list, _) = await Repo.searchTxns(
        ledgerId: Store.i.ledgerId,
        filter: f,
      );
      final exported = await Repo.txnForExport(
        ledgerId: Store.i.ledgerId,
        filter: f,
      );
      expect(exported.length, list.length, reason: '导出和列表必须是同一份条件');
    });

    test('条件互斥时导出为空而不是退回全部', () async {
      await seedThree();
      final none = await Repo.txnForExport(
        ledgerId: Store.i.ledgerId,
        filter: const TxnFilter(minCents: 999999),
      );
      expect(none, isEmpty);
    });
  });
}
