import 'package:heita_ledger/core/local_date.dart';
import 'package:heita_ledger/data/db/db.dart';
import 'package:heita_ledger/data/db/schema.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/data/repo/repo.dart';
import 'package:sqflite/sqflite.dart';

/// repo 测试的共用构造器。
///
/// 测试数据一律**显式传每个字段**：默认值藏在构造器里，改一次默认值可能
/// 悄悄改掉十条断言的语义。
Txn mkTxn({
  required int ledgerId,
  required int amountCents,
  TxnType type = TxnType.expense,
  LocalDate? date,
  LocalDate? periodStart,
  int? categoryId,
  int? accountId,
  int? debtId,
  int? recurringId,
  int? templateId,
  String note = '',
  String? person,
}) {
  return Txn(
    ledgerId: ledgerId,
    type: type,
    amountCents: amountCents,
    categoryId: categoryId,
    accountId: accountId,
    debtId: debtId,
    recurringId: recurringId,
    templateId: templateId,
    date: date ?? const LocalDate(2026, 10, 16),
    periodStart: periodStart,
    note: note,
    person: person,
    createdAt: DateTime(2026, 10, 16, 9),
  );
}

/// 种子里的默认账户 id（`onCreate` 播的「现金」）。
Future<int> defaultAccountId() async {
  final Database db = await Db.open();
  final List<Map<String, Object?>> rows = await db.query(
    Tables.account,
    columns: <String>[AccountCols.id],
    orderBy: '${AccountCols.id} ASC',
    limit: 1,
  );
  return asInt(rows.first[AccountCols.id]);
}

/// 当前账本 id。
Future<int> currentLedger() => Repo.ledger.currentId();

/// 取某个一级分类 id（默认取支出一侧的第一个）。
Future<int> topCategoryId({TxnType type = TxnType.expense}) async {
  final Database db = await Db.open();
  final List<Map<String, Object?>> rows = await db.query(
    Tables.category,
    columns: <String>[CategoryCols.id],
    where: '${CategoryCols.parentId} IS NULL AND ${CategoryCols.type} = ?',
    whereArgs: <Object?>[type.code],
    orderBy: '${CategoryCols.sortOrder} ASC',
    limit: 1,
  );
  return asInt(rows.first[CategoryCols.id]);
}

/// 取某个一级分类下的第一个子分类 id。
Future<int> childCategoryId(int parentId) async {
  final Database db = await Db.open();
  final List<Map<String, Object?>> rows = await db.query(
    Tables.category,
    columns: <String>[CategoryCols.id],
    where: '${CategoryCols.parentId} = ?',
    whereArgs: <Object?>[parentId],
    orderBy: '${CategoryCols.sortOrder} ASC',
    limit: 1,
  );
  return asInt(rows.first[CategoryCols.id]);
}

/// 账户余额（读库）。
Future<int> balanceOf(int accountId) async {
  final Database db = await Db.open();
  final List<Map<String, Object?>> rows = await db.query(
    Tables.account,
    columns: <String>[AccountCols.balanceCents],
    where: '${AccountCols.id} = ?',
    whereArgs: <Object?>[accountId],
    limit: 1,
  );
  return asInt(rows.first[AccountCols.balanceCents]);
}
