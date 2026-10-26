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

    test('GBK 被准确识别成 encodingGbk，而不是笼统的 encoding', () {
      // 「交易时间」的 GBK 字节，不是合法 UTF-8
      final gbk = <int>[0xBD, 0xBB, 0xD2, 0xD7, 0xCA, 0xB1, 0xBC, 0xE4];
      expect(
        () => BillCsv.parse(gbk),
        throwsA(
          isA<BillParseException>().having(
            (e) => e.error,
            'error',
            BillParseError.encodingGbk,
          ),
        ),
      );
    });

    test('GBK 的错误文案同时给出「有电脑」和「只有手机」两条路径', () {
      final gbk = <int>[0xBD, 0xBB, 0xD2, 0xD7, 0xCA, 0xB1, 0xBC, 0xE4];
      try {
        BillCsv.parse(gbk);
        fail('应该抛异常');
      } on BillParseException catch (e) {
        // 手机上无法转码是真实的能力边界，必须明说而不是含糊带过
        expect(e.message, contains('有电脑'));
        expect(e.message, contains('只有手机'));
        expect(e.message, contains('不会影响你已经导入的记录'));
      }
    });

    test('成功解码时带上识别出的编码', () {
      expect(
        BillCsv.parse(utf8.encode(_alipay)).encoding,
        BillEncoding.utf8,
      );
      expect(
        BillCsv.parse(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(_alipay)]).encoding,
        BillEncoding.utf8Bom,
      );
    });

    test('UTF-16LE + BOM 报 utf16Le', () {
      final bytes = <int>[0xFF, 0xFE];
      for (final u in _wechat.codeUnits) {
        bytes.add(u & 0xFF);
        bytes.add((u >> 8) & 0xFF);
      }
      expect(BillCsv.parse(bytes).encoding, BillEncoding.utf16Le);
    });
  });

  group('编码诊断（嗅探）', () {
    /// 解析失败时返回错误类型；没抛异常则判失败。
    BillParseError errorOf(List<int> bytes) {
      try {
        BillCsv.parse(bytes);
      } on BillParseException catch (e) {
        return e.error;
      }
      fail('应该抛 BillParseException，但解析成功了 —— 说明硬解出了乱码');
    }

    test('xlsx（zip 包装）报 notCsv，并指出去另存为 CSV', () {
      final xlsx = <int>[0x50, 0x4B, 0x03, 0x04, ...List.filled(100, 0x41)];
      expect(errorOf(xlsx), BillParseError.notCsv);

      try {
        BillCsv.parse(xlsx);
      } on BillParseException catch (e) {
        expect(e.message, contains('Excel'));
        expect(e.message, contains('另存为'));
      }
    });

    test('PDF 报 notCsv', () {
      final pdf = <int>[0x25, 0x50, 0x44, 0x46, ...List.filled(100, 0x41)];
      expect(errorOf(pdf), BillParseError.notCsv);
    });

    test('无 BOM 的 UTF-16 报 encodingUtf16（零字节挤在单侧）', () {
      // 整份账单转 UTF-16BE 且去掉 BOM：数字/逗号/引号这些 ASCII 的
      // 高字节恒为 0，全挤在偶数位 —— 这就是判据，不是「零字节多不多」
      final bytes = <int>[];
      for (final u in _alipay.codeUnits) {
        bytes.add((u >> 8) & 0xFF);
        bytes.add(u & 0xFF);
      }
      expect(errorOf(bytes), BillParseError.encodingUtf16);
    });

    test('二进制（零字节分布不规律）报 notCsv', () {
      // 0 均匀落在奇偶位，不像 UTF-16，也不像文本
      final bin = <int>[
        for (var i = 0; i < 400; i++) i % 4 == 1 || i % 4 == 2 ? 0x00 : 0xFF,
      ];
      expect(errorOf(bin), BillParseError.notCsv);
    });

    test('认不出具体编码时回落到 encoding，不误判成 GBK', () {
      // 0x80 后接 0x20（< 0x40）不构成 GBK 双字节对
      final odd = <int>[for (var i = 0; i < 200; i++) i.isEven ? 0x80 : 0x20];
      expect(errorOf(odd), BillParseError.encoding);
    });

    test('合法 UTF-8 永远不走嗅探，不会被误判', () {
      // 这条是安全阀：嗅探只在 utf8.decode 失败后触发
      expect(BillCsv.parse(utf8.encode(_alipay)).encoding, BillEncoding.utf8);
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

  // ------------------------------------------------------------------
  // CSV 结构：这两条以前会**静默丢账**（不是算错，是整行消失）
  // ------------------------------------------------------------------
  group('CSV 结构', () {
    const header = '交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态';

    test('引号内的换行属于字段，不会把一条记录劈成两条', () {
      // 商品说明里带换行（多行备注）是真实账单里出现过的形态。
      // 旧实现按 \n 切行 → 两条残行都解析失败 → 静默少一笔。
      final csv = '\n$header\n'
          '2026-09-10 08:00:00,餐饮,某某,"第一行\n第二行",支出,20.00,余额,交易成功\n'
          '2026-09-11 09:00:00,餐饮,隔壁,豆浆,支出,5.00,余额,交易成功\n';
      final r = BillCsv.parse(utf8.encode(csv));
      expect(r.importable.length, 2, reason: '跨行字段不能被当成两行');
      expect(r.importable.first.note, '第一行\n第二行');
      expect(r.importable.first.amountCents, 2000);
      // 行号仍是**原文行号**：跨行记录之后的行不能因为"记录数"而错位
      expect(r.importable.first.lineNo, 3);
      expect(r.importable.last.lineNo, 5);
    });

    test('商品说明里没加引号的逗号不会让整行被丢掉', () {
      // 支付宝/微信不保证给字段加引号：多切出一列后，
      // 金额列会读到「支出」，整行被当成说明行丢掉。
      final csv = '$header\n'
          '2026-09-13 12:00:00,餐饮,某某,套餐,加饮料,支出,25.00,余额,交易成功\n';
      final r = BillCsv.parse(utf8.encode(csv));
      expect(r.importable.length, 1, reason: '多切一列不能导致整行消失');
      expect(r.importable.first.amountCents, 2500);
      expect(r.importable.first.note, '套餐,加饮料', reason: '多出的列并回商品说明');
      expect(r.importable.first.payMethod, '余额', reason: '后面的列不能跟着错位');
    });

    test('行尾少列时补空串，不崩也不错位', () {
      final csv = '$header\n'
          '2026-09-12 10:00:00,餐饮,便利店,矿泉水,支出,3.00\n';
      final r = BillCsv.parse(utf8.encode(csv));
      expect(r.importable.length, 1);
      expect(r.importable.first.amountCents, 300);
      expect(r.importable.first.payMethod, '');
    });

    test('引号包裹 + 双引号转义仍然正确', () {
      final csv = '$header\n'
          '2026-09-14 10:00:00,餐饮,某某,"他说""好""的",支出,9.00,余额,交易成功\n';
      final r = BillCsv.parse(utf8.encode(csv));
      expect(r.importable.single.note, '他说"好"的');
    });
  });

  // ------------------------------------------------------------------
  // 指纹幂等：挡"同一份账单导两次"，但不误杀同额同日的第二笔真账
  // ------------------------------------------------------------------
  group('指纹幂等', () {
    Txn txn({
      required int cents,
      required String date,
      String note = '',
      TxnType type = TxnType.expense,
    }) => Txn(
      id: 1,
      ledgerId: 1,
      type: type,
      amountCents: cents,
      date: date,
      note: note,
    );

    BillRow row({
      required int cents,
      required String date,
      required String party,
      String note = '',
    }) => BillRow(
      lineNo: 2,
      date: date,
      time: '12:00',
      amountCents: cents,
      type: TxnType.expense,
      counterparty: party,
      note: note,
      payMethod: '',
      rawAmount: '${cents / 100}',
    );

    test('同一份账单导第二次：全部判为已存在，默认不勾', () {
      final rows = [
        row(cents: 3200, date: '2026-09-03', party: '星巴克', note: '拿铁'),
        row(cents: 1850, date: '2026-09-05', party: '滴滴出行'),
      ];
      // 库里的 note 就是导入时写的 `对方 · 商品说明`
      final existing = [
        txn(cents: 3200, date: '2026-09-03', note: '星巴克 · 拿铁'),
        txn(cents: 1850, date: '2026-09-05', note: '滴滴出行'),
      ];
      BillCsv.markDuplicates(rows, existing);
      for (final r in rows) {
        expect(r.certainDuplicate, isTrue);
        expect(r.suspectedDuplicate, isTrue);
        expect(r.duplicateScore, 80);
        expect(r.include, isFalse, reason: '确定性重复默认不导，但用户可勾回');
      }
    });

    test('库里 1 笔、文件 2 笔：只认领 1 笔，第 2 笔保持可导入', () {
      // 真实场景：上午下午各喝一杯，库里只存了上午那杯。
      // 用布尔集合会让两行都被排除 → 丢一笔真账。
      final rows = [
        row(cents: 3200, date: '2026-09-03', party: '星巴克'),
        row(cents: 3200, date: '2026-09-03', party: '星巴克'),
      ];
      BillCsv.markDuplicates(rows, [
        txn(cents: 3200, date: '2026-09-03', note: '星巴克'),
      ]);
      expect(rows.where((r) => r.certainDuplicate).length, 1);
      expect(rows.where((r) => r.include).length, 1, reason: '第 2 笔必须仍可导入');
    });

    test('对方为空时不做指纹判定（只留模糊打分）', () {
      final rows = [row(cents: 3200, date: '2026-09-03', party: '')];
      BillCsv.markDuplicates(rows, [
        txn(cents: 3200, date: '2026-09-03', note: ''),
      ]);
      expect(rows.single.certainDuplicate, isFalse);
      expect(rows.single.suspectedDuplicate, isTrue, reason: '同额同日仍要提示');
      expect(rows.single.include, isTrue, reason: '模糊档不动默认勾选');
    });

    test('金额不同、仅对方相同 → 不是确定性重复', () {
      final rows = [row(cents: 3300, date: '2026-09-03', party: '星巴克')];
      BillCsv.markDuplicates(rows, [
        txn(cents: 3200, date: '2026-09-03', note: '星巴克'),
      ]);
      expect(rows.single.certainDuplicate, isFalse);
    });
  });
}
