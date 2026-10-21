import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/data/models/models.dart';
import 'package:heita_ledger/ui/widgets/pickers/picker_wheels.dart';

/// 双轮盘：左轮必选、右轮首项「不细分」、右轮跟随左轮重建、已选子分类停在它上面。
void main() {
  final CategoryTree tree = CategoryTree(const <Category>[
    Category(id: 1, type: TxnType.expense, name: '餐饮', sortOrder: 0),
    Category(id: 2, ledgerId: 1, type: TxnType.expense, name: '正餐', parentId: 1, sortOrder: 0),
    Category(id: 3, ledgerId: 1, type: TxnType.expense, name: '饮品', parentId: 1, sortOrder: 1),
    Category(id: 4, type: TxnType.expense, name: '出行', sortOrder: 1),
    Category(id: 5, ledgerId: 1, type: TxnType.expense, name: '打车', parentId: 4, sortOrder: 0),
    Category(id: 6, type: TxnType.income, name: '工资', sortOrder: 0),
  ]);

  test('① 左轮 = 该类型的一级分类（顺序按 sort_order）', () {
    final CategoryWheelData d = CategoryWheelData(tree, TxnType.expense);
    expect(d.tops.map((Category c) => c.name), <String>['餐饮', '出行']);
    expect(d.selectedTopId, 1, reason: '左轮必选：默认停在第一个');
  });

  test('①② 右轮首项永远是「不细分」（= category_id 指向一级）', () {
    final CategoryWheelData d = CategoryWheelData(tree, TxnType.expense);
    expect(d.subItems.first, isNull);
    expect(d.subItems.length, 3, reason: '不细分 + 正餐 + 饮品');
    expect(d.subIndex, 0);
    expect(d.selectedSubId, isNull, reason: '停在「不细分」时子分类为空');
  });

  test('② 右轮跟随左轮重建，并把选择重置回「不细分」', () {
    final CategoryWheelData d = CategoryWheelData(tree, TxnType.expense)
      ..selectSub(1);
    expect(d.selectedSubId, 2);

    d.selectTop(1); // 切到「出行」
    expect(d.selectedTopId, 4);
    expect(d.subIndex, 0, reason: '换了大类，旧的子分类不再成立');
    expect(d.selectedSubId, isNull);
    expect(d.subItems.map((Category? c) => c?.name), <String?>[null, '打车']);
  });

  test('② 传入已选子分类时，右轮停在它上面', () {
    final CategoryWheelData d = CategoryWheelData(
      tree,
      TxnType.expense,
      subId: 3,
    );
    expect(d.selectedTopId, 1);
    expect(d.subIndex, 2);
    expect(d.selectedSubId, 3);
  });

  test('② 传入的 topId 认不出（脏数据）→ 回落第一个，不抛', () {
    final CategoryWheelData d = CategoryWheelData(
      tree,
      TxnType.expense,
      topId: 999,
    );
    expect(d.selectedTopId, 1);
    expect(d.subItems, hasLength(3));
  });

  test('② 收入类型只看到收入一级分类', () {
    final CategoryWheelData d = CategoryWheelData(tree, TxnType.income);
    expect(d.tops.map((Category c) => c.name), <String>['工资']);
  });

  test('② 没有子分类的一级：右轮只有「不细分」一项', () {
    final CategoryWheelData d = CategoryWheelData(
      tree,
      TxnType.income,
    );
    expect(d.subItems, hasLength(1));
    expect(d.subItems.single, isNull);
    expect(d.selectSub(5).selectedSubId, isNull, reason: '越界也不许崩');
  });
}
