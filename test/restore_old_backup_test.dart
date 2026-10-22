// 从旧版本（v5）备份恢复的自检。
//
// 恢复和「手机上的老库被新应用打开」走的是两条完全不同的路径：
// onUpgrade 只在打开老库时触发，而恢复是直接往新库表里灌行，不会经过它。
// 少了「灌完之后再升一次级」这一步，从旧备份恢复出来的账本会是：
// 9 个一级分类、0 个子分类，历史记录全挂在「交通」「通讯」这种已经不用的名字上，
// 而且再也不会被自动修正 —— 用户看到的是「恢复之后分类全乱了」。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/backup_service.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_restore_old.db';

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

  /// 造一份「v5 时代」的备份：分类是扁平的一级，交易直接挂在上面
  Future<Map<String, Object?>> oldBackup() async {
    final now = await BackupService.dump();
    final s = Store.i;
    final ledgerId = s.ledgerId;
    final acc = s.accounts.first.id;

    // v5 的分类行：没有子分类，parent_id 永远是 null
    Map<String, Object?> cat(int id, String name, String icon) => {
      'id': id,
      'ledger_id': ledgerId,
      'type': 'expense',
      'name': name,
      'icon': icon,
      'parent_id': null,
      'sort_order': id,
      'archived': 0,
    };

    Map<String, Object?> txn(int id, int catId, int cents, String note) => {
      'id': id,
      'ledger_id': ledgerId,
      'type': 'expense',
      'amount_cents': cents,
      'date': Fmt.today(),
      'category_id': catId,
      'account_id': acc,
      'to_account_id': null,
      'note': note,
      'template_id': null,
      'recurring_id': null,
      'created_at': DateTime.now().toIso8601String(),
      'period_start': null,
    };

    final tables = Map<String, Object?>.from(now['tables']! as Map);
    tables['category'] = [
      cat(1, '餐饮', 'food'),
      cat(2, '交通', 'transport'), // → 应改名成「出行」
      cat(3, '通讯', 'comm'), // → 应降级成「居家 / 话费网费」
      cat(4, '医疗', 'medical'), // → 应改名成「健康」
    ];
    tables['txn'] = [
      txn(1, 2, 600, '地铁'),
      txn(2, 3, 9900, '话费'),
      txn(3, 4, 3000, '挂号'),
    ];

    return {
      ...now,
      'schemaVersion': 5, // 关键：告诉恢复流程「这份数据比库老」
      'tables': tables,
    };
  }

  test('旧备份恢复后，扁平分类被升成两级，历史记录原地落位', () async {
    final payload = await oldBackup();
    await BackupService.restore(payload);
    await Store.i.reloadAfterRestore();

    final s = Store.i;
    final tops = s.expenseCats.map((c) => c.name).toList();

    // 1. 改名：交通 → 出行、医疗 → 健康（历史交易不用改 category_id）
    expect(tops, contains('出行'));
    expect(tops, contains('健康'));
    expect(tops, isNot(contains('交通')), reason: '老名字应该已经原地改成出行');
    expect(tops, isNot(contains('医疗')));

    // 2. 降级：通讯 变成了「居家」的子分类「话费网费」
    expect(tops, isNot(contains('通讯')), reason: '通讯应该被降级成子分类');
    final home = s.expenseCats.firstWhere((c) => c.name == '居家');
    final homeSubs = s.childrenOf(home.id).map((c) => c.name).toList();
    expect(homeSubs, contains('话费网费'));

    // 3. 子分类补齐：改名后的「出行」下面有种子里的子分类
    final trip = s.expenseCats.firstWhere((c) => c.name == '出行');
    expect(
      s.childrenOf(trip.id).map((c) => c.name),
      contains('公共交通'),
      reason: '顶级分类要补齐种子里的子分类',
    );

    // 4. 最关键的一条：那 3 笔历史记录还在，而且落到了正确的分类上
    final rows = await Repo.listTxns(
      ledgerId: s.ledgerId,
      month: Fmt.month(DateTime.now()),
    );
    expect(rows.length, 3);

    final byNote = {for (final t in rows) t.note: t};
    expect(byNote['地铁']!.categoryId, trip.id, reason: '原「交通」的交易要跟着改名后的分类走');
    final comm = s.allExpenseCats.firstWhere((c) => c.name == '话费网费');
    expect(byNote['话费']!.categoryId, comm.id);
    expect(comm.parentId, home.id);
  });

  test('恢复之后分类数比备份里多（补出来的子分类）', () async {
    final payload = await oldBackup();
    final oldCount = (payload['tables']! as Map)['category']! as List;
    await BackupService.restore(payload);

    final now = await Repo.listCategories(Store.i.ledgerId);
    expect(now.length, greaterThan(oldCount.length), reason: '两级化之后应当多出一批子分类');
  });
}
