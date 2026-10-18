import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/note_hints.dart';
import '../design/tokens.dart';
import 'common.dart';

/// 双轮盘的选择结果。
///
/// [note] 为 null 表示「用户选了自定义，别动我原来的备注」；为空串表示「清掉备注」。
class NotePick {
  const NotePick({required this.categoryId, required this.note});

  final int categoryId;
  final String? note;
}

/// 打开「分类 + 名目」双轮盘。返回 null 表示取消。
///
/// 左轮是该收支类型下的分类，右轮跟着左轮实时换；右轮末尾固定一项「自定义…」，
/// 选中它就等于「不套用名目，回备注框自己写」。
Future<NotePick?> showCategoryNoteWheel(
  BuildContext context, {
  required List<Category> cats,
  required int? categoryId,
  required TxnType type,
  String note = '',
}) {
  if (cats.isEmpty) return Future<NotePick?>.value();
  return showModalBottomSheet<NotePick>(
    context: context,
    // 轮盘自己吃竖直方向的拖动，面板再插一脚会把滚动抢走
    enableDrag: false,
    builder: (_) => _NoteWheelSheet(
      cats: cats,
      categoryId: categoryId,
      type: type,
      note: note,
    ),
  );
}

class _NoteWheelSheet extends StatefulWidget {
  const _NoteWheelSheet({
    required this.cats,
    required this.categoryId,
    required this.type,
    required this.note,
  });

  final List<Category> cats;
  final int? categoryId;
  final TxnType type;
  final String note;

  @override
  State<_NoteWheelSheet> createState() => _NoteWheelSheetState();
}

class _NoteWheelSheetState extends State<_NoteWheelSheet> {
  /// 右轮末尾的自定义项
  static const _custom = '自定义…';

  late int _catIndex;
  late int _hintIndex;
  late FixedExtentScrollController _catCtrl;
  late FixedExtentScrollController _hintCtrl;

  List<String> _hintsOf(int catIndex) => [
    ...noteHintsFor(widget.type, widget.cats[catIndex].name),
    _custom,
  ];

  @override
  void initState() {
    super.initState();
    final i = widget.cats.indexWhere((c) => c.id == widget.categoryId);
    _catIndex = i < 0 ? 0 : i;

    final hints = _hintsOf(_catIndex);
    // 已有备注能对上名目就停在那一格；对不上（包含空）就停在「自定义…」
    final j = hints.indexOf(widget.note);
    _hintIndex = j < 0 ? hints.length - 1 : j;

    _catCtrl = FixedExtentScrollController(initialItem: _catIndex);
    _hintCtrl = FixedExtentScrollController(initialItem: _hintIndex);
  }

  @override
  void dispose() {
    _catCtrl.dispose();
    _hintCtrl.dispose();
    super.dispose();
  }

  void _onCatChanged(int i) {
    if (i == _catIndex) return;
    final old = _hintCtrl;
    setState(() {
      _catIndex = i;
      _hintIndex = 0;
      // 换了分类，右轮的内容整条换掉，用新控制器避免残留滚动偏移
      _hintCtrl = FixedExtentScrollController(initialItem: 0);
    });
    // 等这一帧把旧轮子拆掉之后再释放
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _done() {
    final hints = _hintsOf(_catIndex);
    final isCustom = _hintIndex >= hints.length - 1;
    Navigator.pop(
      context,
      NotePick(
        categoryId: widget.cats[_catIndex].id,
        note: isCustom ? null : hints[_hintIndex],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.cats;
    final hints = _hintsOf(_catIndex);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: '选择分类'),
          SizedBox(
            height: 192,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: CupertinoPicker(
                    scrollController: _catCtrl,
                    itemExtent: 40,
                    onSelectedItemChanged: _onCatChanged,
                    selectionOverlay:
                        const CupertinoPickerDefaultSelectionOverlay(
                          background: C.inkWash,
                        ),
                    children: [
                      for (var i = 0; i < cats.length; i++)
                        Center(child: _wheelText(cats[i].name, i == _catIndex)),
                    ],
                  ),
                ),
                Container(width: 1, height: 132, color: C.line),
                Expanded(
                  flex: 4,
                  child: CupertinoPicker(
                    key: ValueKey('hint-$_catIndex'),
                    scrollController: _hintCtrl,
                    itemExtent: 40,
                    onSelectedItemChanged: (i) =>
                        setState(() => _hintIndex = i),
                    selectionOverlay:
                        const CupertinoPickerDefaultSelectionOverlay(
                          background: C.inkWash,
                        ),
                    children: [
                      for (var i = 0; i < hints.length; i++)
                        Center(child: _wheelText(hints[i], i == _hintIndex)),
                    ],
                  ),
                ),
              ],
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

  Widget _wheelText(String text, bool selected) {
    return Text(
      text,
      style: TextStyle(
        fontSize: selected ? 15.5 : 14.5,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? C.ink : C.ink3,
      ),
    );
  }
}
