import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/palette.dart';
import '../design/tokens.dart';

/// 主题选择弹层（我的 → 偏好 → 主题）。
///
/// ## 为什么每行都画一个「迷你界面」而不是几个色块
///
/// 色块只能告诉用户「这套里有这几个颜色」，但判断不出**层级对不对** ——
/// 而换肤真正影响观感的是 bg / cardBg / ink 三者的明度关系。所以这里用
/// 真实 token 画一个 56×40 的小窗口：底是 `bg`、卡片是 `cardBg`、
/// 两条文字条是 `ink` / `ink3`、下面两根短条是 `accent` / `over`。
/// 层级塌掉的皮肤在缩略图里会先塌给用户看。
///
/// 返回被选中的 [HeitaThemeId]；点空白处返回 null。
Future<HeitaThemeId?> showThemeSheet(
  BuildContext context, {
  required HeitaThemeId current,
}) {
  return showModalBottomSheet<HeitaThemeId>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _ThemeSheet(current: current),
  );
}

class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.current});

  final HeitaThemeId current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
        ),
        padding: const EdgeInsets.only(top: S.md, bottom: S.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: C.line,
                borderRadius: BorderRadius.circular(R.xs),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
              child: Row(
                children: [
                  Text('主题', style: T.section),
                  const Spacer(),
                  Text('切换后立刻生效', style: T.caption),
                ],
              ),
            ),
            // ⚠️ 这里用 SingleChildScrollView + Column，不用 ListView.separated：
            // 弹层有最大高度（约屏高的 9/16），ListView 只会构建可见的那几行 ——
            // 第六套就不是「滚一下能看到」，而是根本没被创建。套数以后还会加。
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < kPalettes.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: C.line,
                          indent: 76,
                        ),
                      _ThemeRow(
                        palette: kPalettes[i],
                        selected: kPalettes[i].id == current,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.palette, required this.selected});

  final Palette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, palette.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 11),
        child: Row(
          children: [
            _PaletteChip(palette: palette),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    palette.name,
                    style: T.body.copyWith(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(palette.subtitle, style: T.caption),
                ],
              ),
            ),
            if (selected)
              LineIcon('check', size: 18, color: C.accent)
            else
              // 占位：保证选中/未选中两态的文字宽度一致，勾出现时不会挤动
              const SizedBox(width: 18),
          ],
        ),
      ),
    );
  }
}

/// 用真实 token 画的迷你界面（见文件头说明）。
class _PaletteChip extends StatelessWidget {
  const _PaletteChip({required this.palette});

  final Palette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 40,
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: palette.line),
      ),
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(5, 4, 5, 0),
              decoration: BoxDecoration(
                color: palette.cardBg,
                borderRadius: BorderRadius.circular(R.xs),
              ),
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(20, palette.ink),
                  const SizedBox(height: 3),
                  _bar(12, palette.ink3),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _bar(10, palette.accent),
              const SizedBox(width: 3),
              _bar(6, palette.over),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(double w, Color c) => Container(
        width: w,
        height: 3,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
}
