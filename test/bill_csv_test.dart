import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/bill_csv.dart';
import 'package:ledger/data/models.dart';

/// 支付宝账单的最小样例（表头 + 3 行，其中 1 行是不计收支）
const _alipay = '''
支付宝交易记录明细查询
账号:[test@example.com]
起始日期:[2026-09-01 00:00:00]    终止日期:[2026-09-30 23:59:59]
---------------------------------交易记录明细列表------------------------------------
交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态
2026-09-03 12:30:00,餐饮美食,星巴克,拿铁,支出,32.00,余额宝,交易成功
2026-09-05 09:10:00,交通出行,滴滴出行,"快车, 3公里",支出,¥18.50,招商银行储蓄卡(1234),交易成功
2026-09-06 20:00:00,转账,张三,转账,不计收支,200.00,余额,交易成功
''';

/// 微信账单的最小样例
const _wechat = '''
微信支付账单明细
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态
2026-09-07 18:22:00,商户消费,美团,外卖,支出,45.00,零钱,支付成功
2026-09-08 10:00:00,转账,李四,还钱,收入,100.00,零钱,已收钱
''';

void main() {
  group('编码', () {
    test('UTF-8 正常解码', () {
      final r = BillCsv.parse(utf8.encode(_alipay));
      expect(r.rows, isNotEmpty);
      expect(r.source, BillSource.alipay);
    });

    test('UTF-8 BOM 不会被当成表头内容', () {
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(_alipay)];
      final r = BillCsv.parse(bytes);
      expect(r.source, BillSource.alipay);
      expect(r.importable.length, 2);
    });

    test('UTF-16LE + BOM 能解', () {
      final units = _wechat.codeUnits;
      final bytes = <int>[0xFF, 0xFE];
      for (final u in units) {
        bytes.add(u & 0xFF);
        bytes.add((u >> 8) & 0xFF);
      }
      final r = BillCsv.parse(bytes);
      expect(r.source, BillSource.wechat);
      expect(r.importable.length, 2);
    });

    test('GBK 触发 encoding 错误，而不是解出乱码', () {
      // 「交易时间,金额」的 GBK 字节，不是合法 UTF-8
      final gbk = <int>[0xBD, 0xBB, 0xD2, 0xD7, 0xCA, 0xB1, 0xBC, 0xE4];
      expect(
        () => BillCsv.parse(gbk),
        throwsA(
          isA<BillParseException>().having(
            (e) => e.error,
            'error',
            BillParseError.encoding,
          ),
        ),
      );
    });
  });

  group('表头与来源', () {
    test('认不出表头时报 header', () {
      expect(
        () => BillCsv.parse(utf8.encode('a,b,c\n1,2,3\n')),
        throwsA(
          isA<BillParseException>().having(
            (e) => e.error,
            'error',
            BillParseError.header,
          ),
        ),
      );
    });

    test('表头行号正确（前面有说明行）', () {
      final r = BillCsv.parse(utf8.encode(_alipay));
      expect(r.headerLine, 5);
    });

    test('表头在文件中重复出现时被忽略，不会当成数据行', () {
      final doubled = '''
交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态
2026-09-03 12:30:00,餐饮,星巴克,拿铁,支出,32.00,余额宝,交易成功
交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态
2026-09-04 12:30:00,餐饮,瑞幸,美式,支出,15.00,余额宝,交易成功
''';
      final r = BillCsv.parse(utf8.encode(doubled));
      expect(r.importable.length, 2);
    });
  });

  group('金额解析', () {
    test('纯数字与两位小数', () {
      expect(BillCsv.parseAmount('32.00'), 3200);
      expect(BillCsv.parseAmount('32'), 3200);
      expect(BillCsv.parseAmount('0.05'), 5);
    });

    test('货币符号与千分位', () {
      expect(BillCsv.parseAmount('¥1,234.56'), 123456);
      expect(BillCsv.parseAmount('￥1,234'), 123400);
      expect(BillCsv.parseAmount('32.00元'), 3200);
    });

    test('负号', () {
      expect(BillCsv.parseAmount('-45.80'), -4580);
      expect(BillCsv.parseAmount('+12.00'), 1200);
    });

    test('认不出来的返回 null', () {
      expect(BillCsv.parseAmount(''), isNull);
      expect(BillCsv.parseAmount('--'), isNull);
      expect(BillCsv.parseAmount('abc'), isNull);
      expect(BillCsv.parseAmount('1.234'), isNull);
    });
  });

  group('日期解析', () {
    test('带时间', () {
      final d = BillCsv.parseDate('2026-09-03 12:30:00');
      expect(d?.$1, '2026-09-03');
      expect(d?.$2, '12:30');
    });

    test('斜杠与单位数月日补零', () {
      final d = BillCsv.parseDate('2026/9/3');
      expect(d?.$1, '2026-09-03');
      expect(d?.$2, '');
    });

    test('非法日期返回 null', () {
      expect(BillCsv.parseDate('2026年9月3日'), isNull);
    });
  });

  group('行过滤', () {
    test('不计收支被跳过并计入 skippedLines', () {
      final r = BillCsv.parse(utf8.encode(_alipay));
      expect(r.rows.length, 2);
      expect(r.skippedLines, 1);
    });

    test('交易关闭被跳过', () {
      final csv = '''
交易时间,交易对方,收/支,金额,交易状态
2026-09-03 12:30:00,淘宝,支出,99.00,交易关闭
2026-09-03 13:30:00,京东,支出,88.00,交易成功
''';
      final r = BillCsv.parse(utf8.encode(csv));
      expect(r.importable.length, 1);
      expect(r.importable.first.amountCents, 8800);
    });

    test('全是不计收支时抛 empty', () {
      final csv = '''
交易时间,交易对方,收/支,金额
2026-09-03 12:30:00,张三,不计收支,200.00
''';
      expect(
        () => BillCsv.parse(utf8.encode(csv)),
        throwsA(
          isA<BillParseException>().having(
            (e) => e.error,
            'error',
            BillParseError.empty,
          ),
        ),
      );
    });

    test('没有收/支列时按金额符号判方向', () {
      final csv = '''
交易时间,交易对方,金额
2026-09-03 12:30:00,星巴克,-32.00
2026-09-04 10:00:00,李四,50.00
''';
      final r = BillCsv.parse(utf8.encode(csv));
      expect(r.importable[0].type, TxnType.expense);
      expect(r.importable[1].type, TxnType.income);
      expect(r.importable[0].amountCents, 3200);
      expect(r.warnings, isNotEmpty);
    });
  });

  group('字段映射', () {
    test('对方 / 商品 / 方式都取到', () {
      final r = BillCsv.parse(utf8.encode(_alipay));
      final first = r.importable.first;
      expect(first.counterparty, '星巴克');
      expect(first.note, '拿铁');
      expect(first.payMethod, '余额宝');
      expect(first.date, '2026-09-03');
      expect(first.time, '12:30');
    });

    test('引号里的逗号不会被拆列', () {
      final r = BillCsv.parse(utf8.encode(_alipay));
      final second = r.importable[1];
      expect(second.note, '快车, 3公里');
      expect(second.amountCents, 1850);
    });

    test('summary 拼接对方与说明', () {
      final r = BillCsv.parse(utf8.encode(_alipay));
      expect(r.importable.first.summary, '星巴克 · 拿铁');
    });

    test('支出默认算入、收入默认不算入', () {
      final r = BillCsv.parse(utf8.encode(_wechat));
      final expense = r.importable.firstWhere((e) => e.type.isExpense);
      final income = r.importable.firstWhere((e) => e.type.isIncome);
      expect(expense.include, isTrue);
      expect(income.include, isFalse);
    });

    test('合计只统计可导入行', () {
      final r = BillCsv.parse(utf8.encode(_alipay));
      expect(r.expenseTotalCents, 3200 + 1850);
      expect(r.incomeTotalCents, 0);
    });
  });

  group('重复判定', () {
    Txn txn({
      required int cents,
      required String date,
      TxnType type = TxnType.expense,
      String note = '',
    }) => Txn(
      id: 1,
      ledgerId: 1,
      type: type,
      amountCents: cents,
      date: date,
      note: note,
    );

    test('金额相同 + 同日 → ≥80，标为疑似', () {
      final rows = [
        BillRow(
          lineNo: 2,
          date: '2026-09-03',
          time: '12:30',
          amountCents: 3200,
          type: TxnType.expense,
          counterparty: '星巴克',
          note: '拿铁',
          payMethod: '',
          rawAmount: '32.00',
        ),
      ];
      BillCsv.markDuplicates(rows, [txn(cents: 3200, date: '2026-09-03')]);
      expect(rows.first.duplicateScore, greaterThanOrEqualTo(80));
      expect(rows.first.suspectedDuplicate, isTrue);
    });

    test('日期差 1 天 → 落在疑似的中间档，仍然标出', () {
      final rows = [
        BillRow(
          lineNo: 2,
          date: '2026-09-04',
          time: '',
          amountCents: 3200,
          type: TxnType.expense,
          counterparty: '',
          note: '',
          payMethod: '',
          rawAmount: '32.00',
        ),
      ];
      BillCsv.markDuplicates(rows, [txn(cents: 3200, date: '2026-09-03')]);
      expect(rows.first.duplicateScore, 70);
      expect(rows.first.suspectedDuplicate, isTrue);
    });

    test('金额与日期都差很多 → 不打标', () {
      final rows = [
        BillRow(
          lineNo: 2,
          date: '2026-09-20',
          time: '',
          amountCents: 8800,
          type: TxnType.expense,
          counterparty: '',
          note: '',
          payMethod: '',
          rawAmount: '88.00',
        ),
      ];
      BillCsv.markDuplicates(rows, [txn(cents: 3200, date: '2026-09-03')]);
      expect(rows.first.suspectedDuplicate, isFalse);
    });

    test('方向不同时不打标（同额同日但一收一支）', () {
      final rows = [
        BillRow(
          lineNo: 2,
          date: '2026-09-03',
          time: '',
          amountCents: 3200,
          type: TxnType.income,
          counterparty: '',
          note: '',
          payMethod: '',
          rawAmount: '32.00',
        ),
      ];
      BillCsv.markDuplicates(
        rows,
        [txn(cents: 3200, date: '2026-09-03', type: TxnType.expense)],
      );
      expect(rows.first.duplicateScore, 70);
    });

    test('空库时什么都不标', () {
      final rows = [
        BillRow(
          lineNo: 2,
          date: '2026-09-03',
          time: '',
          amountCents: 3200,
          type: TxnType.expense,
          counterparty: '',
          note: '',
          payMethod: '',
          rawAmount: '32.00',
        ),
      ];
      BillCsv.markDuplicates(rows, const []);
      expect(rows.first.suspectedDuplicate, isFalse);
      expect(rows.first.duplicateScore, 0);
    });

    test('跳过行不参与打分', () {
      final rows = [
        BillRow(
          lineNo: 2,
          date: '2026-09-03',
          time: '',
          amountCents: 3200,
          type: TxnType.expense,
          counterparty: '',
          note: '',
          payMethod: '',
          rawAmount: '32.00',
          skipReason: '交易关闭',
        ),
      ];
      BillCsv.markDuplicates(rows, [txn(cents: 3200, date: '2026-09-03')]);
      expect(rows.first.duplicateScore, 0);
    });
  });
}
