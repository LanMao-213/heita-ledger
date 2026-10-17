// 记账模板的数据层自检。
//
// 模板这块最容易错的地方不是界面，而是：排序值、使用次数、老库升级。
// 这三样出问题都不会立刻报错，只会在用户手机上悄悄错乱，所以单独测。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_template.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 和各测试文件各用各的库，避免并行时抢同一个文件
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() async {
    await Db.close();
    // 必须删库：升级测试会造一个「只有 txn_template」的假库，
    // 留着会污染同目录下其它测试（sqlite 会认为 v2 已就位而跳过建表）。
    final file = File(await _dbPath());
    if (file.existsSync()) file.deleteSync();
  });

  /// 建一条模板的便捷方法
  Future<int> add(
    int ledgerId,
    String name,
    int cents, {
    String icon = 'tpl',
    int? categoryId,
    int? accountId,
  }) =>
      Repo.insertTemplate(TxnTemplate(
        id: 0,
        ledgerId: ledgerId,
        name: name,
        icon: icon,
        type: TxnType.expense,
        amountCents: cents,
        categoryId: categoryId,
        accountId: accountId,
      ));

  test('模板增删改：排序值自动递增，编辑不影响排序', () async {
    await Db.open();
    final ledgerId = await Repo.currentLedgerId();
    final cat =
        (await Repo.listCategories(ledgerId, type: TxnType.expense)).first;
    final acc = (await Repo.listAccounts()).first;

    final id1 = await add(ledgerId, '早餐', 1200,
        icon: 'food', categoryId: cat.id, accountId: acc.id);
    final id2 = await add(ledgerId, '房租', 300000, icon: 'home');

    var list = await Repo.listTemplates(ledgerId);
    expect(list.map((e) => e.name).toList(), ['早餐', '房租']);
    expect(list.map((e) => e.sortOrder).toList(), [0, 1]);

    await Repo.updateTemplate(
      list.first.copyWith(name: '早饭', amountCents: 1500),
    );
    list = await Repo.listTemplates(ledgerId);
    expect(list.first.name, '早饭');
    expect(list.first.amountCents, 1500);
    expect(list.first.sortOrder, 0, reason: '编辑不该改变排序值');

    await Repo.deleteTemplate(id2);
    list = await Repo.listTemplates(ledgerId);
    expect(list.length, 1);
    expect(list.single.id, id1);
  });

  test('金额留空的模板 hasAmount 为 false', () async {
    await Db.open();
    final ledgerId = await Repo.currentLedgerId();
    await add(ledgerId, '随便花', 0);
    final t = (await Repo.listTemplates(ledgerId)).single;
    expect(t.hasAmount, isFalse);
  });

  test('最近使用：先按次数，再按最后一次使用时间', () async {
    await Db.open();
    final ledgerId = await Repo.currentLedgerId();
    await add(ledgerId, 'A', 100);
    final b = await add(ledgerId, 'B', 100);
    final c = await add(ledgerId, 'C', 100);
    final d = await add(ledgerId, 'D', 100);

    // B 用过两次、C 用过一次、D 用过一次
    await Repo.touchTemplate(b);
    await Repo.touchTemplate(b);
    await Repo.touchTemplate(c);
    await Repo.touchTemplate(d);

    final top3 = await Repo.recentTemplates(ledgerId);
    expect(top3.length, 3);
    expect(top3.first.name, 'B');
    // C 和 D 次数相同，D 后 touch，所以排在 C 前面
    expect(top3.map((e) => e.name).toList(), ['B', 'D', 'C']);
    expect(top3.first.useCount, 2);

    // A 一次没用过 → 排在最后，进不了前三
    final all = await Repo.recentTemplates(ledgerId, limit: 10);
    expect(all.last.name, 'A');
  });

  test('拖动排序：按传入顺序写回 sort_order', () async {
    await Db.open();
    final ledgerId = await Repo.currentLedgerId();
    final a = await add(ledgerId, 'A', 100);
    final b = await add(ledgerId, 'B', 100);
    final c = await add(ledgerId, 'C', 100);

    await Repo.reorderTemplates([c, a, b]);
    final list = await Repo.listTemplates(ledgerId);
    expect(list.map((e) => e.name).toList(), ['C', 'A', 'B']);
    expect(list.map((e) => e.sortOrder).toList(), [0, 1, 2]);
  });

  test('用模板记一笔：template_id 落到账目上，使用次数 +1', () async {
    await Db.open();
    final ledgerId = await Repo.currentLedgerId();
    final cat =
        (await Repo.listCategories(ledgerId, type: TxnType.expense)).first;
    final acc = (await Repo.listAccounts()).first;
    final tplId = await add(ledgerId, '早餐', 1200,
        categoryId: cat.id, accountId: acc.id);

    await Repo.insertTxn(Txn(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.expense,
      amountCents: 1200,
      date: Fmt.today(),
      categoryId: cat.id,
      accountId: acc.id,
      templateId: tplId,
    ));
    await Repo.touchTemplate(tplId);

    final db = await Db.open();
    final txnRow = (await db.query('txn')).single;
    expect(txnRow['template_id'], tplId);

    final tpl = (await Repo.listTemplates(ledgerId)).single;
    expect(tpl.useCount, 1);
    expect(tpl.lastUsedAt, isNotNull);
  });

  test('v1 老库升级：补上 use_count / last_used_at，旧数据不丢', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, _dbName);

    // 手工造一个只带 txn_template 的 v1 库（升级逻辑只碰这张表）
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE txn_template (
              id           INTEGER PRIMARY KEY AUTOINCREMENT,
              ledger_id    INTEGER NOT NULL,
              name         TEXT    NOT NULL,
              icon         TEXT    NOT NULL DEFAULT 'tpl',
              type         TEXT    NOT NULL,
              amount_cents INTEGER NOT NULL DEFAULT 0,
              category_id  INTEGER,
              account_id   INTEGER,
              note         TEXT    NOT NULL DEFAULT '',
              sort_order   INTEGER NOT NULL DEFAULT 0
            )''');
        },
      ),
    );
    await old.insert('txn_template', {
      'ledger_id': 1,
      'name': '旧模板',
      'type': 'expense',
      'amount_cents': 500,
    });
    await old.close();

    final db = await Db.open();
    final cols = await db.rawQuery('PRAGMA table_info(txn_template)');
    expect(
      cols.map((c) => c['name']).toList(),
      containsAll(['use_count', 'last_used_at']),
    );

    final row = (await db.query('txn_template')).single;
    expect(row['name'], '旧模板');
    expect(row['use_count'], 0);
    expect(row['last_used_at'], isNull);
  });
}
