// 用「真实回单形状」的夹具锁住解析行为。
//
// 为什么需要这一份：`bill_csv_test.dart` 里的样本是手写的 5 行前言，
// 而支付宝 App 实际导出的文件是 **23 行前言 + 带尾随逗号与空格填充的表头**，
// 部分字段还夹着制表符。这两种形状在表头定位、列切分上不是一回事，
// 手写样本跑绿不代表真实文件跑绿。
//
// 夹具为**合成数据**（账户 sample@example.com、商户「示例商户甲/乙/丙…」），
// 只保留真实文件的**结构特征**。结构特征取自 Apache-2.0 开源的
// double-entry-generator 项目的 example/alipay 样本（已由该项目作者脱敏）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/bill_csv.dart';
import 'package:ledger/data/models.dart';

void main() {
  final bytes = File('test/fixtures/alipay_real_shape_utf8.csv').readAsBytesSync();
  final result = BillCsv.parse(bytes);

  test('23 行前言之后才找到表头（headerLine = 24）', () {
    expect(result.headerLine, 24);
  });

  test('识别为支付宝来源', () {
    expect(result.source, BillSource.alipay);
    expect(result.encoding, BillEncoding.utf8);
  });

  test('6 条明细里只有 4 条可导入，2 条被跳过', () {
    expect(result.rows.length, 4);
    // 不计收支 1 条 + 交易关闭 1 条
    expect(result.skippedLines, 2);
  });

  test('金额按分解析，收入行默认不勾', () {
    final cents = result.rows.map((r) => r.amountCents).toList();
    expect(cents, [4974, 2000, 10000, 4190]);

    final income = result.rows.where((r) => r.type == TxnType.income).toList();
    expect(income.length, 1);
    expect(income.single.amountCents, 10000);
    expect(
      income.single.include,
      isFalse,
      reason: '收入行默认不勾选 —— 分类映射容易错，要用户主动确认',
    );
  });

  test('行号能对回源文件（第一条在 25 行）', () {
    expect(result.rows.first.lineNo, 25);
    expect(result.rows.first.date, '2023-02-12');
    expect(result.rows.first.time, '21:32');
    expect(result.rows.first.counterparty, '示例商户甲');
  });
}
