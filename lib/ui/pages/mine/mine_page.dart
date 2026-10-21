import 'package:flutter/material.dart';

import '../../../core/scope.dart';
import '../../../stores/shell_store.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';
import '../../widgets/roadmap_list.dart';
import '../../widgets/toast.dart';

/// 我的页（tab 3 / 底栏槽位 4）。
///
/// **阶段 0 是占位内容**，但带一个**真功能**：配色切换。用户要求「两套配色运行时
/// 切换」，验证它不用等阶段 5 —— 这里就是那个临时入口（M09-F13 / 架构设计 §4-⑥）。
class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage>
    with AutomaticKeepAliveClientMixin<MinePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AppPalette pal = context.pal;
    final ShellStore shell = ShellScope.watch(context);
    return ColoredBox(
      color: pal.bg,
      child: SafeArea(
        bottom: false,
        child: RoadmapList(
          icon: Icons.person_outline,
          title: '这里还没有内容',
          hint: '这一页将来是净资产、账户、账本、账单日与数据安全。',
          leading: PaletteSwitcher(shell: shell),
          items: const <RoadmapItem>[
            RoadmapItem(
              stage: 'T05-1',
              title: '净资产 + 账户管理',
              detail: '账户余额 + 应收 − 应付；改账户不碰 opening 与 balance',
            ),
            RoadmapItem(
              stage: 'T05-1',
              title: '账本 / 账单日 / 触感',
              detail: '新建账本自动灌完整两级分类；改账单日会重算全部归属期',
            ),
            RoadmapItem(
              stage: 'T05-2',
              title: '备份 / 恢复 / 快照',
              detail: '先写快照再覆盖；备份为明文 JSON，导出时明确提示未加密',
            ),
            RoadmapItem(
              stage: 'T05-3',
              title: '旧版备份导入',
              detail: 'v5 / v6 / v7 / v8 四种历史形态，导入后自动跑一遍数据体检',
            ),
          ],
        ),
      ),
    );
  }
}

/// 配色切换（阶段 0 的临时入口）。
///
/// 切换路径：点一行 → [ShellStore.setPalette] → 内存立即变 + 落库 + 1 次通知
/// → `MaterialApp` 重建 theme → `AnimatedTheme` 做 200ms 插值 → 整屏跟着变。
/// **无需重启**，因为所有页面取色都走 `context.pal.*`，没有一处写死颜色。
class PaletteSwitcher extends StatelessWidget {
  const PaletteSwitcher({super.key, required this.shell});

  final ShellStore shell;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return Container(
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: R.rCard,
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('配色', style: Ts.section.copyWith(color: pal.ink)),
          const SizedBox(height: 2),
          Text(
            '两套配色运行时切换，切完整屏立刻生效、无需重启。',
            style: Ts.caption.copyWith(color: pal.ink3),
          ),
          const SizedBox(height: S.sm),
          for (final AppPalette option in AppPalette.all)
            _PaletteOption(
              option: option,
              selected: option.id == pal.id,
              onTap: () {
                if (option.id == pal.id) return;
                shell.setPalette(option);
                showToast(context, '已切到「${option.label}」');
              },
            ),
        ],
      ),
    );
  }
}

class _PaletteOption extends StatelessWidget {
  const _PaletteOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppPalette option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    return InkWell(
      key: ValueKey<String>('palette-${option.id}'),
      onTap: onTap,
      borderRadius: R.rMd,
      child: Container(
        constraints: const BoxConstraints(minHeight: S.touch),
        padding: const EdgeInsets.symmetric(
          horizontal: S.sm,
          vertical: S.sm,
        ),
        child: Row(
          children: <Widget>[
            // 用这套配色自己的强调色做色点，一眼看出选的是哪套
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: option.accent,
                shape: BoxShape.circle,
                border: Border.all(color: option.lineStrong),
              ),
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Text(
                option.label,
                style: Ts.body.copyWith(
                  color: selected ? pal.ink : pal.ink2,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: pal.navActive),
          ],
        ),
      ),
    );
  }
}
