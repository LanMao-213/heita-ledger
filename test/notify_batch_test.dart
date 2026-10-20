// 通知合并的自检（1.5.0）。
//
// 原来的问题：`afterTxnChange()` 里 `loadCycle()` 和 `loadStats()` 各自
// `notifyListeners()`，于是一次记账会触发**两次**全树重建 —— 中间那次的内容
// 永远被立刻覆盖，是纯白工。用户的感受是「记完账界面发沉」。
//
// 这里钉住：一次 afterTxnChange 只通知一次，而且通知时数据已经是新的
// （不能为了少通知而让界面看到旧值）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_notify_batch.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  late int catFood;
  late int accCash;
  final month = Fmt.month(DateTime.now());

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
    final s = Store.i;
    catFood = (await Repo.listCategories(
      s.ledgerId,
      type: TxnType.expense,
    )).firstWhere((c) => c.name == '餐饮').id;
    accCash = (await Repo.listAccounts()).first.id;
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  Future<int> spend(int cents) => Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: Store.i.ledgerId,
      type: TxnType.expense,
      amountCents: cents,
      date: '$month-16',
      categoryId: catFood,
      accountId: accCash,
    ),
  );

  test('一次记账只触发一次通知，且通知时数据已经是新的', () async {
    final s = Store.i;
    var notified = 0;
    // 通知时刻的数据快照：用来证明「通知的时候已经算完了」
    int? expenseAtNotify;

    void listener() {
      notified++;
      expenseAtNotify = s.expenseCents;
    }

    s.addListener(listener);
    addTearDown(() => s.removeListener(listener));

    final before = s.expenseCents;
    await spend(2000);
    await s.afterTxnChange();

    expect(
      notified,
      1,
      reason: 'loadCycle 与 loadStats 各发一次通知时这里是 2，合并后应为 1',
    );
    expect(s.expenseCents, before + 2000);
    expect(
      expenseAtNotify,
      before + 2000,
      reason: '通知发出时列表数字必须已经是新的，不能让人先看到旧值再刷一次',
    );
  });

  test('连续两次记账：每次各通知一次，不会互相吞掉', () async {
    final s = Store.i;
    var notified = 0;
    void listener() => notified++;
    s.addListener(listener);
    addTearDown(() => s.removeListener(listener));

    await spend(100);
    await s.afterTxnChange();
    await spend(200);
    await s.afterTxnChange();

    expect(notified, 2, reason: '合并只发生在单次操作内部，不能跨操作合并');
  });

  test('批量块里抛异常：仍然会通知一次，且不把界面卡在旧状态', () async {
    final s = Store.i;
    var notified = 0;
    void listener() => notified++;
    s.addListener(listener);
    addTearDown(() => s.removeListener(listener));

    await expectLater(
      s.batchNotify<void>(() async {
        s.switchTab(2); // 会 notify，但被合并
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );

    expect(
      notified,
      1,
      reason: '异常路径也要把攒下的通知发出去，否则界面会停在旧状态',
    );
  });
}
