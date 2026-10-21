import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/db/schema.dart';
import 'package:heita_ledger/data/db/seeds.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 账本 repo：**I6（新建账本灌完整两级分类）** 是这一组的主角。
///
/// 原版 c-5 / b-1 的洞就是「新建账本只灌旧的扁平分类，且没有测试钉住」——
/// 于是它活到了 1.4.5。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  test('I6：新建账本灌完整两级分类（15 一级 + 73 子，支出 49 / 收入 24）', () async {
    final ({int id, SeedResult seed}) created = await Repo.ledger.insertLedger(
      name: '第二本',
    );

    expect(created.seed.topCount, 15);
    expect(created.seed.subCount, 73);

    final List<Category> cats = await Repo.category.all(created.id);
    expect(cats.where((Category c) => c.isTop).length, 15);
    expect(
      cats.where((Category c) => c.isChild && c.type == TxnType.expense).length,
      49,
    );
    expect(
      cats.where((Category c) => c.isChild && c.type == TxnType.income).length,
      24,
    );
  });

  test('I6：新建账本的分类数与主账本**逐项相等**', () async {
    final int mainId = await currentLedger();
    final ({int id, SeedResult seed}) created = await Repo.ledger.insertLedger(
      name: '第二本',
    );

    expect(await Repo.ledger.categoryCount(mainId), 88);
    expect(
      await Repo.ledger.categoryCount(created.id),
      await Repo.ledger.categoryCount(mainId),
    );
  });

  test('新建账本默认成为当前账本，并能从 setting 读到', () async {
    final ({int id, SeedResult seed}) created = await Repo.ledger.insertLedger(
      name: '旅行账本',
    );
    expect(await Db.readSetting('current_ledger_id'), '${created.id}');
    expect((await Repo.ledger.current())?.name, '旅行账本');
  });

  test('makeCurrent: false 不动当前指针', () async {
    final int before = await currentLedger();
    await Repo.ledger.insertLedger(name: '旁支', makeCurrent: false);
    expect(await currentLedger(), before);
  });

  test('改名：空名字被忽略，正常名字写回', () async {
    final int id = await currentLedger();
    await Repo.ledger.rename(id, '   ');
    expect((await Repo.ledger.current())?.name, '我的账本');
    await Repo.ledger.rename(id, '家庭账');
    expect((await Repo.ledger.current())?.name, '家庭账');
  });

  test('删当前账本 → 外键级联删分类与流水，指针自愈到剩下的那本', () async {
    final int first = await currentLedger();
    final ({int id, SeedResult seed}) second = await Repo.ledger.insertLedger(
      name: '第二本',
    );
    expect(await currentLedger(), second.id);

    await Repo.ledger.deleteLedger(second.id);

    expect(await Repo.ledger.categoryCount(second.id), 0, reason: '级联删分类');
    expect(await Db.rowCount(Tables.ledger), 1);
    expect(await currentLedger(), first, reason: '指针要自愈回第一本');
  });

  test('删掉唯一一本账本 → 自动重建一本（含完整两级分类）', () async {
    final int only = await currentLedger();
    await Repo.ledger.deleteLedger(only);

    final int rebuilt = await currentLedger();
    expect(rebuilt, greaterThan(0));
    expect(await Db.rowCount(Tables.ledger), 1);
    expect(await Repo.ledger.categoryCount(rebuilt), 88);
  });

  test('switchTo 只写指针，不动别的设置', () async {
    final ({int id, SeedResult seed}) second = await Repo.ledger.insertLedger(
      name: '第二本',
      makeCurrent: false,
    );
    await Db.writeSetting('theme.palette', 'aurora');

    await Repo.ledger.switchTo(second.id);

    expect(await currentLedger(), second.id);
    expect(await Db.readSetting('theme.palette'), 'aurora');
  });

  test('账本按 sort_order 升序返回', () async {
    await Repo.ledger.insertLedger(name: '第二本');
    await Repo.ledger.insertLedger(name: '第三本');
    final List<Ledger> ledgers = await Repo.ledger.all();
    expect(ledgers.map((Ledger l) => l.name), <String>['我的账本', '第二本', '第三本']);
  });
}
