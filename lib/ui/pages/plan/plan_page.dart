import 'package:flutter/material.dart';

import '../../../theme/palette.dart';
import '../../widgets/roadmap_list.dart';

/// 计划页（tab 2 / 底栏槽位 3）。
///
/// **阶段 0 是占位内容**：往来摘要、总预算与节奏、分类预算、储蓄目标、周期账单
/// 入口在 T03-2 / T04-2 落地。
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage>
    with AutomaticKeepAliveClientMixin<PlanPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AppPalette pal = context.pal;
    return ColoredBox(
      color: pal.bg,
      child: const SafeArea(
        bottom: false,
        child: RoadmapList(
          icon: Icons.event_note_outlined,
          title: '还没有计划',
          hint: '这一页将来是预算与往来：额度、进度、每天可花，以及谁欠你多少。',
          items: <RoadmapItem>[
            RoadmapItem(
              stage: 'T03-2',
              title: '本期总预算与节奏',
              detail: '额度 + 本期借入 → 可用额度；「还剩 N 天 / 每天可花 X」按整除算',
            ),
            RoadmapItem(
              stage: 'T03-2',
              title: '分类预算',
              detail: '只列「设了预算的 ∪ 本期有支出的一级」，支出含其所有子分类',
            ),
            RoadmapItem(
              stage: 'T03-2',
              title: '储蓄目标',
              detail: '新建 / 编辑 / 删除 / 存钱 / 取钱；取超了按 0 兜底，且不生成流水',
            ),
            RoadmapItem(
              stage: 'T04-2',
              title: '周期账单',
              detail: '规则 CRUD + 到期补记 + 三道防重复闸 + 回前台补记',
            ),
          ],
        ),
      ),
    );
  }
}
