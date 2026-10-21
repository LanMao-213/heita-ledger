import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/ui/pages/record/template_strip.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 模板排序与使用计数：reorder 重写成 0..n-1、新模板 MAX+1、recent 三级排序、touch。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  Future<int> tpl(String name, {int amount = 1000}) async => Repo.template.insert(
    TxnTemplate(
      ledgerId: await currentLedger(),
      name: name,
      type: TxnType.expense,
      amountCents: amount,
      categoryId: await topCategoryId(),
      accountId: await defaultAccountId(),
    ),
  );

  test('① 新模板追加到 MAX+1（不是插到最前）', () async {
    await tpl('A');
    await tpl('B');
    final int id = await tpl('C');

    final List<TxnTemplate> all = await Repo.template.all(await currentLedger());
    expect(all.map((TxnTemplate t) => t.name).toList(), <String>['A', 'B', 'C']);
    expect(all.map((TxnTemplate t) => t.sortOrder).toList(), <int>[0, 1, 2]);
    expect(all.last.id, id);
  });

  test('① 拖拽后 sort_order 重写成 0..n-1（单事务）', () async {
    await tpl('A');
    await tpl('B');
    await tpl('C');
    final List<TxnTemplate> all = await Repo.template.all(await currentLedger());

    // 把 C 拖到最前
    await Repo.template.reorder(<int>[
      all[2].id!,
      all[0].id!,
      all[1].id!,
    ]);

    final List<TxnTemplate> after = await Repo.template.all(
      await currentLedger(),
    );
    expect(after.map((TxnTemplate t) => t.name).toList(), <String>['C', 'A', 'B']);
    expect(
      after.map((TxnTemplate t) => t.sortOrder).toList(),
      <int>[0, 1, 2],
      reason: '重编号成连续整数，不是「交换两个数」（交换会留洞）',
    );
  });

  test('④ recent(3)：use_count DESC → last_used_at DESC → sort_order', () async {
    final int a = await tpl('A');
    final int b = await tpl('B');
    final int c = await tpl('C');
    final int d = await tpl('D');

    await Repo.template.touch(b);
    await Repo.template.touch(b);
    await Repo.template.touch(c);

    final List<TxnTemplate> recent = await Repo.template.recent(
      await currentLedger(),
    );
    expect(recent.length, 3);
    expect(
      recent.map((TxnTemplate t) => t.name).toList(),
      <String>['B', 'C', 'A'],
      reason: 'B 用过 2 次；C 用过 1 次；A/D 没动过，按 sort_order 取 A',
    );
    expect(d, isPositive);
    expect(a, isPositive);
  });

  test('④ touch 让 use_count 与 last_used_at 一起变', () async {
    final int id = await tpl('早饭');

    await Repo.template.touch(id);

    final TxnTemplate t = (await Repo.template.all(await currentLedger())).single;
    expect(t.useCount, 1);
    expect(t.lastUsedAt, isNotNull);
  });

  test('面板模板条最多 3 个（纯函数）', () async {
    await tpl('A');
    await tpl('B');
    await tpl('C');
    await tpl('D');
    final List<TxnTemplate> all = await Repo.template.all(await currentLedger());

    expect(recentTemplates(all).length, 3);
    expect(recentTemplates(all, limit: 2).length, 2);
  });

  test('④ 手敲的同类型+同分类+同金额也算命中模板', () async {
    final int ledger = await currentLedger();
    final int cat = await topCategoryId();
    final int acc = await defaultAccountId();
    final int tplId = await Repo.template.insert(
      TxnTemplate(
        ledgerId: ledger,
        name: '早饭',
        type: TxnType.expense,
        amountCents: 1000,
        categoryId: cat,
        accountId: acc,
      ),
    );
    final List<TxnTemplate> all = await Repo.template.all(ledger);

    final Txn hit = mkTxn(
      ledgerId: ledger,
      amountCents: 1000,
      categoryId: cat,
      accountId: acc,
    );
    expect(matchTemplateFor(all, hit)?.id, tplId);

    // 金额不同就不算
    expect(
      matchTemplateFor(all, hit.copyWith(amountCents: 2000)),
      isNull,
    );
    // 类型不同也不算
    expect(
      matchTemplateFor(all, hit.copyWith(type: TxnType.income)),
      isNull,
    );
  });

  test('③ 删模板不影响已经记过的账（txn.template_id 悬空不报错）', () async {
    final int ledger = await currentLedger();
    final int tplId = await tpl('早饭');
    final Txn saved = await Repo.saveTxn(
      mkTxn(
        ledgerId: ledger,
        amountCents: 1000,
        categoryId: await topCategoryId(),
        accountId: await defaultAccountId(),
        templateId: tplId,
        date: const LocalDate(2026, 10, 10),
      ),
      cycleStartDay: 1,
    );

    await Repo.template.delete(tplId);

    final List<Txn> all = await Repo.txn.allOfLedger(ledger);
    expect(all.length, 1);
    expect(all.single.id, saved.id);
    expect(
      all.single.templateId,
      tplId,
      reason: '悬空外键：历史账目照旧显示，不因为模板没了就丢',
    );
  });
}
