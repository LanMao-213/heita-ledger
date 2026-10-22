// 搜索范围的回归（1.4.4）。
//
// 1.4.3 之前只搜 note / person / subject / place_*。也就是说：输「餐饮」0 条、
// 输「现金」0 条、输「38.5」0 条 —— 而这三样恰恰是人最常想搜的线索。
// 更糟的是 0 条看起来像「没记过」，用户会以为数据丢了。
//
// 这里钉三件事：分类名（含父分类）、账户名、金额；外加两条「不要过头」的边界
// （非数字关键词不参与金额匹配、一位数不算金额），以及列表与合计口径一致。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_search_scope.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

late Category _parent;
late Category _child;
late Account _alipay;

/// 记一笔，默认挂在「子分类」上、用第二个账户 ——
/// 正是真实数据的样子（记录几乎都挂在子分类上）
Future<int> _add({
  int cents = 3850,
  String note = '',
  int? categoryId,
  int? accountId,
}) => Repo.insertTxn(
  Txn(
    id: 0,
    ledgerId: Store.i.ledgerId,
    type: TxnType.expense,
    amountCents: cents,
    date: Fmt.today(),
    categoryId: categoryId ?? _child.id,
    accountId: accountId ?? _alipay.id,
    note: note,
  ),
);

Future<List<Txn>> _search(String keyword) async {
  final (hits, _) = await Repo.searchTxns(
    ledgerId: Store.i.ledgerId,
    keyword: keyword,
  );
  return hits;
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

    // 挑一个「有子分类」的一级分类，以及它的第一个子分类
    _parent = Store.i.expenseCats.firstWhere(
      (c) => Store.i.allExpenseCats.any((x) => x.parentId == c.id),
    );
    _child = Store.i.allExpenseCats.firstWhere((x) => x.parentId == _parent.id);
    _alipay = Store.i.accounts[1];
  });

  group('分类名', () {
    test('搜父分类名能找到挂在子分类下的记录', () async {
      await _add(note: '午饭');

      final hits = await _search(_parent.name);
      expect(
        hits,
        hasLength(1),
        reason:
            '记录挂在「${_child.name}」上，用户搜的是「${_parent.name}」—— '
            '不带父子关系的话这里会是 0 条',
      );
      expect(hits.first.note, '午饭');
    });

    test('搜子分类名同样能找到', () async {
      await _add(note: '晚饭');
      final hits = await _search(_child.name);
      expect(hits, hasLength(1));
    });

    test('分类名只部分匹配也能命中', () async {
      await _add(note: '打车');
      final partial = _parent.name.substring(1);
      final hits = await _search(partial);
      expect(hits, hasLength(1), reason: '「${_parent.name}」的后半截「$partial」也该命中');
    });
  });

  group('账户名', () {
    test('搜账户名能找到用这个账户记的账', () async {
      await _add(note: '咖啡', accountId: _alipay.id);
      final hits = await _search(_alipay.name);
      expect(hits, hasLength(1));
    });

    test('不相关的账户名搜不到', () async {
      await _add(note: '咖啡', accountId: _alipay.id);
      // 换一个名字不同的账户
      final other = Store.i.accounts.firstWhere((a) => a.name != _alipay.name);
      final hits = await _search(other.name);
      expect(hits, isEmpty, reason: '${other.name} 没被这条记录用到，不该命中');
    });
  });

  group('金额', () {
    test('搜「38.5」能命中 38.50', () async {
      await _add(cents: 3850, note: '午饭');
      final hits = await _search('38.5');
      expect(hits, hasLength(1));
      expect(hits.first.amountCents, 3850);
    });

    test('带两位小数也能搜', () async {
      await _add(cents: 3850);
      expect(await _search('38.50'), hasLength(1));
    });

    test('小数点在金额里不是必需的：搜 385 同样命中 38.50', () async {
      await _add(cents: 3850);
      expect(
        await _search('385'),
        hasLength(1),
        reason: '「38.5」和「385」在 amount_cents 里都是 385…，按包含关系匹配',
      );
    });

    test('一位数不当成金额：搜「5」不该命中 5 元', () async {
      await _add(cents: 500, note: '水');
      expect(
        await _search('5'),
        isEmpty,
        reason: '一位数几乎能匹配所有金额（含 3850、13850…），噪音会盖掉结果',
      );
    });

    test('非数字关键词不参与金额匹配', () async {
      await _add(cents: 3850, note: '午饭');
      await _add(cents: 1200, note: '地铁');

      expect(await _search('午饭'), hasLength(1), reason: '只该命中备注，不该因为都有数字而多出别的');
    });
  });

  group('列表与合计同一口径', () {
    test('同一个关键词，列表条数与合计笔数一致', () async {
      await _add(cents: 1000, note: '早饭');
      await _add(cents: 2000, note: '午饭');
      await _add(cents: 3000, note: '晚饭');

      for (final k in ['饭', '1000', _parent.name]) {
        final hits = await _search(k);
        final sum = await Repo.sumFiltered(
          ledgerId: Store.i.ledgerId,
          keyword: k,
        );
        expect(
          hits.length,
          sum.$3,
          reason:
              '关键词「$k」：列表 ${hits.length} 条、合计 ${sum.$3} 笔，'
              '两处必须共用同一份 WHERE（searchTxns 与 sumFiltered 都走 _txnWhere）',
        );
      }
    });
  });
}
