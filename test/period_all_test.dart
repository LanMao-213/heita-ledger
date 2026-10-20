// 「明细被 500 条上限截断」这件事的自检（1.4.4）。
//
// 1.4.3 之前的行为是**静默丢弃**：概览卡的笔数走 SQL COUNT 是真实值，
// 列表只画前 500 条，两者对不上，而界面上一个字都不说 ——
// 用户看到的只是「数字和列表不一致」，会怀疑数据丢了。
//
// 现在两件事要钉住：
// 1) 截断必须被识别出来（正好 500 条时不能误报）；
// 2) 截断之后有路可走 —— 「本期全览」能分批把剩下的都取回来。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/period_all_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_period_all.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 直接把同一期的记录灌 n 条。
///
/// 不逐条走 `Repo.insertTxn`：那会一笔一个事务再算一次余额，620 条能跑十几秒，
/// 而这里要验的是「读取侧怎么处理条数」，写入路径不是被测对象。
Future<void> _seedTxns(int n) async {
  final db = await Db.open();
  final s = Store.i;
  final proto = await Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.expense,
      amountCents: 100,
      date: Fmt.today(),
      categoryId: s.expenseCats.first.id,
      accountId: s.accounts.first.id,
      note: '原型',
    ),
  );
  final row = (await db.query(
    'txn',
    where: 'id = ?',
    whereArgs: [proto],
  )).first;
  final batch = db.batch();
  for (var i = 1; i < n; i++) {
    batch.insert('txn', {...row}..remove('id'));
  }
  await batch.commit(noResult: true);
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
    await Store.i.boot();
  });

  group('截断识别', () {
    test('条数不足上限时不算截断', () async {
      await _seedTxns(3);
      await Store.i.loadCycle();

      expect(Store.i.txns, hasLength(3));
      expect(Store.i.txnTruncated, isFalse);
    });

    test('正好 500 条时不算截断（边界不能误报）', () async {
      await _seedTxns(Store.txnPageLimit);
      await Store.i.loadCycle();

      expect(Store.i.txns, hasLength(Store.txnPageLimit));
      expect(
        Store.i.txnTruncated,
        isFalse,
        reason: '多取一条的判断方式就是为了区分「正好 500」和「500 之外还有」',
      );
    });

    test('超过上限时置位，且列表停在 500 条', () async {
      await _seedTxns(Store.txnPageLimit + 20);
      await Store.i.loadCycle();

      expect(
        Store.i.txns,
        hasLength(Store.txnPageLimit),
        reason: '明细页一次最多画 500 条',
      );
      expect(Store.i.txnTruncated, isTrue);
      expect(
        Store.i.txnCount,
        Store.txnPageLimit + 20,
        reason: '概览卡的笔数是 SQL COUNT，本来就该是真实值',
      );
    });
  });

  group('本期全览的取数', () {
    test('按批取能拿全，且前后两批不重复', () async {
      const total = 430;
      await _seedTxns(total);
      await Store.i.loadCycle();

      final seen = <int>{};
      var offset = 0;
      while (true) {
        final batch = await Repo.rangeListTxns(
          ledgerId: Store.i.ledgerId,
          from: Store.i.cycleFrom,
          to: Store.i.cycleTo,
          limit: 200,
          offset: offset,
        );
        for (final t in batch) {
          seen.add(t.id);
        }
        offset += batch.length;
        if (batch.length < 200) break;
      }

      expect(seen, hasLength(total), reason: '分批累加必须正好等于总数，不能漏也不能重');
    });

    test('超过一屏的批量也不丢：620 条分 4 批取完', () async {
      const total = 620;
      await _seedTxns(total);
      await Store.i.loadCycle();

      var offset = 0;
      var rounds = 0;
      while (true) {
        final batch = await Repo.rangeListTxns(
          ledgerId: Store.i.ledgerId,
          from: Store.i.cycleFrom,
          to: Store.i.cycleTo,
          limit: 200,
          offset: offset,
        );
        offset += batch.length;
        rounds++;
        if (batch.length < 200) break;
      }

      expect(offset, total);
      expect(rounds, 4, reason: '200/200/200/20');
    });
  });
  group('本期全览页', () {
    testWidgets('一路滚到底能取完 620 条，最后一屏说明「已经是本期全部」', (tester) async {
      await tester.runAsync(() async {
        await _seedTxns(620);
        await Store.i.loadCycle();
      });

      await tester.pumpWidget(const MaterialApp(home: PeriodAllPage()));
      // 页面 initState 里就要读库：假时钟里那个 Future 回不来，
      // 必须放 runAsync 把真实 IO 跑完，再 pump 一帧
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('本期全览'), findsOneWidget);
      expect(find.text('共 620 笔'), findsOneWidget, reason: '表头必须是真实总数');

      final st = tester.state<ScrollableState>(find.byType(Scrollable).first);
      for (var i = 0; i < 60; i++) {
        st.position.jumpTo(st.position.maxScrollExtent);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
        if (find.textContaining('已经是本期全部').evaluate().isNotEmpty) break;
      }

      expect(
        find.textContaining('已经是本期全部 620 笔'),
        findsOneWidget,
        reason: '分批取完才说明「一条都没丢」，这正是 1.4.3 静默丢弃的反面',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
