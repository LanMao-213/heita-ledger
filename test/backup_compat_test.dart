// 备份**字段级**兼容的自检（P2-2）。
//
// 要钉的四件事：
//   1. 旧备份**多**一列（列后来被弃用/换名）→ 丢那一列，**不能整次恢复失败**；
//   2. 旧备份**少**列 → 走列的默认值，不算错；
//   3. 必填列缺失 → 报一句人能看懂的话，且事务回滚、数据不动；
//   4. 兼容动作必须留痕（[ConformReport]），悄悄丢字段是最坏的失败模式。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/backup_compat.dart';
import 'package:ledger/data/backup_service.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_backup_compat.db';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

Map<String, BackupColumn> _cols(List<BackupColumn> list) => {
  for (final c in list) c.name: c,
};

BackupColumn _col(
  String name, {
  String type = 'TEXT',
  bool notNull = false,
  bool hasDefault = false,
  int pk = 0,
}) => BackupColumn(
  name: name,
  type: type,
  notNull: notNull,
  hasDefault: hasDefault,
  pk: pk,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  group('conformRow（纯函数）', () {
    test('未知列被丢弃，并记账', () {
      final report = ConformReport();
      final out = conformRow(
        table: 'txn',
        row: {'id': 1, 'date': '2026-10-01', 'legacy_tag': 'x'},
        columns: _cols([_col('id', type: 'INTEGER', pk: 1), _col('date')]),
        report: report,
      );
      expect(out.containsKey('legacy_tag'), isFalse);
      expect(out['date'], '2026-10-01');
      expect(report.dropped, ['txn.legacy_tag']);
      expect(report.summary, contains('忽略 1 个旧字段'));
    });

    test('budget.month 换成 period_start，并补 -01', () {
      final report = ConformReport();
      final out = conformRow(
        table: 'budget',
        row: {'ledger_id': 1, 'month': '2026-10', 'amount_cents': 500000},
        columns: _cols([
          _col('ledger_id', type: 'INTEGER'),
          _col('period_start'),
          _col('amount_cents', type: 'INTEGER'),
        ]),
        report: report,
      );
      expect(out['period_start'], '2026-10-01');
      expect(out.containsKey('month'), isFalse);
      expect(report.renamed, ['budget.month → period_start']);
    });

    test('同时有 month 和新列时，以新列为准', () {
      final report = ConformReport();
      final out = conformRow(
        table: 'budget',
        row: {
          'period_start': '2026-11-01',
          'month': '2026-10',
        },
        columns: _cols([_col('period_start')]),
        report: report,
      );
      expect(out['period_start'], '2026-11-01');
    });

    test('少列（有默认值 / 可空）不算错', () {
      final report = ConformReport();
      final out = conformRow(
        table: 'txn',
        row: {'date': '2026-10-01'},
        columns: _cols([
          _col('date', notNull: true),
          _col('note', notNull: true, hasDefault: true),
          _col('person'),
        ]),
        report: report,
      );
      expect(out, {'date': '2026-10-01'});
      expect(report.clean, isTrue);
    });

    test('必填且无默认值的列缺失 → 明确报错，指出表和列', () {
      expect(
        () => conformRow(
          table: 'txn',
          row: {'note': '午饭'},
          columns: _cols([_col('date', notNull: true), _col('note')]),
          report: ConformReport(),
        ),
        throwsA(
          isA<BackupFieldException>().having(
            (e) => e.message,
            'message',
            allOf(contains('txn'), contains('date')),
          ),
        ),
      );
    });

    test('JSON 里的 bool 落成 INTEGER 的 1/0', () {
      final report = ConformReport();
      final out = conformRow(
        table: 'account',
        row: {'include_in_total': true},
        columns: _cols([_col('include_in_total', type: 'INTEGER')]),
        report: report,
      );
      expect(out['include_in_total'], 1);
      expect(report.coerced, ['account.include_in_total: bool→int']);
    });
  });

  group('restore（走真库）', () {
    setUp(() async {
      await Db.close();
      final f = File(await _dbPath());
      if (f.existsSync()) f.deleteSync();
      await Store.i.boot();

      // 造点真数据：空库测不出「旧字段被丢掉之后还能不能读」
      final s = Store.i;
      await Repo.insertTxn(
        Txn(
          id: 0,
          ledgerId: s.ledgerId,
          type: TxnType.expense,
          amountCents: 12800,
          date: Fmt.today(),
          categoryId: s.expenseCats.first.id,
          accountId: s.accounts.first.id,
          note: '午饭',
        ),
      );
      await Repo.setBudget(
        ledgerId: s.ledgerId,
        periodStart: s.cycleFrom,
        categoryId: null,
        amountCents: 300000,
      );
    });

    tearDown(() async {
      await Db.close();
      final f = File(await _dbPath());
      if (f.existsSync()) f.deleteSync();
    });

    /// 把当前的备份改造成「旧版形状」：删掉新列、把 budget 还原成 month、塞一个废弃列。
    Future<Map<String, Object?>> oldShapedPayload() async {
      final payload = await BackupService.dump();
      final tables = Map<String, Object?>.from(payload['tables']! as Map);

      List<Map<String, Object?>> rowsOf(String t) => [
        for (final r in (tables[t] as List? ?? const []))
          Map<String, Object?>.from(r as Map),
      ];

      // txn：抹掉 v6 才有的详情列与 v7 的 debt_id
      tables['txn'] = [
        for (final r in rowsOf('txn'))
          {
            for (final e in r.entries)
              if (!const ['place_from', 'place_to', 'person', 'subject', 'debt_id']
                  .contains(e.key))
                e.key: e.value,
            'legacy_tag': '老版本留下的列',
          },
      ];
      // budget：period_start → month（v4 形状）
      tables['budget'] = [
        for (final r in rowsOf('budget'))
          {
            for (final e in r.entries)
              if (e.key != 'period_start') e.key: e.value,
            'month': (r['period_start'] as String?)?.substring(0, 7),
          },
      ];
      return {...payload, 'schemaVersion': 3, 'tables': tables};
    }

    test('旧形状备份能恢复，字段级差异被记录', () async {
      final report = ConformReport();
      final payload = await oldShapedPayload();
      final counts = await BackupService.restore(payload, report: report);

      expect(counts['txn'], greaterThan(0));
      expect(report.dropped.any((s) => s.contains('legacy_tag')), isTrue);
      expect(report.renamed.any((s) => s.contains('month')), isTrue);

      // 预算仍然落得回去，说明 month → period_start 真的生效了。
      // ⚠️ 精度事实：旧格式只到「月」，换算后落在该月 1 号；
      //   若账单日不是 1 号，随后的 `upgradeRestoredData` 会再把它挪到当期起始日。
      //   这是旧格式本身的信息缺失（当年只存到月），不是这次改动的副作用。
      final budgets = (await Repo.dumpTables())['budget']!;
      expect(budgets, isNotEmpty, reason: 'month → period_start 后预算行必须在');
      expect(budgets.first['period_start'], isNotNull);
      // 交易仍然读得出来（少的那几列是 NULL，不影响核心字段）。
      // 直接看表而不走 rangeListTxns：周期筛选依赖 period_start，
      // 而这一条考的是「字段兼容」，不该被周期口径干扰。
      final txns = (await Repo.dumpTables())['txn']!;
      expect(txns, isNotEmpty);
      expect(txns.first['date'], isNotNull);
      expect(txns.first.containsKey('legacy_tag'), isFalse,
          reason: '废弃列不能进库');
    });

    test('必填列被改坏 → 抛用户可读错误，且数据一行未动', () async {
      final payload = await BackupService.dump();
      final tables = Map<String, Object?>.from(payload['tables']! as Map);
      tables['txn'] = [
        for (final r in (tables['txn'] as List))
          (Map<String, Object?>.from(r as Map)..remove('date')),
      ];

      final before = await Repo.rangeListTxns(
        ledgerId: Store.i.ledgerId,
        from: Store.i.stats.month,
        to: Store.i.stats.month,
      );

      await expectLater(
        BackupService.restore({
          ...payload,
          'schemaVersion': 3,
          'tables': tables,
        }),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            allOf(contains('必填字段'), contains('date')),
          ),
        ),
      );

      final after = await Repo.rangeListTxns(
        ledgerId: Store.i.ledgerId,
        from: Store.i.stats.month,
        to: Store.i.stats.month,
      );
      expect(after.length, before.length, reason: '失败必须整体回滚');
    });
  });
}
