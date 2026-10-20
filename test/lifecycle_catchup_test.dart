// 「回到前台补记周期账单」的自检（1.4.4）。
//
// 背景：这个应用没有后台服务，所有「到点该做的事」都挂在「打开应用」这一刻。
// 1.4.3 之前只有冷启动一个触发点，而 Android 上应用常驻后台过夜是常态 ——
// 于是 1 号该扣的房租可能三天后才补记，中间那几天余额和预算都是错的。
//
// 加了第二个触发点之后，风险从「漏记」变成了「重复记」，所以下面这些条
// 重点钉的是幂等与隔离，而不是「能不能补上」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:ledger/widgets/detail/txn_row.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_lifecycle.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

late int _cat;
late int _acc;

/// 建一条「今天到期」的月度规则，默认金额 1000 元
Future<int> _addRule({
  required String note,
  int cents = 100000,
  String? nextRun,
  int? ledgerId,
  int? categoryId,
}) => Repo.insertRecurring(
  RecurringRule(
    id: 0,
    ledgerId: ledgerId ?? Store.i.ledgerId,
    type: TxnType.expense,
    amountCents: cents,
    // 别的账本用不了主账本的分类 id，传 null 让它走「未分类」
    categoryId: categoryId ?? (ledgerId == null ? _cat : null),
    accountId: _acc,
    note: note,
    nextRunDate: nextRun ?? Fmt.today(),
  ),
);

Future<int> _txnCount({int? ledgerId}) async {
  final db = await Db.open();
  final rows = await db.query(
    'txn',
    where: ledgerId == null ? null : 'ledger_id = ?',
    whereArgs: ledgerId == null ? null : [ledgerId],
  );
  return rows.length;
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
    // boot 之后闸已经打开，每个用例从干净状态开始
    Store.i.debugResetRecurringGates();
    _cat = Store.i.expenseCats.first.id;
    _acc = Store.i.accounts.first.id;
  });

  group('幂等：同一期不会记两遍', () {
    test('runDueRecurring 插过一次之后，日期被拨回去也不会重复插', () async {
      final ruleId = await _addRule(note: '房租');

      expect(await Repo.runDueRecurring(Store.i.ledgerId), 1);
      expect(await _txnCount(), 1);

      // 模拟最危险的那条路径：插入成功、但推进 next_run_date 之前进程被杀
      // （或者两个触发点几乎同时跑到这里）。日期还在今天 → 下一次扫描
      // 仍会命中这条规则，此时必须靠查重挡住。
      final rule = (await Repo.listRecurring(Store.i.ledgerId))
          .firstWhere((r) => r.id == ruleId);
      await Repo.updateRecurring(
        RecurringRule(
          id: rule.id,
          ledgerId: rule.ledgerId,
          type: rule.type,
          amountCents: rule.amountCents,
          categoryId: rule.categoryId,
          accountId: rule.accountId,
          note: rule.note,
          freq: rule.freq,
          interval: rule.interval,
          nextRunDate: Fmt.today(), // 拨回今天
          endDate: rule.endDate,
          enabled: rule.enabled,
        ),
      );

      expect(
        await Repo.runDueRecurring(Store.i.ledgerId),
        0,
        reason: '这一期已经有记录了，只推进日期、不再插一条',
      );
      expect(await _txnCount(), 1, reason: '房租不能变成两份');
    });

    test('同一个账本在同一天只扫一次', () async {
      await _addRule(note: '房租');

      expect(await Store.i.catchUpRecurring(), 1, reason: '第一次要补上');
      expect(await Store.i.catchUpRecurring(), 0, reason: '同一天再次回到前台不该重复扫（闸一）');
      expect(await _txnCount(), 1);
    });

    test('两次触发挨着发生，只产生一笔（闸二：复用同一个 Future）', () async {
      await _addRule(note: '房租');

      // 不 await 第一条，立刻发第二条 —— 模拟「冷启动还没跑完就回到前台」
      final a = Store.i.catchUpRecurring();
      final b = Store.i.catchUpRecurring();
      final results = await Future.wait([a, b]);

      expect(await _txnCount(), 1, reason: '并发触发不能插两笔');
      expect(results, [1, 1], reason: '两条调用拿到的是同一次执行的结果，而不是各自跑了一遍');
    });
  });

  group('限流按账本分开', () {
    test('切换账本时，新账本的欠账不会被上一个账本挡住', () async {
      // 主账本今天已经扫过
      expect(await Store.i.catchUpRecurring(), 0);

      final other = await Repo.insertLedger(const Ledger(id: 0, name: '家庭账本'));
      await _addRule(note: '物业费', ledgerId: other, nextRun: Fmt.today());

      await Store.i.switchLedger(other);
      expect(Store.i.recurringJustAdded, 1, reason: '限流必须按账本各算各的，否则切过去永远补不上');

      final rows = await (await Db.open()).query(
        'txn',
        where: 'ledger_id = ?',
        whereArgs: [other],
      );
      expect(rows, hasLength(1));
      expect(rows.first['note'], '物业费');
    });

    test('补记只写自己的账本，不会串到别的账本', () async {
      final other = await Repo.insertLedger(const Ledger(id: 0, name: '家庭账本'));
      await _addRule(note: '房租', nextRun: Fmt.today());
      await _addRule(note: '物业费', ledgerId: other, nextRun: Fmt.today());

      expect(await Repo.runDueRecurring(Store.i.ledgerId), 1);
      expect(await Repo.runDueRecurring(other), 1);

      expect(await _txnCount(ledgerId: Store.i.ledgerId), 1);
      expect(await _txnCount(ledgerId: other), 1);
    });
  });

  group('回到前台', () {
    test('同一天、同一个账本：什么都不做', () async {
      await _addRule(note: '房租');
      await Store.i.catchUpRecurring(); // 把今天的闸用掉
      final cycles = Store.i.cycleFrom;

      expect(await Store.i.onAppResumed(), 0);
      expect(Store.i.cycleFrom, cycles);
    });

    test('跨天回来：补记当天的账，并且余额跟着变', () async {
      await _addRule(note: '房租', cents: 100000);
      final before = Store.i.accounts.firstWhere((a) => a.id == _acc);
      final beforeNet = Store.i.netWorthCents;

      // 假装上一次是昨天
      Store.i.debugSetSeenDay('2000-01-01');
      final added = await Store.i.onAppResumed();

      expect(added, 1, reason: '跨天回来必须把到期的补上');
      final after = Store.i.accounts.firstWhere((a) => a.id == _acc);
      expect(
        after.balanceCents,
        before.balanceCents - 100000,
        reason: '补记会扣账户余额，界面上的数字必须同步，否则「明细多了一笔、余额没动」',
      );
      expect(Store.i.netWorthCents, beforeNet - 100000);
    });

    test('用户正停在历史期时，不把游标拽回今天', () async {
      await Store.i.shiftCycle(-1); // 翻到上一期看旧账
      final historic = Store.i.cycleFrom;

      Store.i.debugSetSeenDay('2000-01-01');
      await Store.i.onAppResumed();

      expect(Store.i.cycleFrom, historic, reason: '正在翻旧账时被拽回本月，等于抢用户的方向盘');
    });

    test('本来就在当前期：跨天回来会归位到新一期', () async {
      // 游标停在「上一期」但把它当成当前期在用是不可能的 —— 这里验证的是
      // 「停在当前期」的那条分支会跟着日期走
      expect(Store.i.isCurrentPeriod, isTrue, reason: '前提：boot 后停在本期');

      Store.i.debugSetSeenDay('2000-01-01');
      await Store.i.onAppResumed();

      expect(Store.i.isCurrentPeriod, isTrue);
    });
  });

  group('界面', () {
    testWidgets('周期账单在明细里带「周期」标记，手记的没有', (tester) async {
      await tester.runAsync(() async {
        await _addRule(note: '房租', cents: 100000);
        await Store.i.catchUpRecurring();
        await Store.i.loadCycle();
      });

      final auto = Store.i.txns.firstWhere((t) => t.recurringId != null);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TxnRow(txn: auto)),
        ),
      );
      expect(find.text('周期'), findsOneWidget);

      // 手记的一笔：不该有标记
      final manual = Txn(
        id: 0,
        ledgerId: Store.i.ledgerId,
        type: TxnType.expense,
        amountCents: 1200,
        date: Fmt.today(),
        categoryId: _cat,
        accountId: _acc,
        note: '午饭',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TxnRow(txn: manual)),
        ),
      );
      expect(find.text('周期'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
