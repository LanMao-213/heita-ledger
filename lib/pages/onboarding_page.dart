import 'dart:async';

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';

/// 首次使用引导的**自动弹出**开关。
///
/// 默认开；只有 `test/flutter_test_config.dart` 会把它关掉 —— 引导是一层全屏
/// 遮罩，在任何「pump 整个 App 再点界面」的用例里，它都会盖住所有待点击的控件，
/// 让几十条与引导无关的测试报「找不到 tab」。关掉的是**自动**，不是引导本身：
/// 侧拉栏入口和 `test/onboarding_test.dart` 都照常能打开它。
///
/// 不用 `kDebugMode` 判：那样 debug 包在真机上也不会自动出现，等于把功能砍在
/// 开发环境里，反而更难验。
abstract final class Onboarding {
  static bool autoShow = true;
}

/// 打开引导。任何入口（首启动自动 / 侧拉栏「使用引导」）都走这一个。
Future<void> showOnboarding(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const OnboardingPage(),
    ),
  );
}

/// 一页引导的内容。
class _Step {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    required this.tips,
    this.brand = false,
  });

  final String icon;
  final String title;
  final String body;

  /// 两三条「具体在哪、点了会怎样」。引导最容易犯的错是只喊口号 ——
  /// 用户看完仍然不知道该点哪里。
  final List<String> tips;

  /// 第一页用品牌标志代替图标
  final bool brand;
}

const _steps = <_Step>[
  _Step(
    icon: 'book',
    brand: true,
    title: '欢迎使用黑塔消费日记',
    body: '一个只存在这台手机上的记账本。没有账号、不联网、不上传。',
    tips: [
      '打开就能记，不需要注册',
      '数据全部在本机的数据库文件里',
    ],
  ),
  _Step(
    icon: 'plus',
    title: '记一笔：底部中间的 ＋',
    body: '支出、收入、借出、借入四档，选好分类和账户就能存。',
    tips: [
      '账单日决定这笔算哪一期，默认每月 1 号',
      '存完会告诉你它落到了哪一期',
    ],
  ),
  _Step(
    icon: 'menu',
    title: '侧拉栏：所有功能都在这里',
    body: '从屏幕左边缘往右滑，或点任意页面左上角的三横。',
    tips: [
      '导航、管理、数据、帮助按组排好，不再散在各处',
      '点分组标题就能把整组收起来，下次打开还是收着的',
    ],
  ),
  _Step(
    icon: 'list',
    title: '翻着看：明细与图表',
    body: '明细页顶部概览卡左右滑是翻上一期 / 下一期，双击回到本期；在列表正文上滑是换页。',
    tips: [
      '点一行看详情，长按出编辑 / 删除菜单',
      '图表页可以在「本期」和「本月」之间切换',
    ],
  ),
  _Step(
    icon: 'shield',
    title: '数据在你手里',
    body: '换手机或重装之前，先去侧拉栏导出备份 —— 卸载会把账目一起删掉。',
    tips: [
      '加密备份要设口令，口令不会保存，忘了就打不开',
      '恢复与清空都会先自动留一份快照，可以回滚',
    ],
  ),
];

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _page = PageController();
  int _index = 0;

  bool get _last => _index == _steps.length - 1;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  /// 结束引导（走完或跳过都算）。
  ///
  /// **落库不 await**：`finishOnboarding` 会先把内存里的「待弹出」置 false（同步），
  /// 再去写库。写库是磁盘 I/O，真机上几十毫秒，但在这几十毫秒里用户的手指已经
  /// 点上去了，表现就是「点了没反应」。所以界面立刻退出，写库在后台走完。
  ///
  /// 代价：进程如果在写库返回前被杀，下次启动会**再弹一次**引导。那是「多看一遍
  /// 说明书」，比「按了没反应」轻得多，所以这个顺序是有意选的。
  ///
  /// 先取 `NavigatorState` 再 pop：本 widget 在 pop 之后就没了，之后任何
  /// `Navigator.of(context)` 都会拿到已卸载的元素（`busy_dialog.dart` 同一条规矩）。
  void _finish() {
    final nav = Navigator.of(context);
    unawaited(Store.i.finishOnboarding());
    nav.pop();
  }

  void _next() {
    if (_last) {
      _finish();
      return;
    }
    _page.nextPage(duration: M.base, curve: M.standard);
  }

  void _prev() {
    if (_index == 0) return;
    _page.previousPage(duration: M.base, curve: M.standard);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 返回键/返回手势**也算看过**：不拦的话，用户按一次返回，下次启动
      // 又弹一遍 —— 他会以为这 App 只会重复同一件事。拦下来后按「跳过」处理。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const Spacer(),
                    // 跳过一直在：任何一步都该有一条「我知道了，别拦我」的路
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        '跳过',
                        style: T.body2.copyWith(
                          color: C.ink3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: S.sm),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _StepView(step: _steps[i]),
                ),
              ),
              _Dots(count: _steps.length, index: _index),
              const SizedBox(height: S.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.lg),
                child: Row(
                  children: [
                    // 「上一步」占位而不隐藏：隐藏会让主按钮左右横跳
                    SizedBox(
                      width: 72,
                      child: _index == 0
                          ? null
                          : TextButton(
                              onPressed: _prev,
                              child: Text('上一步', style: T.body2),
                            ),
                    ),
                    const SizedBox(width: S.sm),
                    Expanded(
                      child: _PrimaryButton(
                        label: _last ? '开始记账' : '下一步',
                        onTap: _next,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: S.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    // 垂直居中，而不是贴着顶部。
    //
    // 五步的文案都是两三行 + 两条补充，贴着顶部排版会在下方留出约 340dp 的
    // 空白 —— 那不像留白，像「内容没加载完」。居中后上下各留一半，
    // 视觉重心的位置与「一页一件事」的语气才对得上。
    //
    // 仍然套 `SingleChildScrollView`：大字号系统设置或横屏时内容会超过一屏，
    // 那时 `minHeight` 撑不到底，Column 自然变成「从头排、可滚」，
    // 不会把图标或按钮挤掉。
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: S.xxl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 96,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: C.bg2,
                      borderRadius: BorderRadius.circular(R.lg),
                    ),
                    child: Center(
                      child: step.brand
                          ? const BrandMark(height: 38)
                          : LineIcon(step.icon, size: 34, color: C.ink),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: S.xl),
              Text(step.title, style: T.title),
              const SizedBox(height: S.md),
              Text(
                step.body,
                style: T.body.copyWith(color: C.ink2, height: 1.6),
              ),
              const SizedBox(height: S.xl),
              for (final t in step.tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用小圆点而不是图标：这一列是「补充说明」，不是「功能入口」，
                      // 给它配图标会让它看起来可以点
                      Padding(
                        padding: const EdgeInsets.only(top: 7, right: S.md),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: C.ink3,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Expanded(child: Text(t, style: T.body2)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 步骤指示点：当前那一点拉长成一条，位置信息比「第 3/5 步」更快读。
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: M.fast,
            curve: M.standard,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? C.ink : C.line2,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// 主按钮：实心墨色。
///
/// 这个 App 里实心面只给「最想让人点的那一颗」（底栏的 ＋）。引导的「下一步」
/// 是同一性质，所以用同一种表达；其余动作一律是文字按钮（见 `menu.dart` 里的
/// `DialogAction`）。
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.ink,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Text(
          label,
          style: T.body.copyWith(color: C.bg, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
