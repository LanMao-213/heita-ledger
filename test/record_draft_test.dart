// `RecordDraft` 的规则测试。
//
// 为什么值得测：这些规则原先埋在记账面板 1,667 行的 `_save` 里，只能靠
// 「点开面板、填表、保存、再查库」来验证。而其中两条最容易出错、后果最隐蔽：
//   - 编辑时丢了 `id` → 变成新记一笔（用户以为改了，其实多出一笔）；
//   - 编辑时丢了 `createdAt` → 记录重新排到列表最前（看不出错，但顺序乱了）。
// 抽成草稿之后，这两条可以在毫秒级用例里钉死。
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/category_seed.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/record_draft.dart';

RecordDraft _draft({
  TxnType type = TxnType.expense,
  int amountCents = 1234,
  Map<TxnField, String> details = const {},
  Debt? debt,
  Txn? editing,
  int? templateId,
}) => RecordDraft(
  ledgerId: 7,
  type: type,
  amountCents: amountCents,
  date: '2026-10-26',
  accountId: 3,
  categoryId: 11,
  note: '午饭',
  details: details,
  debt: debt,
  editing: editing,
  templateId: templateId,
);

Txn _old() => const Txn(
  id: 42,
  ledgerId: 9,
  type: TxnType.expense,
  amountCents: 500,
  date: '2026-10-01',
  categoryId: 2,
  accountId: 4,
  note: '旧的',
  templateId: 77,
  recurringId: 88,
  createdAt: '2026-10-01T08:00:00.000',
);

void main() {
  group('分支判定', () {
    test('没有借贷也没有老记录 → insert', () {
      expect(_draft().action, RecordAction.insert);
    });

    test('有老记录 → update', () {
      expect(_draft(editing: _old()).action, RecordAction.update);
    });

    test('借贷优先于编辑（两者都非空时走借贷）', () {
      final d = _draft(
        debt: const Debt(
          id: 0,
          ledgerId: 7,
          direction: DebtDirection.lent,
          counterparty: '张三',
          amountCents: 5000,
          date: '2026-10-26',
        ),
        editing: _old(),
      );
      expect(d.action, RecordAction.lend);
    });
  });

  group('toTxn', () {
    test('新增：id 归零、账本取草稿、字段原样落到流水', () {
      final t = _draft(
        details: {
          TxnField.from: '公司',
          TxnField.to: '餐厅',
          TxnField.person: '小李',
          TxnField.subject: '聚餐',
        },
      ).toTxn();

      expect(t.id, 0);
      expect(t.ledgerId, 7);
      expect(t.type, TxnType.expense);
      expect(t.amountCents, 1234);
      expect(t.date, '2026-10-26');
      expect(t.accountId, 3);
      expect(t.categoryId, 11);
      expect(t.note, '午饭');
      expect(t.placeFrom, '公司');
      expect(t.placeTo, '餐厅');
      expect(t.person, '小李');
      expect(t.subject, '聚餐');
      expect(t.createdAt, '', reason: '新增由库侧填 createdAt');
    });

    test('编辑：保留 id / createdAt / recurringId / 老模板', () {
      final t = _draft(
        editing: _old(),
        templateId: 999, // 本次面板识别出的模板不该覆盖老记录的
      ).toTxn();

      expect(t.id, 42, reason: '丢了 id 就变成新记一笔');
      expect(t.ledgerId, 9, reason: '账本以老记录为准');
      expect(t.createdAt, '2026-10-01T08:00:00.000', reason: '否则排序会乱');
      expect(t.recurringId, 88);
      expect(t.templateId, 77);
      expect(t.amountCents, 1234, reason: '金额取本次输入');
      expect(t.date, '2026-10-26', reason: '日期取本次输入');
    });

    test('新增：本次模板记到流水上', () {
      final t = _draft(templateId: 55).toTxn();
      expect(t.templateId, 55);
      expect(t.id, 0);
    });

    test('详情字段缺键时落空串，不抛异常', () {
      final t = _draft(details: {TxnField.from: '只剩出发地'}).toTxn();
      expect(t.placeFrom, '只剩出发地');
      expect(t.placeTo, '');
      expect(t.person, '');
      expect(t.subject, '');
    });

    test('负数金额原样保留（净额记账靠符号），不在这里取绝对值', () {
      // 取绝对值是「借贷」这一分支的规则，由调用方在构造草稿时做；
      // 草稿本身不能偷偷改变金额，否则「支出 −20」这种净额记账会被抹平。
      final t = _draft(amountCents: -2000).toTxn();
      expect(t.amountCents, -2000);
    });
  });
}
