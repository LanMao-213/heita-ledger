import 'package:flutter/material.dart';

import '../../../theme/palette.dart';
import '../../widgets/roadmap_list.dart';

/// 明细页（tab 0 / 底栏槽位 0）。
///
/// **阶段 0 是占位内容**：真实结构（概览卡 + 按日分组 + keyset 分页 + 翻期）
/// 在 T02-2 落地。这一阶段唯一必须成立的是「壳」的部分：
/// ① 页面可横滑进入；② 切走再回来滚动位置不变（`AutomaticKeepAliveClientMixin`）。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with AutomaticKeepAliveClientMixin<DetailPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // AutomaticKeepAliveClientMixin 要求 build 里先调 super.build
    super.build(context);
    final AppPalette pal = context.pal;
    return ColoredBox(
      color: pal.bg,
      child: const SafeArea(
        bottom: false,
        child: RoadmapList(
          icon: Icons.receipt_long_outlined,
          title: '还没有账目',
          hint: '这一页将来是当前周期的全部流水：概览卡、按日分组、翻期与筛选。',
          items: <RoadmapItem>[
            RoadmapItem(
              stage: 'T02-2',
              title: '概览卡与按日分组',
              detail: '本期收入 / 结余 / 笔数、预算进度条、每天一张日卡带当日小计',
            ),
            RoadmapItem(
              stage: 'T02-2',
              title: '三手势翻期 + keyset 分页',
              detail: '左滑下一期、右滑上一期、双击回今天；列表懒加载并在末尾标「已显示 N / 共 M」',
            ),
            RoadmapItem(
              stage: 'T02-3',
              title: '筛选与搜索',
              detail: '类型 / 分类两级 / 账户 / 金额区间 / 时间段；筛选一律跨全部历史',
            ),
            RoadmapItem(
              stage: 'T02-1',
              title: '中央「记一笔」',
              detail: '四段模式、表达式键盘、双轮盘分类、这笔算下一期',
            ),
          ],
        ),
      ),
    );
  }
}
