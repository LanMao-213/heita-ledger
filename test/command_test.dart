// 写入网关（WriteGateway）的自检。
//
// 钉两件靠「看代码」无法确认的事：
// 1. **回滚真的生效** —— 命令里第二步抛异常时，第一步写入必须一起消失。
//    没有这条，"有事务"只是一句声明。
// 2. **不变量校验真的在跑** —— 余额被外部改坏之后再记一笔，
//    网关必须产生警告；而且**不能因此阻断这次记账**（用户不该被历史问题卡住）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/command.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_gateway.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 故意写到一半就炸：用来证明回滚。
class _HalfWriteThenBoom extends Command<void> {
  _HalfWriteThenBoom();

  @override
  Future<void> apply(WriteScope w) async {
    await w.insert('ledger', {
      'name': '半截账本',
      'icon': 'book',
      'sort_order': 99,
      'archived': 0,
      'created_at': '',
    });
    throw StateError('第二步失败，整个事务必须回滚');
  }
}

/// 不发 HTTP、不发通知，只用来验证「网关把作用域交进来时，前面写的能被自己读到」。
class _ReadOwnWrite extends Command<int> {
  @override
  Future<int> apply(WriteScope w) async {
    await w.insert('ledger', {
      'name': '自己看自己',
      'icon': 'book',
      'sort_order': 98,
      'archived': 0,
      'created_at': '',
    });
    final rows = await w.query(
      'ledger',
      where: 'name = ?',
      whereArgs: ['自己看自己'],
    );
    return rows.length;
  }
}

void main() {
  late int ledgerId;
  late int catFood;
  late int accCash;
  late int accBank;
  final month = Fmt.month(DateTime.now());

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();

    await Db.open();
    ledgerId = await Repo.currentLedgerId();
    catFood = await Repo.insertCategory(
      Category(id: 0, ledgerId: ledgerId, type: TxnType.expense, name: '餐饮'),
    );
    accCash = await Repo.insertAccount(const Account(id: 0, name: '现金'));
    accBank = await Repo.insertAccount(const Account(id: 0, name: '银行卡'));
  });

  tearDown(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  Future<int> ledgerCount() async {
    final db = await Db.open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM ledger');
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<int> balanceOf(int accountId) async {
    final db = await Db.open();
    final rows = await db.query(
      'account',
      columns: ['balance_cents'],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    return rows.first['balance_cents'] as int;
  }

  test('命令中途抛异常 → 前面写的一起回滚', () async {
    final before = await ledgerCount();

    await expectLater(
      WriteGateway.run(_HalfWriteThenBoom()),
      throwsA(isA<StateError>()),
    );

    expect(
      await ledgerCount(),
      before,
      reason: '第一条 insert 必须随事务一起消失，否则就是「写了一半」',
    );

    // 回滚之后连接仍然可用，下一条正常的写入不受影响
    final id = await WriteGateway.run(_ReadOwnWrite());
    expect(id, 1, reason: '事务内应该能读到自己刚写的行');
    expect(await ledgerCount(), before + 1);
  });

  test('insertTxn 走网关后余额与流水一致', () async {
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 2000,
        date: '$month-10',
        categoryId: catFood,
        accountId: accCash,
      ),
    );

    expect(await balanceOf(accCash), -2000);
    expect(
      WriteGateway.warnings,
      isEmpty,
      reason: '正常记账不该产生任何不变量警告',
    );
  });

  test('updateTxn 换账户：旧账户回滚、新账户生效', () async {
    final id = await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 3000,
        date: '$month-11',
        categoryId: catFood,
        accountId: accCash,
      ),
    );
    expect(await balanceOf(accCash), -3000);

    final db = await Db.open();
    final rows = await db.query('txn', where: 'id = ?', whereArgs: [id]);
    final old = Txn.fromMap(rows.first);
    await Repo.updateTxn(
      old,
      old.copyWith(
        amountCents: 5000,
        accountId: accBank,
      ),
    );

    expect(await balanceOf(accCash), 0, reason: '旧账户的 30.00 必须回滚');
    expect(await balanceOf(accBank), -5000, reason: '新账户按新金额扣');
    expect(WriteGateway.warnings, isEmpty);
  });

  test('deleteTxn 把余额还回去', () async {
    final id = await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.income,
        amountCents: 10000,
        date: '$month-12',
        accountId: accCash,
      ),
    );
    expect(await balanceOf(accCash), 10000);

    final db = await Db.open();
    final rows = await db.query('txn', where: 'id = ?', whereArgs: [id]);
    await Repo.deleteTxn(Txn.fromMap(rows.first));

    expect(await balanceOf(accCash), 0);
    expect(WriteGateway.warnings, isEmpty);
  });

  test('余额被外部改坏 → 校验产生警告，但不阻断这次记账', () async {
    // 模拟历史遗留的漂移（1.4.4 之前那种「有账没扣余额」的库）
    final db = await Db.open();
    await db.rawUpdate(
      'UPDATE account SET balance_cents = 12345 WHERE id = ?',
      [accCash],
    );

    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: ledgerId,
        type: TxnType.expense,
        amountCents: 500,
        date: '$month-13',
        categoryId: catFood,
        accountId: accCash,
      ),
    );

    expect(
      WriteGateway.warnings,
      isNotEmpty,
      reason: '校验必须真的跑起来，否则它只是装饰',
    );
    // 关键：警告不等于阻断 —— 用户不该因为历史数据问题记不了账
    expect(await balanceOf(accCash), 12345 - 500);
  });
}
