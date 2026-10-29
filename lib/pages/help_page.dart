import 'package:flutter/material.dart';

import '../app.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../widgets/common.dart';

/// 帮助说明：把「这个 App 的规则」写成一篇能从头读到尾的东西。
///
/// 为什么要有这一页：这些规则以前散在三处 —— 空态提示、对话框副标题、提交信息。
/// 用户真正会问的问题（「为什么这笔算到上个月」「换手机怎么搬」「口令忘了怎么办」）
/// 没有一个地方能一次答完。而记账应用里最贵的错误是**误解规则**：以为余额不对、
/// 以为数据丢了，然后卸载重装把账清掉。
///
/// 内容只写**已经成立的行为**。这里每一条都能在代码里找到落点，注释里标了文件名
/// —— 写帮助页最容易滑向「描述一个想象中的产品」，所以每条都留了可核对的锚点。
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('帮助说明'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: LineIcon('arrow_left', semanticLabel: '返回', size: 22, color: C.ink),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: S.xxl),
        children: [
          const SectionTitle('记账'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Item(
                  title: '一笔账有四种类型',
                  body: '支出、收入、借出、借入。前两种进收支统计；后两种只改「谁欠谁」，'
                      '不进统计 —— 借给朋友 500 不是消费，还回来也不是收入。'
                      '账户之间的挪钱用「转账」，它同样不计入收支。',
                ),
                _Item(
                  title: '账单日决定这笔算哪一期',
                  body: '默认每月 1 号起算一期。如果你把账单日设成 15 号，那 10 月 15 日到'
                      ' 11 月 14 日记的账都算「10 月这一期」。账单日可以在「我的 → 账单日」改，'
                      '改完会重算所有历史记录的归属期，金额一分不动。',
                ),
                _Item(
                  title: '分类是两级的',
                  body: '一级分类下面还有子分类（例如「餐饮 → 早餐」）。只记到一级也完全没问题，'
                      '统计时子分类会归到父级。不需要的分类可以在「分类管理」里归档，'
                      '归档不删历史记录。',
                ),
              ],
            ),
          ),
          const SectionTitle('三个页面'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Item(
                  title: '明细',
                  body: '按天倒序列出当期流水。点一行看详情，长按出菜单（编辑 / 删除）。'
                      '顶部概览卡上左右滑是翻上一期 / 下一期，双击回到本期；'
                      '在列表正文上左右滑是切换页面。右上角有筛选、搜索、多选。',
                ),
                _Item(
                  title: '图表',
                  body: '「本期」按归属期算，「本月」按自然日期算 —— 账单日不是 1 号时'
                      '这两个数字本来就不一样，那不是错。分类统计按金额从大到小排。',
                ),
                _Item(
                  title: '计划',
                  body: '分类预算：给某个分类设一个每期上限，超了会标红。'
                      '储蓄目标：设目标金额，存入 / 取出都记一笔流水，'
                      '有流水之后才会显示「按当前速度大概什么时候达成」。',
                ),
              ],
            ),
          ),
          const SectionTitle('侧拉栏'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Item(
                  title: '所有入口都在这里',
                  body: '从屏幕左边缘往右滑，或点任意页面左上角的三横，就能拉出侧拉栏。'
                      '导航、账户与分类管理、导出与备份、帮助，都在里面按组排好；'
                      '每一组的标题可以点，点一下就把这组收起来，下次打开还是收着的。',
                ),
                _Item(
                  title: '想再看一遍引导',
                  body: '侧拉栏 →「帮助」→「使用引导」。它会重新走一遍首次打开时的分步说明，'
                      '随时可以关掉，不会影响任何数据。',
                ),
              ],
            ),
          ),
          const SectionTitle('数据'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Item(
                  title: 'Excel 是给「看」的，备份是给「搬」的',
                  body: '导出 Excel 方便发给人或存网盘。要换手机、要重装，请用加密备份或明文备份 —— '
                      '它们带的是完整账本，恢复回去和原来一模一样。',
                ),
                _Item(
                  title: '加密备份的口令不保存',
                  body: '口令只在你输入的那一刻存在于内存里，不写盘、不进日志。'
                      '忘了就真的打不开 —— 这是加密的代价，不是缺陷。'
                      '重要账本建议同时留一份明文备份在自己电脑里。',
                ),
                _Item(
                  title: '恢复会覆盖，但先留快照',
                  body: '「从备份恢复」和「清空全部数据」都会先把当前数据存一份快照，'
                      '在「我的 → 数据安全」里能看到并回滚。所以手滑之后还有路可走。',
                ),
              ],
            ),
          ),
          const SectionTitle('隐私'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Item(
                  title: '不联网',
                  body: '这个应用不发起任何网络请求：没有账号、没有云同步、没有统计和广告 SDK。'
                      '安装包里连联网权限都没有申请。',
                ),
                _Item(
                  title: '数据只在本机',
                  body: '账本存在应用自己的数据库文件里。卸载应用会把它们一起删掉 —— '
                      '这也是为什么换手机、重装之前一定要先导出备份。',
                ),
              ],
            ),
          ),
          const SectionTitle('常见问题'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Item(
                  title: '换了账单日，历史数据会不会乱？',
                  body: '不会。金额、笔数、余额都不变，变的只是「这笔算在哪一期」。'
                      '已有预算会跟着挪到新的期上。',
                ),
                _Item(
                  title: '为什么余额和我算的对不上？',
                  body: '账户余额 = 期初值 + 这个账户上所有流水的合计。'
                      '借出 / 借入的流水会改余额但不进收支统计，容易造成「明明没花这么多」的错觉。'
                      '在「我的 → 账户管理」里可以校准余额，校准只改期初值，不动历史流水。',
                ),
                _Item(
                  title: '装不上 / 提示签名不一致',
                  body: '不同签名的安装包不能互相覆盖，只能先卸载再装 —— 卸载会清空账目。'
                      '装之前先导出备份，装完再恢复。',
                ),
                _Item(
                  title: '数据会不会被上传？',
                  body: '不会。应用没有联网能力，导出的文件也只在你主动分享时才离开本机。',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.xl, S.lg, 0),
            child: Text(
              '$kAppName v$kAppVersion · 本地版',
              textAlign: TextAlign.center,
              style: T.overline.copyWith(color: C.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条「小标题 + 说明」。
class _Item extends StatelessWidget {
  const _Item({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: T.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: S.xs),
          Text(body, style: T.body2),
        ],
      ),
    );
  }
}
