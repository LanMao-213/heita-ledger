// 分类的停用与排序。
//
// 为什么单独测这一条：`archived` 列和 `sort_order` 列在 schema v6 就有了，
// 但一直只有数据层在用（查询过滤、排序），没有任何界面能写。一旦接上界面，
// 最容易出的两个事故是：
//   1. 停用之后历史流水渲染成「已删除分类」—— 因为按 id 反查分类时漏了停用那份；
//   2. 拖完顺序存进去了，但列表用的还是按旧顺序排的那份缓存。
// 这两个都不会崩、不会报错，只能靠断言盯住。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/pages/cats_page.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/wait_write.dart';

const _dbName = 'test_category_archive.db';

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

  test('停用后从选择器消失，但管理页与反查仍然认得它', () async {
    await Store.i.boot();
    final s = Store.i;
    final target = s.expenseCats.first;
    final before = s.expenseCats.length;

    // 先在这个分类下记一笔，模拟「停用之前已经花掉的钱」
    await Repo.insertTxn(
      Txn(
        id: 0,
        ledgerId: s.ledgerId,
        type: TxnType.expense,
        amountCents: 1234,
        date: s.cycleFrom,
        categoryId: target.id,
        accountId: s.accounts.first.id,
      ),
    );
    await s.afterTxnChange();

    await Repo.setCategoryArchived(target.id, archived: true);
    await s.afterCategoryChange();

    expect(s.expenseCats.length, before - 1, reason: '停用的不该再出现在选择器里');
    expect(
      s.expenseCats.any((c) => c.id == target.id),
      isFalse,
      reason: '选择器 / 预算 / 统计用的都是 expenseCats，它必须干净',
    );
    expect(
      s.archivedTopCats(TxnType.expense).map((c) => c.id),
      contains(target.id),
      reason: '管理页的「已停用」段要能列出它，否则没法恢复',
    );

    // 按 id 反查必须还能拿到：明细、模板、周期账单都靠 categoryOf 显示分类名
    expect(
      s.categoryOf(target.id)?.name,
      target.name,
      reason: '停用不等于删除，历史流水不能显示成「已删除分类」',
    );

    // 统计照旧包含它 —— 停用只管「以后不再选到」，已经花掉的钱不能凭空消失，
    // 否则各分类加总会和总额对不上
    final stats = await Repo.rangeCategoryStats(
      ledgerId: s.ledgerId,
      from: s.cycleFrom,
      to: s.cycleTo,
      type: TxnType.expense,
    );
    expect(
      stats.any((e) => e.categoryId == target.id),
      isTrue,
      reason: '本期已有的这笔支出挂在停用分类上，统计里必须还在',
    );
  });

  test('恢复后重新回到选择器', () async {
    await Store.i.boot();
    final s = Store.i;
    final target = s.expenseCats.first;

    await Repo.setCategoryArchived(target.id, archived: true);
    await s.afterCategoryChange();
    expect(s.expenseCats.any((c) => c.id == target.id), isFalse);

    await Repo.setCategoryArchived(target.id, archived: false);
    await s.afterCategoryChange();

    expect(
      s.expenseCats.any((c) => c.id == target.id),
      isTrue,
      reason: '恢复后要能重新被选到',
    );
    expect(s.archivedTopCats(TxnType.expense), isEmpty);
  });

  test('子分类停用只影响它自己，父级列表不动', () async {
    await Store.i.boot();
    final s = Store.i;
    final parent = s.expenseCats.firstWhere(
      (c) => s.childrenOf(c.id).isNotEmpty,
    );
    final subsBefore = s.childrenOf(parent.id).length;
    final sub = s.childrenOf(parent.id).first;

    await Repo.setCategoryArchived(sub.id, archived: true);
    await s.afterCategoryChange();

    expect(s.childrenOf(parent.id).length, subsBefore - 1);
    expect(
      s.archivedChildrenOf(parent.id).map((c) => c.id),
      contains(sub.id),
    );
    expect(
      s.expenseCats.any((c) => c.id == parent.id),
      isTrue,
      reason: '停用子分类不该把父级也带走',
    );
  });

  test('拖拽排序写回 sort_order 后，列表顺序按新顺序', () async {
    await Store.i.boot();
    final s = Store.i;
    final original = s.expenseCats.map((c) => c.id).toList();
    final reversed = original.reversed.toList();

    await Repo.reorderCategories(reversed);
    await s.afterCategoryChange();

    expect(
      s.expenseCats.map((c) => c.id).toList(),
      reversed,
      reason: 'reorderCategories 写完必须重载缓存，否则界面还是旧顺序',
    );

    // 落库再查一次，确认不是只改了内存。
    // 注意 `listCategories` 返回的是「该类型下的全部节点」——一级和子级混在一起，
    // 而 `sort_order` 是**按同级分组**的（每组的子分类都从 0 开始），
    // 所以这里必须先按 parentId 把一级挑出来再比。
    final fromDb = await Repo.listCategories(s.ledgerId, type: TxnType.expense);
    final topFromDb = [
      for (final c in fromDb)
        if (c.parentId == null) c.id,
    ];
    expect(topFromDb, reversed);
  });

  testWidgets('停用的分类在管理页落到「已停用」段，点恢复能回来', (tester) async {
    // 默认 800×600 的测试窗口装不下 9 个一级分类 + 末尾的「已停用」段，
    // 而 ListView 不会构建屏幕外的项 —— 所以先把视口撑高，再断言
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => Store.i.boot());
    final s = Store.i;
    final target = s.expenseCats.first;

    await tester.pumpWidget(const MaterialApp(home: CatsPage()));
    await tester.pump();

    await tester.runAsync(
      () => Repo.setCategoryArchived(target.id, archived: true),
    );
    await tester.runAsync(() => s.afterCategoryChange());
    await tester.pump();

    expect(
      find.textContaining('已停用 1 个'),
      findsOneWidget,
      reason: '列表末尾要有「已停用」段，否则用户没地方找回停用的分类',
    );
    expect(find.text('恢复'), findsOneWidget);

    // 点「恢复」的回调里要 await 真实数据库，必须放进 runAsync ——
    // 假时钟里 await 真实 I/O 永远不会返回（交接说明第 2 节第 2 条）
    await tester.runAsync(() => tester.tap(find.text('恢复')));
    // 原来这里是 runAsync 里死等 200ms。两个问题：
    //   ① `tester.tap` 不等回调里的异步 —— `_setArchived` 要走完
    //      afterCategoryChange 的 _loadCategories → loadCycle → loadStats 三步
    //      真实数据库查询，测试体先结束就把后两步留在半路上；
    //   ② 于是测试结束后那条查询撞上已关闭的库，抛 `database_closed`，
    //      框架按失败计（表现为「偶发 flaky」，全量跑时约一半概率红）。
    // 改用仓库统一的 settleWrites：真实时间与 pump 交替，让整条链走完再断言。
    await settleWrites(tester);
    await tester.pump();
    // 把 toast 的时间走完，避免结束时留着未完成的定时器
    await tester.pump(const Duration(seconds: 3));

    expect(find.textContaining('已停用 1 个'), findsNothing);
    expect(
      s.expenseCats.any((c) => c.id == target.id),
      isTrue,
      reason: '点「恢复」要把 archived 改回 0',
    );
  });
}
