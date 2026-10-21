import 'package:flutter/material.dart';

import '../../../theme/palette.dart';
import '../../widgets/roadmap_list.dart';

/// 图表页（tab 1 / 底栏槽位 1）。
///
/// **阶段 0 是占位内容**：四张自绘图（环形饼 / 分类排行 / 每日柱 / 近 6 段双柱）
/// 与统计骨架在 T03-1 落地。见架构设计 §5.3：统计页首帧必须渲染骨架而不是
/// 「本期还没有数据」—— 这是原版栽过、且没被测试挡住的那个坑（I20）。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage>
    with AutomaticKeepAliveClientMixin<StatsPage> {
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
          icon: Icons.pie_chart_outline,
          title: '还没有图表',
          hint: '这一页将来是四种图：本期 / 本月两个口径，支出 / 收入两档。',
          items: <RoadmapItem>[
            RoadmapItem(
              stage: 'T03-1',
              title: '环形饼 + 分类排行',
              detail: '色阶严格由深到浅、合计 ≤0 的分类不参与；排行点一行跳明细并带上当前区间',
            ),
            RoadmapItem(
              stage: 'T03-1',
              title: '每日柱 + 近 6 段双柱',
              detail: '区间内每天都占一格、零值不画柱；趋势用 1 条合并查询取回',
            ),
            RoadmapItem(
              stage: 'T03-1',
              title: '统计骨架与脏标记',
              detail: '先渲染上次快照，后台重算；失败保留旧值不清空',
            ),
            RoadmapItem(
              stage: 'T03-1',
              title: '账户资产卡',
              detail: 'Σ 计入净资产的账户余额（不含应收应付）',
            ),
          ],
        ),
      ),
    );
  }
}
