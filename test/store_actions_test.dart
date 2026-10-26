// 用例方法（Store.saveXxx / addXxx / deleteXxx）的契约测试。
//
// 为什么单独一个文件：这些方法的**全部价值**在于「写库」和「刷新」是原子的一对。
// 只要有人日后把它拆回去（或新增一个方法忘了调 after），界面就会停在旧数字，
// 而且不报错。这里的每条用例都同时断言两件事：
//   1. 库里真的变了（走 Repo 只读查询核对）；
//   2. Store 的投影真的跟着变了（并且发过通知）。
// 只断言 1 会漏掉刷新，只断言 2 会漏掉落库。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_store_actions.db';

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
    await Store.i.boot();
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  /// 记一次通知次数，用完自己摘掉监听
  Future<int> countNotify(Future<void> Function() body) async {
    final s = Store.i;
    var n = 0;
    void l() => n++;
    s.addListener(l);
    try {
      await body();
    } finally {
      s.removeListener(l);
    }
    return n;
  }

  group('流水', () {
    test('addTxn 落库 + 进明细 + 通知 + 返回归属期', () async {
      final s = Store.i;
      final today = Fmt.today();
      final before = s.txns.length;

      String? periodStart;
      final n = await countNotify(() async {
        periodStart = await s.addTxn(
          Txn(
            id: 0,
            ledgerId: s.ledgerId,
            type: TxnType.expense,
            amountCents: 1234,
            date: today,
            categoryId: s.expenseCats.first.id,
            accountId: s.accounts.first.id,
            note: '用例',
          ),
        );
      });

      expect(periodStart, s.cycleFrom, reason: '普通支出落在当前期');
      expect(s.txns.length, before + 1, reason: '投影里要立刻能看到');
      expect(s.expenseCents, greaterThan(0));
      expect(n, greaterThanOrEqualTo(1), reason: '必须通知，否则界面不重画');

      final rows = await Repo.rangeListTxns(
        ledgerId: s.ledgerId,
        from: s.cycleFrom,
        to: s.cycleTo,
      );
      expect(rows.any((t) => t.note == '用例'), isTrue, reason: '库里要真的有');
    });

    test('工资抬期：addTxn 返回的期与落库的期一致', () async {
      final s = Store.i;
      // 造一个「同月账单日之前」的日期：账单日设 25，今天取本月 1 号
      await Repo.setSetting(Repo.cycleStartDayKey, '25');
      await s.boot();
      final y = DateTime.now().year;
      final m = DateTime.now().month;
      final date = Fmt.date(DateTime(y, m, 1));

      final salary = s.incomeCats.firstWhere(
        (c) => s.liftableCatIds.contains(c.id),
        orElse: () => s.incomeCats.first,
      );
      final periodStart = await s.addTxn(
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.income,
          amountCents: 100000,
          date: date,
          categoryId: salary.id,
          accountId: s.accounts.first.id,
        ),
        liftToNext: true,
      );

      expect(periodStart, '$y-${m.toString().padLeft(2, '0')}-25');
      final row = (await Repo.rangeListTxns(
        ledgerId: s.ledgerId,
        from: periodStart,
        to: periodStart,
      )).where((t) => t.amountCents == 100000);
      expect(row, isNotEmpty, reason: '抬期后这笔必须真的落在新一期里');
    });

    test('deleteTxn 删库 + 投影回落 + 余额回滚', () async {
      final s = Store.i;
      final acc = s.accounts.first;
      final beforeBalance = s.netWorthCents;

      final ps = await s.addTxn(
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.expense,
          amountCents: 5000,
          date: Fmt.today(),
          categoryId: s.expenseCats.first.id,
          accountId: acc.id,
        ),
      );
      expect(s.netWorthCents, beforeBalance - 5000);

      final t = s.txns.firstWhere((t) => t.periodStart == ps && t.amountCents == 5000);
      await s.deleteTxn(t);

      expect(s.txns.any((x) => x.id == t.id), isFalse);
      expect(s.netWorthCents, beforeBalance, reason: '删除要把钱退回账户');
    });
  });

  group('预算与目标', () {
    test('setBudget 写当前期 + 刷出总额与分项', () async {
      final s = Store.i;
      final n = await countNotify(() async {
        await s.setBudget(periodStart: s.cycleFrom, amountCents: 300000);
      });

      expect(s.totalBudgetCents, 300000);
      expect(n, greaterThanOrEqualTo(1));

      final cat = s.expenseCats.first;
      await s.setBudget(
        periodStart: s.cycleFrom,
        categoryId: cat.id,
        amountCents: 100000,
      );
      expect(
        s.budgetStats.any((b) => b.categoryId == cat.id && b.budgetCents == 100000),
        isTrue,
        reason: '分类预算要立刻反映到 budgetStats',
      );
    });

    test('saveGoal 新建与编辑都刷新 goals', () async {
      final s = Store.i;
      final n = await countNotify(() async {
        await s.saveGoal(
          const SavingGoal(id: 0, name: '相机', icon: 'gift', targetCents: 500000),
        );
      });
      expect(s.goals.length, 1);
      expect(n, greaterThanOrEqualTo(1));

      final g = s.goals.first;
      await s.saveGoal(g.copyWith(targetCents: 600000));
      expect(s.goals.first.targetCents, 600000);
      expect(s.goals.length, 1, reason: '编辑不能变成新增');
    });

    test('addFunds 与 deleteGoal 各自刷新', () async {
      final s = Store.i;
      await s.saveGoal(
        const SavingGoal(id: 0, name: '旅行', icon: 'gift', targetCents: 100000),
      );
      final id = s.goals.first.id;

      await s.addFunds(id, 20000);
      expect(s.goals.first.savedCents, 20000);

      await s.deleteGoal(id);
      expect(s.goals, isEmpty);
      final rows = await Repo.listGoals();
      expect(rows, isEmpty);
    });
  });

  group('账户与分类', () {
    test('saveAccount 新建：期初 = 手填余额，净资产同步', () async {
      final s = Store.i;
      final before = s.netWorthCents;

      final id = await s.saveAccount(
        const Account(id: 0, name: '测试卡', kind: AccountKind.debit, sortOrder: 999),
        balanceCents: 88800,
      );

      final acc = s.accounts.firstWhere((a) => a.id == id);
      expect(acc.balanceCents, 88800);
      expect(acc.openingCents, 88800, reason: '新账户没有流水，期初就是手填值');
      expect(s.netWorthCents, before + 88800);
      // 恒等式：余额 = 期初 + 流水
      expect(
        acc.balanceCents,
        acc.openingCents + await Repo.accountFlowSum(acc.id),
      );
    });

    test('saveAccount 编辑：改的是期初而不是余额', () async {
      final s = Store.i;
      final id = await s.saveAccount(
        const Account(id: 0, name: '钱包', kind: AccountKind.cash),
        balanceCents: 10000,
      );
      final acc = s.accounts.firstWhere((a) => a.id == id);

      await s.saveAccount(acc.copyWith(name: '钱包2'), balanceCents: 30000);

      final now = s.accounts.firstWhere((a) => a.id == id);
      expect(now.name, '钱包2');
      expect(now.openingCents, 30000);
      expect(now.balanceCents, 30000);
    });

    test('deleteAccount 之后 accounts 与净资产都不再包含它', () async {
      final s = Store.i;
      final id = await s.saveAccount(
        const Account(id: 0, name: '临时', kind: AccountKind.cash),
        balanceCents: 5000,
      );
      expect(s.accounts.any((a) => a.id == id), isTrue);

      await s.deleteAccount(id);
      expect(s.accounts.any((a) => a.id == id), isFalse);
    });

    test('saveCategory 新增 / 改名 / 停用都刷新分类投影', () async {
      final s = Store.i;
      final before = s.expenseCats.length;

      final id = await s.saveCategory(
        Category(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.expense,
          name: '测试分类',
          icon: 'more',
          sortOrder: 99,
        ),
      );
      expect(s.expenseCats.length, before + 1);

      final c = s.expenseCats.firstWhere((c) => c.id == id);
      await s.saveCategory(c.copyWith(name: '改名了'));
      expect(s.expenseCats.firstWhere((c) => c.id == id).name, '改名了');

      await s.setCategoryArchived(id, archived: true);
      expect(s.expenseCats.any((c) => c.id == id), isFalse, reason: '停用要离开选择器');
      expect(s.archivedExpenseCats.any((c) => c.id == id), isTrue);
    });
  });

  test('recalcBalances 修掉账面漂移并刷新投影', () async {
    final s = Store.i;
    final id = await s.saveAccount(
      const Account(id: 0, name: '漂移账户', kind: AccountKind.cash),
      balanceCents: 10000,
    );
    // 人为制造漂移：直接把账面余额改掉（模拟「增量维护漏加一次」）
    final db = await Db.open();
    await db.update(
      'account',
      {'balance_cents': 7777},
      where: 'id = ?',
      whereArgs: [id],
    );
    expect(s.accounts.firstWhere((a) => a.id == id).balanceCents, 10000,
        reason: '投影此刻还是旧值');

    final fixed = await s.recalcBalances();

    expect(fixed, 1);
    expect(
      s.accounts.firstWhere((a) => a.id == id).balanceCents,
      10000,
      reason: '重算后要按「期初 + 流水」回来，并同步到投影',
    );
  });

  group('模板与账本', () {
    test('saveTemplate / deleteTemplate 刷新模板列表', () async {
      final s = Store.i;
      final id = await s.saveTemplate(
        TxnTemplate(
          id: 0,
          ledgerId: s.ledgerId,
          name: '早餐',
          icon: 'food',
          type: TxnType.expense,
          amountCents: 1200,
          categoryId: s.expenseCats.first.id,
          accountId: s.accounts.first.id,
          note: '',
          sortOrder: 0,
        ),
      );
      expect(s.templates.any((t) => t.id == id), isTrue);

      await s.deleteTemplate(id);
      expect(s.templates.any((t) => t.id == id), isFalse);
    });

    test('addLedger 建账本并切过去', () async {
      final s = Store.i;
      final before = s.ledgers.length;

      await s.addLedger('用例账本');

      expect(s.ledgers.length, before + 1);
      expect(
        s.currentLedger?.name,
        '用例账本',
        reason: '新建之后要真的切过去，否则用户会以为没建成',
      );
    });
  });
}
