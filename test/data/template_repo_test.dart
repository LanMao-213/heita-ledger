import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 模板与目标：轻量 CRUD + 两个派生规则（最近 3 个、取钱不低于 0）。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  group('模板', () {
    test('插入自动排序，改名/删除生效', () async {
      final int ledger = await currentLedger();
      final int id = await Repo.template.insert(
        TxnTemplate(ledgerId: ledger, name: '早餐', type: TxnType.expense, amountCents: 800),
      );
      await Repo.template.insert(
        TxnTemplate(ledgerId: ledger, name: '地铁', type: TxnType.expense, amountCents: 500),
      );

      List<TxnTemplate> all = await Repo.template.all(ledger);
      expect(all.map((TxnTemplate t) => t.name), <String>['早餐', '地铁']);
      expect(all.first.sortOrder, 0);
      expect(all.last.sortOrder, 1);

      await Repo.template.update(
        (await Repo.template.all(ledger)).first.copyWith(name: '早饭'),
      );
      all = await Repo.template.all(ledger);
      expect(all.first.name, '早饭');

      await Repo.template.delete(id);
      expect((await Repo.template.all(ledger)).length, 1);
    });

    test('touch 累加使用次数与最后使用时间', () async {
      final int ledger = await currentLedger();
      final int id = await Repo.template.insert(
        TxnTemplate(ledgerId: ledger, name: '早餐', type: TxnType.expense),
      );
      await Repo.template.touch(id);
      await Repo.template.touch(id);

      final TxnTemplate t = (await Repo.template.all(ledger)).single;
      expect(t.useCount, 2);
      expect(t.lastUsedAt, isNotNull);
    });

    test('recent(3)：用过次数多的在前', () async {
      final int ledger = await currentLedger();
      final int a = await Repo.template.insert(
        TxnTemplate(ledgerId: ledger, name: 'A', type: TxnType.expense, sortOrder: 1),
      );
      await Repo.template.insert(
        TxnTemplate(ledgerId: ledger, name: 'B', type: TxnType.expense, sortOrder: 2),
      );
      final int c = await Repo.template.insert(
        TxnTemplate(ledgerId: ledger, name: 'C', type: TxnType.expense, sortOrder: 3),
      );
      await Repo.template.touch(c);
      await Repo.template.touch(c);
      await Repo.template.touch(a);

      final List<TxnTemplate> recent = await Repo.template.recent(ledger);
      expect(recent.first.name, 'C');
      expect(recent[1].name, 'A');
      expect(recent.length, 3);
    });

    test('reorder 按数组顺序重写', () async {
      final int ledger = await currentLedger();
      final int a = await Repo.template.insert(
        TxnTemplate(ledgerId: ledger, name: 'A', type: TxnType.expense),
      );
      final int b = await Repo.template.insert(
        TxnTemplate(ledgerId: ledger, name: 'B', type: TxnType.expense),
      );

      await Repo.template.reorder(<int>[b, a]);

      final List<TxnTemplate> all = await Repo.template.all(ledger);
      expect(all.map((TxnTemplate t) => t.name), <String>['B', 'A']);
    });
  });

  group('储蓄目标', () {
    test('插入 / 存钱 / 取钱（取超按 0 兜底）', () async {
      final int id = await Repo.goal.insert(
        const SavingGoal(name: '旅行', targetCents: 100000),
      );

      expect(await Repo.goal.addFunds(id, 30000), 30000);
      expect(await Repo.goal.addFunds(id, 10000), 40000);
      expect(await Repo.goal.addFunds(id, -50000), 0, reason: '不许出现负存款');

      final SavingGoal g = (await Repo.goal.all()).single;
      expect(g.savedCents, 0);
      expect(g.remainingCents, 100000);
      expect(g.isDone, isFalse);
    });

    test('进度不截断上界，超额算 1.5', () async {
      final int id = await Repo.goal.insert(
        const SavingGoal(name: '旅行', targetCents: 10000),
      );
      await Repo.goal.addFunds(id, 15000);
      final SavingGoal g = (await Repo.goal.all()).single;
      expect(g.progress, 1.5);
      expect(g.isDone, isTrue);
    });

    test('更新与删除', () async {
      final int id = await Repo.goal.insert(const SavingGoal(name: '旧'));
      await Repo.goal.update(
        (await Repo.goal.all()).single.copyWith(name: '新', targetCents: 5000),
      );
      final SavingGoal g = (await Repo.goal.all()).single;
      expect(g.name, '新');
      expect(g.targetCents, 5000);

      await Repo.goal.delete(id);
      expect(await Repo.goal.all(), isEmpty);
    });
  });
}
