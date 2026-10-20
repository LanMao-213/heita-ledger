// 「清空全部数据」与「记完这一笔一定看得见」的自检。
//
// 这两条是 1.4.1 真机上暴露出来的问题，都属于「界面什么都不说，数据已经错了」
// 那一类，靠肉眼走查很难稳定复现，所以钉成测试：
//
// 1) 清空：删除与重建必须原子。1.4.1 是「事务里只删、事务外 seed」，
//    seed 撞 setting 主键抛异常 → 数据删了一半、界面没刷新 → 用户看到
//    「点了没反应、数据还在」，冷启动后当前账本指向已删除的账本。
// 2) 记账后可见：游标停在别的期、或明细上挂着筛选时，新记的一笔也必须出现
//    —— 否则用户以为没存上，会重复记一遍。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/cycle.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_wipe.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

late int _cat;
late int _acc;

/// 记一笔普通支出，返回流水 id
Future<int> _addExpense(Store s, {int cents = 12800, String? date}) =>
    Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.expense,
        amountCents: cents,
        date: date ?? Fmt.today(),
        categoryId: _cat,
        accountId: _acc,
        note: '午饭',
      ),
    );

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
    _cat = Store.i.expenseCats.first.id;
    _acc = Store.i.accounts.first.id;
  });

  group('清空全部数据', () {
    test('不抛异常，账目清零，默认账本/账户/分类重建', () async {
      await _addExpense(Store.i);
      await Repo.setBudget(
        ledgerId: Store.i.ledgerId,
        periodStart: Store.i.cycleFrom,
        categoryId: null,
        amountCents: 300000,
      );

      final before = await Repo.rangeListTxns(
        ledgerId: Store.i.ledgerId,
        from: Store.i.cycleFrom,
        to: Store.i.cycleTo,
      );
      expect(before, hasLength(1), reason: '前提：清空前有一笔');

      // 1.4.1 这里会抛 SqliteException(1555) UNIQUE constraint failed: setting.k
      await Db.wipeAllData();

      final db = await Db.open();
      expect(await db.query('txn'), isEmpty);
      expect(await db.query('debt'), isEmpty);
      expect(await db.query('budget'), isEmpty);
      expect(await db.query('txn_template'), isEmpty);
      expect(await db.query('ledger'), hasLength(1));
      expect(await db.query('account'), hasLength(4));
      expect(
        await db.query('category'),
        isNotEmpty,
        reason: '分类必须重建，否则记账没有分类可选',
      );
    });

    test('清空后 current_ledger_id 指向真实存在的账本，还能继续记账', () async {
      await _addExpense(Store.i);
      await Db.wipeAllData();

      // 库没问题还不够：Store 必须真的重开库并把状态换到新账本上
      await Store.i.reboot();
      final s = Store.i;
      expect(s.ledgerId, greaterThan(0));
      expect(s.expenseCats, isNotEmpty);
      expect(s.accounts, hasLength(4));
      expect(s.txns, isEmpty);

      final db = await Db.open();
      final rows = await db.query(
        'setting',
        where: 'k = ?',
        whereArgs: ['current_ledger_id'],
      );
      expect(rows, hasLength(1), reason: 'setting 里只该有一条当前账本');
      expect(rows.first['v'], '${s.ledgerId}');

      // 清空之后记的一笔要真的能落库、能查出来
      _cat = s.expenseCats.first.id;
      _acc = s.accounts.first.id;
      await _addExpense(s, cents: 6600);
      await s.afterTxnChange();
      expect(s.txns, hasLength(1));
      expect(s.txns.first.amountCents, 6600);
    });

    test('setting 里的旧账本 id 已失效时自愈到现存账本', () async {
      await Repo.setSetting('current_ledger_id', '99999');
      final db = await Db.open();
      final ledgers = await db.query('ledger');
      expect(ledgers, hasLength(1));

      final id = await Repo.currentLedgerId();
      expect(id, ledgers.first['id']);
      expect(
        await Repo.getSetting('current_ledger_id'),
        '${ledgers.first['id']}',
      );
    });
  });

  group('记完一笔一定看得见', () {
    test('游标停在上一期时，记账后自动对齐到这笔所在的期', () async {
      final s = Store.i;
      // 往后退一期，模拟用户翻过周期条后忘了回来
      await s.shiftCycle(-1);
      final viewingFrom = s.cycleFrom;

      final date = Fmt.today();
      await _addExpense(s, cents: 3300);
      await s.afterTxnInserted(
        date: date,
        periodStart: Repo.periodFor(
          Txn(
            id: 0,
            ledgerId: s.ledgerId,
            type: TxnType.expense,
            amountCents: 3300,
            date: date,
            categoryId: _cat,
          ),
          1,
          const {},
          liftToNext: false,
        ),
      );

      expect(s.cycleFrom, isNot(viewingFrom), reason: '游标应该被搬到今天这一期');
      expect(s.txns, hasLength(1));
      expect(s.visibleTxns, hasLength(1), reason: '这笔必须出现在明细里');
    });

    test('明细挂着筛选时，记账后清掉筛选，这笔仍然可见', () async {
      final s = Store.i;
      await _addExpense(s, cents: 9900);
      await s.afterTxnChange();

      // 筛一个这笔一定不满足的条件：≥ 100 元
      await s.applyFilter(const TxnFilter(minCents: 10000));
      expect(s.filtering, isTrue);
      expect(s.visibleTxns, isEmpty);

      final date = Fmt.today();
      await _addExpense(s, cents: 3300);
      await s.afterTxnInserted(
        date: date,
        periodStart: periodStartOf(date, s.cycleStartDay),
      );

      expect(s.filtering, isFalse, reason: '刚记的一笔不能还被旧条件挡着');
      expect(s.visibleTxns, hasLength(2));
    });

    test('从别的 tab 记账后回到明细页', () async {
      final s = Store.i;
      s.switchTab(2);
      expect(s.tabIndex, 2);

      final date = Fmt.today();
      await _addExpense(s, cents: 1000);
      await s.afterTxnInserted(
        date: date,
        periodStart: periodStartOf(date, s.cycleStartDay),
      );

      expect(s.tabIndex, 0);
    });
  });
}
