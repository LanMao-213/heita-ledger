import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/tokens.dart';
import 'common.dart';

/// 双轮盘的选择结果。
///
/// 一级分类必选，子分类可空 —— 空表示「这一笔不细分」。
class CatPick {
  const CatPick({required this.categoryId, this.subId});

  /// 一级分类 id
  final int categoryId;

  /// 子分类 id；null = 不细分，这笔直接挂在一级上
  final int? subId;

  /// 真正写进 `txn.category_id` 的值
  int get txnCategoryId => subId ?? categoryId;
}

/// 打开「分类 + 子分类」双轮盘。返回 null 表示取消。
///
/// 左轮是一级分类，右轮跟着左轮实时换；右轮首项固定「不细分」——
/// 允许用户只记到一级，不强迫每笔都挑子分类（记账最大的敌人是步骤多）。
Future<CatPick?> showCategoryWheel(
  BuildContext context, {
  required List<Category> cats,
  required List<Category> Function(int parentId) childrenOf,

  /// 当前已选中的分类，可能是子分类（编辑老记录时会这样）
  int? selectedCategoryId,
}) {
  if (cats.isEmpty) return Future<CatPick?>.value();
  return showModalBottomSheet<CatPick>(
    context: context,
    // 轮盘自己吃竖直方向的拖动，面板再插一脚会把滚动抢走
    enableDrag: false,
    // 不放开的话默认只给屏幕高度的 9/16：轮盘从 192 抬到 240 之后，
    // 矮屏（含 800×600 的测试画布）会被裁掉 38px，确定键直接点不到
    isScrollControlled: true,
    builder: (_) => _CatWheelSheet(
      cats: cats,
      childrenOf: childrenOf,
      selectedCategoryId: selectedCategoryId,
    ),
  );
}

class _CatWheelSheet extends StatefulWidget {
  const _CatWheelSheet({
    required this.cats,
    required this.childrenOf,
    required this.selectedCategoryId,
  });

  final List<Category> cats;
  final List<Category> Function(int parentId) childrenOf;
  final int? selectedCategoryId;

  @override
  State<_CatWheelSheet> createState() => _CatWheelSheetState();
}

class _CatWheelSheetState extends State<_CatWheelSheet> {
  /// 右轮第 0 项：只记到一级
  static const _noSub = '不细分';

  late int _catIndex;

  /// 0 = 不细分；i > 0 = 子分类列表的第 i-1 项
  late int _subIndex;
  late FixedExtentScrollController _catCtrl;
  late FixedExtentScrollController _subCtrl;

  List<Category> _subsOf(int catIndex) =>
      widget.childrenOf(widget.cats[catIndex].id);

  @override
  void initState() {
    super.initState();
    var cat = widget.cats.indexWhere((c) => c.id == widget.selectedCategoryId);
    var sub = 0;
    if (cat < 0 && widget.selectedCategoryId != null) {
      // 选中的是子分类：反查它属于哪个一级，右轮直接停在它上面
      for (var i = 0; i < widget.cats.length; i++) {
        final j = _subsOf(i).indexWhere(
          (s) => s.id == widget.selectedCategoryId,
        );
        if (j < 0) continue;
        cat = i;
        sub = j + 1;
        break;
      }
    }
    _catIndex = cat < 0 ? 0 : cat;
    _subIndex = sub;
    _catCtrl = FixedExtentScrollController(initialItem: _catIndex);
    _subCtrl = FixedExtentScrollController(initialItem: _subIndex);
  }

  @override
  void dispose() {
    _catCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subs = _subsOf(_catIndex);
    final subLabels = [_noSub, for (final s in subs) s.name];

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: '选择分类'),
          // 240 / 52：原 192 / 40 的转轮在小屏上只能露出 4 行，选中行偏细、
          // 单手滚动容易滑过头。抬高到 240 后能稳定露出 5 行，指腹落点更准
          SizedBox(
            height: 240,
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: CupertinoPicker(
                    scrollController: _catCtrl,
                    itemExtent: 52,
                    onSelectedItemChanged: _onCatChanged,
                    selectionOverlay:
                        const CupertinoPickerDefaultSelectionOverlay(
                          background: C.inkWash,
                        ),
                    children: [
                      for (var i = 0; i < widget.cats.length; i++)
                        Center(
                          child: _wheelText(
                            widget.cats[i].name,
                            i == _catIndex,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(width: 1, height: 160, color: C.line),
                Expanded(
                  flex: 5,
                  child: CupertinoPicker(
                    // 换分类时整条重建，避免残留上一组的滚动偏移
                    key: ValueKey('sub-$_catIndex'),
                    scrollController: _subCtrl,
                    itemExtent: 52,
                    onSelectedItemChanged: (i) =>
                        setState(() => _subIndex = i),
                    selectionOverlay:
                        const CupertinoPickerDefaultSelectionOverlay(
                          background: C.inkWash,
                        ),
                    children: [
                      for (var i = 0; i < subLabels.length; i++)
                        Center(
                          child: _wheelText(
                            subLabels[i],
                            i == _subIndex,
                            // 「不细分」是兜底项，视觉上比具体子分类轻一档
                            muted: i == 0,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (subs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, 0),
              child: Text(
                '这个分类还没有子分类，可在「我的 → 分类管理」里添加',
                style: T.caption.copyWith(color: C.ink4),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.md),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(R.md),
                        border: Border.all(color: C.line2),
                      ),
                      child: Text('取消', style: T.body2.copyWith(color: C.ink2)),
                    ),
                  ),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _done,
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.ink,
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: Text(
                        '确定',
                        style: T.body.copyWith(
                          color: C.bg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onCatChanged(int i) {
    final old = _subCtrl;
    setState(() {
      _catIndex = i;
      _subIndex = 0;
      // 换了分类，右轮的内容整条换掉，用新控制器避免残留滚动偏移
      _subCtrl = FixedExtentScrollController(initialItem: 0);
    });
    // 等这一帧把旧轮子拆掉之后再释放
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _done() {
    final subs = _subsOf(_catIndex);
    Navigator.pop(
      context,
      CatPick(
        categoryId: widget.cats[_catIndex].id,
        subId: _subIndex == 0 ? null : subs[_subIndex - 1].id,
      ),
    );
  }

  Widget _wheelText(String text, bool selected, {bool muted = false}) {
    final color = selected ? (muted ? C.ink2 : C.ink) : C.ink3;
    return Text(
      text,
      style: TextStyle(
        fontSize: selected ? 18 : 16.5,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: color,
      ),
    );
  }
}
