// 删除账户 = 把余额和流水并到另一个账户。
//
// 为什么单独测一条：`txn.account_id` 没有外键约束（见 db.dart），直接
// `DELETE FROM account` 只会把账户删掉，流水留在库里指向一个不存在的
// 账户 —— 明细里那几笔解析不出账户名，总资产又少了一块。这条链路写错
// 不报错、不崩，只是数字慢慢不对，所以用测试钉住。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_account_delete.db';

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

  test('合并账户：余额相加、流水改挂、不留孤儿记录', () async {
    await Store.i.boot();
    final s = Store.i;

    // 保证至少两个账户
    while (s.accounts.length < 2) {
      await Repo.insertAccount(
        Account(id: 0, name: '测试账户${s.accounts.length + 1}'),
      );
      await s.afterAccountChange();
    }
    final a = s.accounts[0];
    final b = s.accounts[1];

    // a 记三笔，b 记一笔（b 也要有流水，才能验证「两边都不丢」）
    final cat = s.expenseCats.first.id;
    for (final cents in [1000, 2000, 3000]) {
      await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.expense,
          amountCents: cents,
          date: Fmt.today(),
          categoryId: cat,
          accountId: a.id,
          note: '',
        ),
      );
    }
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.expense,
        amountCents: 500,
        date: Fmt.today(),
        categoryId: cat,
        accountId: b.id,
        note: '',
      ),
    );
    await s.afterTxnChange();

    final balA = s.accounts.firstWhere((x) => x.id == a.id).balanceCents;
    final balB = s.accounts.firstWhere((x) => x.id == b.id).balanceCents;
    final worthBefore = s.netWorthCents;
    final countBefore = await Repo.accountTxnCount(a.id);
    expect(countBefore, 3, reason: 'a 名下应有 3 笔');

    await Repo.mergeAccount(from: a.id, to: b.id);
    await s.afterAccountChange();
    await s.afterTxnChange();

    // 1. a 没了
    expect(s.accounts.any((x) => x.id == a.id), isFalse);
    // 2. b 的余额 = 原来的和
    expect(
      s.accounts.firstWhere((x) => x.id == b.id).balanceCents,
      balB + balA,
      reason: '净资产的转移必须一分不差',
    );
    // 3. 三笔流水还在，且挂在 b 名下
    expect(await Repo.accountTxnCount(b.id), 4);
    // 4. 没有指向已删账户的孤儿流水
    final db = await Db.open();
    final orphans = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM txn t
      WHERE (t.account_id IS NOT NULL AND t.account_id NOT IN (SELECT id FROM account))
         OR (t.to_account_id IS NOT NULL AND t.to_account_id NOT IN (SELECT id FROM account))
    ''');
    expect((orphans.first['c'] as int?) ?? 0, 0, reason: '不允许留下孤儿流水');
    // 5. 总资产不变（钱没少，只是换了个账户）
    expect(s.netWorthCents, worthBefore);
  });

  test('合并账户：删掉双方之间的转账，避免自转账', () async {
    await Store.i.boot();
    final s = Store.i;
    while (s.accounts.length < 2) {
      await Repo.insertAccount(
        Account(id: 0, name: '测试账户${s.accounts.length + 1}'),
      );
      await s.afterAccountChange();
    }
    final a = s.accounts[0];
    final b = s.accounts[1];

    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.transfer,
        amountCents: 2000,
        date: Fmt.today(),
        accountId: a.id,
        toAccountId: b.id,
        note: 'a → b',
      ),
    );
    await s.afterTxnChange();

    await Repo.mergeAccount(from: a.id, to: b.id);
    await s.afterAccountChange();

    final db = await Db.open();
    final self = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM txn WHERE account_id = ? AND to_account_id = ?',
      [b.id, b.id],
    );
    expect((self.first['c'] as int?) ?? 0, 0, reason: '合并后不该留下自转账');
  });
}
