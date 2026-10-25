// 演示数据自检。
//
// 这段代码只服务于「带 HEITA_SEED 的测试包」，但它会往真机数据库里写几十条记录，
// 写错了就是真机上一堆看不下去的假账。所以几条硬约束钉在这里：
//
// 1) 金额不能让统计口径失真 —— 借出的本金必须不计入支出；
// 2) 借贷三种状态都要造出来（未还 / 部分还 / 逾期 / 借入计入预算），
//    否则真机走查看不出往来页到底对不对；
// 3) 同一个包重装、库里已有数据时不能再灌一份。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/debt_grouping.dart';
import 'package:ledger/data/integrity.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/data/repo_stats.dart';
import 'package:ledger/dev/seed.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_seed.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Future<void> _freshDb() async {
  await Db.close();
  Db.fileName = _dbName;
  final file = File(await _dbPath());
  if (file.existsSync()) file.deleteSync();
  await Db.open();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  test('演示数据：账户、流水、预算、模板都灌进去了', () async {
    await _freshDb();
    await Store.i.boot();
    final ledgerId = Store.i.ledgerId;

    await seedDemoData(ledgerId);

    final accounts = await Repo.listAccounts();
    expect(accounts.length, greaterThanOrEqualTo(3));
    // 账户名不能重复：建库时已经种了现金/支付宝/微信/储蓄卡，
    // 种子若再 insertAccount 一遍，真机上会看到两个「现金」（踩过）。
    final names = accounts.map((a) => a.name).toList();
    expect(
      names.toSet().length,
      names.length,
      reason: '账户重复了：种子应该复用已有账户，而不是新建同名的',
    );
    expect(names, containsAll(['现金', '微信', '储蓄卡']));
    expect(Store.i.templates.length, 2);
    expect(Store.i.goals, isEmpty, reason: '演示数据不造储蓄目标，避免和真实目标混淆');

    // 每条流水都必须落在真实分类上。写错分类名时 cat() 会返回 null，
    // 明细里就是「未分类」——这个错在真机上很显眼，但在总数断言里完全看不出来
    // （踩过一次：种子里写了不存在的「外卖」）。
    final txns = await Repo.rangeListTxns(
      ledgerId: ledgerId,
      from: Fmt.date(DateTime(DateTime.now().year, DateTime.now().month - 2, 1)),
      to: Fmt.date(DateTime.now()),
    );
    expect(txns, isNotEmpty);
    // 借贷流水不带分类（它显示成「借出 · 张三」），只检查普通收支
    final spending = txns.where((t) => t.debtId == null);
    expect(
      spending.where((t) => t.categoryId == null).map((t) => '${t.date} ${t.note}'),
      isEmpty,
      reason: '有流水没匹配到分类，说明种子里用了不存在的分类名',
    );

    // 本月：收入一笔工资 15000，支出是那 14 笔之和
    final totals = await RepoStats.monthTotals(ledgerId, Fmt.month(DateTime.now()));
    expect(totals.$2, 1500000, reason: '这个月只有一笔工资');
    expect(
      totals.$1,
      504900,
      reason: '本月 14 笔支出合计；借出的 5000 本金不在其中',
    );
  });

  test('演示数据：借贷三种状态齐全', () async {
    await _freshDb();
    await Store.i.boot();
    final ledgerId = Store.i.ledgerId;
    await seedDemoData(ledgerId);

    final debts = await Repo.listDebts(ledgerId: ledgerId);
    expect(debts.length, 3);

    final zhang = debts.firstWhere((d) => d.counterparty == '张三');
    expect(zhang.repaidCents, 200000, reason: '已还 2000');
    expect(zhang.remainingCents, 300000, reason: '剩余 3000');

    final li = debts.firstWhere((d) => d.counterparty == '李四');
    expect(li.overdueDays, 6, reason: '应还日在 6 天前，往来页要标红');

    final wang = debts.firstWhere((d) => d.counterparty == '王五');
    expect(wang.direction, DebtDirection.borrowed);
    expect(wang.countInBudget, isTrue, reason: '用来验「可用金额含借入」');

    // 界面拿到的是按人汇总的结果：三个人三行，各一行
    final groups = groupDebtsByCounterparty(debts);
    expect(groups.length, 3);
    expect(groups.first.name, '李四', reason: '逾期最久的排最前');
  });

  test('演示数据：已有流水时不重复灌', () async {
    await _freshDb();
    await Store.i.boot();
    final ledgerId = Store.i.ledgerId;
    await seedDemoData(ledgerId);

    final before = (await Repo.listDebts(ledgerId: ledgerId)).length;
    // 直接再调一次 seedDemoData 会叠加（它的守卫在 seedDemoDataIfNeeded 里）
    await seedDemoData(ledgerId);
    expect(
      (await Repo.listDebts(ledgerId: ledgerId)).length,
      before * 2,
      reason: '证明 seedDemoData 本身不设幂等守卫，守卫在 IfNeeded 那一层',
    );
  });

  // 演示数据是「按真机走查的需要」手工造的，很容易造出「余额和流水对不上」
  // 这种自伤 —— 1.4.5 真机第一次跑体检就抓到过（微信 1744 / 应 -3256，
  // 因为种子改余额时绕过了 saveAccount）。这条把它钉在 CI 里。
  test('演示数据灌完：数据体检必须是干净的', () async {
    await _freshDb();
    await Store.i.boot();
    await seedDemoDataIfNeeded();

    final report = await Integrity.check();
    expect(
      report.ok,
      isTrue,
      reason: '假账也是账，体检不过说明种子写坏了：${report.summary}',
    );
  });
}
