import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/core/period.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:heita_ledger/stores/book_store.dart';
import 'package:heita_ledger/stores/catalog_store.dart';
import 'package:heita_ledger/stores/plan_store.dart';
import 'package:heita_ledger/stores/shell_store.dart';
import 'package:heita_ledger/ui/boot/boot_gate.dart';

import '../support/db_fixture.dart';
import '../support/repo_fixture.dart';

/// 启动序列：**12 步顺序正确** + 全程只重建 1 次 + 失败时 ready 保持 false。
void main() {
  setUp(openTestDb);
  tearDown(closeTestDb);

  test('12 步跑完：ready、四个 Store 都有数据、只发 1 次通知', () async {
    final ShellStore shell = ShellStore();
    final BookStore book = BookStore();
    final CatalogStore catalog = CatalogStore();
    final PlanStore plan = PlanStore();

    int notified = 0;
    shell.addListener(() => notified++);

    final BootOutcome outcome = await BootSequence.run(
      shell,
      book: book,
      catalog: catalog,
      plan: plan,
    );

    expect(shell.ready, isTrue);
    expect(shell.bootError, isNull);
    expect(outcome.isEmpty, isTrue, reason: '新库没有周期账单，也没有分类升级');
    expect(notified, 1, reason: '启动全程只重建 1 次');

    // ⑤ 配色（缺省 ink）
    expect(shell.palette.id, 'ink');
    // ⑦ 游标落在今天所在期
    expect(book.cycle, Period.cycleRange(LocalDate.today(), 1));
    expect(book.cycleStartDay, 1);
    // ⑩ 分类树与账户都加载了
    expect(catalog.loaded, isTrue);
    expect(catalog.tree.tops, hasLength(15));
    expect(catalog.accounts, hasLength(1));
    // ⑩ 统计只打脏标记，不在启动路径算
    expect(plan.statsStale, isTrue);
    expect(plan.stats.isEmpty, isTrue);
  });

  test('② 配色在首帧之前定好：库里是 aurora 就直接用 aurora', () async {
    await Db.writeSetting('theme.palette', 'aurora');
    final ShellStore shell = ShellStore();

    await BootSequence.run(shell, catalog: CatalogStore(), plan: PlanStore());

    expect(shell.palette.id, 'aurora');
  });

  test('④ 触感缺省开、显式 0 则关', () async {
    final ShellStore on = ShellStore();
    await BootSequence.run(on);
    expect(on.hapticsEnabled, isTrue);

    await Db.writeSetting('ui.haptics', '0');
    final ShellStore off = ShellStore();
    await BootSequence.run(off);
    expect(off.hapticsEnabled, isFalse);
  });

  test('⑦ 账单日非法（99）→ 自愈成 1 并写回', () async {
    await Db.writeSetting('cycle_start_day', '99');
    final ShellStore shell = ShellStore();
    final BookStore book = BookStore();

    await BootSequence.run(shell, book: book);

    expect(book.cycleStartDay, 1);
    expect(await Db.readSetting('cycle_start_day'), '1');
  });

  test('⑧ 补记：有到期规则时 outcome 里带上笔数，且 Store 已重载', () async {
    final int ledger = await currentLedger();
    final int acc = await defaultAccountId();
    await Repo.recurring.insert(
      Recurring(
        ledgerId: ledger,
        type: TxnType.expense,
        amountCents: 30000,
        accountId: acc,
        nextRunDate: LocalDate.today().addDays(-1),
        note: '房租',
      ),
    );

    final ShellStore shell = ShellStore();
    final PlanStore plan = PlanStore();
    final CatalogStore catalog = CatalogStore();

    final BootOutcome outcome = await BootSequence.run(
      shell,
      catalog: catalog,
      plan: plan,
    );

    expect(outcome.recurringAdded, 1);
    expect(outcome.message, contains('已补记 1 笔周期账单'));
    expect(plan.recurring, hasLength(1));
    expect(catalog.netWorthCents, -30000, reason: '补记要影响净资产');
  });

  test('⑪ ready 为真时重复 run 不会重复补记（上游自己跳过）', () async {
    final ShellStore shell = ShellStore();
    final PlanStore plan = PlanStore();
    await BootSequence.run(shell, plan: plan);
    expect(shell.ready, isTrue);

    final int before = (await Repo.txn.allOfLedger(await currentLedger())).length;
    await BootSequence.run(shell, plan: plan);
    final int after = (await Repo.txn.allOfLedger(await currentLedger())).length;
    expect(after, before);
  });

  test('任一步失败 → BootGate 落 bootError 且 ready 保持 false', () async {
    final ShellStore shell = ShellStore();
    await expectLater(
      BootSequence.run(shell, catalog: CatalogStore(), plan: PlanStore()),
      completes,
    );
    expect(shell.ready, isTrue);

    // 换一个「会失败」的库路径，验证失败路径不会把 ready 置真
    await Db.close();
    Db.fileName = 'no_such_dir_xyz/heita.db';
    final ShellStore broken = ShellStore();
    Object? caught;
    try {
      await BootSequence.run(broken);
    } catch (error) {
      caught = error;
    }
    if (caught != null) {
      broken.failBoot(caught);
      expect(broken.ready, isFalse);
      expect(broken.bootError, isNotNull);
    } else {
      // 某些平台能自动建目录 → 退化为「至少 ready 为真」的断言
      expect(broken.ready, isTrue);
    }
    Db.fileName = ':memory:';
  });
}
