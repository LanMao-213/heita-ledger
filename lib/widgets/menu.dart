/// 二级 / 三级菜单的统一件（2026-10-24）。
///
/// ## 为什么要单独开这个文件
///
/// 改这一版之前，全 App 的弹层是「谁用到谁随手搭」：
/// - 把手有三种：宽 36 / 38，色 `C.line` / `C.line2`，还有自己画一个的；
/// - 弹层底有两种：`C.bg`（主题选择）和 `C.cardBg`（走 `bottomSheetTheme` 的
///   默认值），而菜单行直接铺在底上 —— 底和行同色，边界只能靠「有没有
///   分割线」猜；
/// - 分割线时有时无，缩进也不统一；
/// - 行高两种：11 和 14；
/// - 三级更散：约 20 个 `AlertDialog` 各自给按钮上色（`C.ink` / `C.ink2` /
///   `C.over` 混用），另有 3 个 `DropdownButtonFormField` 直接吃 M3 默认样式。
///
/// 这套件把上面这些收成一处：**二级用 [MenuGroup] + [MenuTile]，
/// 三级用 [showAppDialog] / [showAppConfirm]，选择类用 [showPickSheet]。**
///
/// ## 这一版的形状规则
///
/// - **面分层，不靠线分界**：弹层底是页面底 `C.bg`，菜单项装在 `C.cardBg`
///   的圆角卡里 —— 白卡浮在灰底上，边界自己就出来了。
/// - **分割线内缩到文字左边**（46 = 左内距 14 + 图标 20 + 间距 12），
///   不再横穿整行；组与组之间靠留白，不靠线。
/// - **危险项红字、同组**：`删除` 和 `编辑` 是同一个菜单的两条，拆成两张卡
///   反而像两个不相干的东西；「取消」语义是「关掉这一层」，才单独一张卡。
library;

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/tokens.dart';

// ─────────────────────────────────────────────────────────────── 二级：弹层

/// 菜单的一项。
class MenuAction {
  const MenuAction({
    required this.icon,
    required this.title,
    this.subtitle,
    this.danger = false,
    this.checked = false,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.popFirst = true,
    this.result,
  });

  final String icon;
  final String title;

  /// 标题下的小字。菜单项常要带一句解释（「历史记录照常显示」这类）
  final String? subtitle;

  /// 危险项（删除 / 清空 / 停用）：图标和文字一起转 `C.over`
  final bool danger;

  /// 选择类菜单里的勾。左右两态都占位，勾出现时不挤动文字
  final bool checked;

  /// 行尾自定义控件（账户行那颗 ⋯）。给了它就不画勾
  final Widget? trailing;

  /// 点了做什么。**弹层关闭之后**才执行，所以在闭包里可以放心用外层 context
  final VoidCallback? onTap;

  /// 灰掉但仍可见（正忙 / 不可用）
  final bool enabled;

  /// 先关弹层再执行 [onTap]。要在弹层里就地改状态的传 false
  final bool popFirst;

  /// 关弹层时带回的值。选择类菜单靠它把选中项传出去
  final Object? result;
}

/// 一张圆角卡里的一组菜单项：白卡 + 内缩分割线，组内是一个整体。
///
/// 两种用法：
/// - `MenuGroup(actions: [...])` —— 标准菜单项，行由 [MenuTile] 画；
/// - `MenuGroup(children: [...])` —— 行自己给（账户列表那类带 ⋯ 的行），
///   分割线照插，缩进自己定。
class MenuGroup extends StatelessWidget {
  const MenuGroup({
    super.key,
    this.actions,
    this.children,
    this.indent = kIndent,
  });

  /// 左内距 14 + 图标 20 + 间距 12 —— 分割线只切到文字开始的地方
  static const double kIndent = 46;

  final List<MenuAction>? actions;
  final List<Widget>? children;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final items = actions != null
        ? [for (final a in actions!) MenuTile(action: a)]
        : (children ?? const <Widget>[]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.sm),
      child: Material(
        color: C.cardBg,
        shape: Shape.squircle(R.card),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: C.line, indent: indent),
              items[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// [MenuAction] 的行。
class MenuTile extends StatelessWidget {
  const MenuTile({super.key, required this.action});

  final MenuAction action;

  @override
  Widget build(BuildContext context) {
    final a = action;
    final live = a.enabled && a.onTap != null;
    final fg = a.danger ? C.over : C.ink;

    final child = Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, 13, S.lg, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          LineIcon(a.icon, size: 20, color: a.danger ? C.over : C.ink2),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: T.body.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (a.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(a.subtitle!, style: T.caption),
                ],
              ],
            ),
          ),
          if (a.trailing != null) ...[
            const SizedBox(width: S.sm),
            a.trailing!,
          ] else if (a.checked)
            LineIcon('check', size: 18, color: C.accent)
          else
            const SizedBox(width: 18),
        ],
      ),
    );

    if (!live) return Opacity(opacity: 0.45, child: child);
    return InkWell(
      onTap: () {
        if (a.popFirst) Navigator.of(context).pop(a.result);
        a.onTap?.call();
      },
      child: child,
    );
  }
}

/// 弹层的外壳：把手 + 标题 + 内容。
///
/// 底色走 `C.bg`（页面底），菜单项自己带白卡 —— 「弹层浮在页面上」和
/// 「卡片浮在弹层上」于是是同一套关系，不用再给弹层发明第二种面。
class SheetShell extends StatelessWidget {
  const SheetShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.footnote,
    this.bottom,
  });

  final String title;

  /// 标题下的小字（「切换后立刻生效」这类）
  final String? subtitle;

  /// 标题行右侧（关闭 / 完成）
  final Widget? action;

  /// 内容。要不要滚动由调用方包 `Flexible` 决定
  final Widget child;

  /// 最底下的说明文字（灰、小）
  final String? footnote;

  /// 钉在底部的控件（输入框那类）
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final note = footnote;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: S.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: C.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: T.title),
                        if (sub != null) ...[
                          const SizedBox(height: 2),
                          Text(sub, style: T.caption),
                        ],
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            child,
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.lg),
                child: Text(note, style: T.caption),
              ),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

/// 二级动作菜单：标题 + 若干组菜单项 + 一张「取消」。
///
/// 用例：账户的 ⋯、分类的 ⋯、模板的 ⋯。
/// 菜单项点了之后**先关弹层**再执行 `onTap`，所以 `onTap` 里用外层 context
/// 是安全的（老代码要自己写 `Navigator.pop(ctx)`，漏一处就变成点了没反应）。
Future<V?> showMenuSheet<V>({
  required BuildContext context,
  required String title,
  String? subtitle,
  List<MenuGroup> groups = const [],
  Widget? body,
  String? footnote,
  String? cancelLabel = '取消',
  bool isScrollControlled = true,
}) {
  final cancel = cancelLabel;
  return showModalBottomSheet<V>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => SheetShell(
      title: title,
      subtitle: subtitle,
      footnote: footnote,
      child: Flexible(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...groups,
              ?body,
              if (cancel != null) _CancelCard(label: cancel),
              const SizedBox(height: S.sm),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 「取消」那张卡：语义是「关掉这一层」，所以单独立一张，不和菜单项混组。
class _CancelCard extends StatelessWidget {
  const _CancelCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.sm),
      child: Material(
        color: C.cardBg,
        shape: Shape.squircle(R.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pop(context),
          child: SizedBox(
            height: 50,
            child: Center(
              child: Text(
                label,
                style: T.body.copyWith(
                  color: C.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 选择类弹层的一个选项。
class PickOption<V> {
  const PickOption({
    required this.value,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final V value;
  final String icon;
  final String title;
  final String? subtitle;
}

/// 单选弹层：选中项右侧打勾，点了直接把值带回去。
///
/// 替掉原来的 `DropdownButtonFormField` —— M3 的下拉浮在界面上是一整套
/// Material 的形状和动效，和纸墨不是一路。
Future<V?> showPickSheet<V>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<PickOption<V>> options,
  V? current,
  String? footnote,
}) {
  return showMenuSheet<V>(
    context: context,
    title: title,
    subtitle: subtitle,
    footnote: footnote,
    cancelLabel: null,
    groups: [
      MenuGroup(
        actions: [
          for (final o in options)
            MenuAction(
              icon: o.icon,
              title: o.title,
              subtitle: o.subtitle,
              checked: o.value == current,
              result: o.value,
              onTap: () {},
            ),
        ],
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────── 三级：对话框

/// 对话框的一个按钮。
class DialogAction<V> {
  const DialogAction({
    required this.label,
    this.value,
    this.valueOf,
    this.danger = false,
    this.strong = false,
  });

  final String label;

  /// 带回去的值。单按钮的「知道了」不给就行
  final V? value;

  /// **点下去那一刻**才取值 —— 表单类对话框要读输入框里的当前文本，
  /// 写 `value: ctl.text` 的话取到的是建对话框那一刻的空串。
  final V? Function()? valueOf;

  /// 危险操作（删除 / 清空）：字转 `C.over`
  final bool danger;

  /// 主按钮：字加粗到 600。一个对话框只给一个
  final bool strong;
}

/// 统一的对话框。
///
/// 之前 20 处 `AlertDialog` 各自给按钮上色，取消键有 `C.ink` 也有 `C.ink2`，
/// 确认键有 `C.ink` 也有 `C.over` —— 同一个「确定」在两个页面长得不一样。
/// 这里定死：取消 = `C.ink2` 常规字重，确认 = `C.ink` 600，危险 = `C.over`
/// 600；两个按钮等宽横排、中间 1px 竖线，一个按钮就占满一行。
Future<V?> showAppDialog<V>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  required List<DialogAction<V>> actions,
  bool barrierDismissible = true,
}) {
  return showDialog<V>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => Dialog(
      backgroundColor: C.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Shape.squircle(R.lg),
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: _DialogBody<V>(
        title: title,
        message: message,
        content: content,
        actions: actions,
      ),
    ),
  );
}

class _DialogBody<V> extends StatelessWidget {
  const _DialogBody({
    required this.title,
    required this.actions,
    this.message,
    this.content,
  });

  final String title;
  final String? message;
  final Widget? content;
  final List<DialogAction<V>> actions;

  @override
  Widget build(BuildContext context) {
    // 表单类对话框内容会长（周期账单那种一屏塞不下），给它一个上限让它滚
    final maxH = MediaQuery.sizeOf(context).height * 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: S.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.xl),
          child: Text(title, style: T.section, textAlign: TextAlign.center),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.xl, S.sm, S.xl, 0),
            child: Text(message!, style: T.body2, textAlign: TextAlign.center),
          ),
        if (content != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(S.xl, S.md, S.xl, 0),
              child: content,
            ),
          ),
        const SizedBox(height: S.xl),
        _DialogActions<V>(actions: actions),
      ],
    );
  }
}

class _DialogActions<V> extends StatelessWidget {
  const _DialogActions({required this.actions});

  final List<DialogAction<V>> actions;

  @override
  Widget build(BuildContext context) {
    // 三个以上竖排：横排会把字挤成一个字宽
    if (actions.length > 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: C.line),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: C.line),
            _DialogButton<V>(action: actions[i]),
          ],
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: C.line, width: 1)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: C.line),
              Expanded(child: _DialogButton<V>(action: actions[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _DialogButton<V> extends StatelessWidget {
  const _DialogButton({required this.action});

  final DialogAction<V> action;

  @override
  Widget build(BuildContext context) {
    final color = action.danger ? C.over : (action.strong ? C.ink : C.ink2);
    return InkWell(
      onTap: () => Navigator.pop(
        context,
        action.valueOf != null ? action.valueOf!() : action.value,
      ),
      child: SizedBox(
        height: 50,
        child: Center(
          child: Text(
            action.label,
            style: T.body.copyWith(
              color: color,
              fontWeight: action.strong || action.danger
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 二次确认。返回 `true` 表示用户认了。
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool danger = false,
}) async {
  final v = await showAppDialog<bool>(
    context: context,
    title: title,
    message: message,
    actions: [
      DialogAction(label: cancelLabel, value: false),
      DialogAction(
        label: confirmLabel,
        value: true,
        danger: danger,
        strong: true,
      ),
    ],
  );
  return v ?? false;
}

/// 单按钮的告知框（导入完成、已清空这类）。
Future<void> showAppNotice(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  String buttonLabel = '知道了',
}) {
  return showAppDialog<void>(
    context: context,
    title: title,
    message: message,
    content: content,
    actions: [DialogAction(label: buttonLabel, strong: true)],
  );
}

/// 表单里的「选择」行：左边字段名，右边当前值 + 下拉箭头。
///
/// 用在原本是 `DropdownButtonFormField` 的位置 —— 点开走 [showPickSheet]，
/// 不再弹 M3 的下拉菜单。
class PickField extends StatelessWidget {
  const PickField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onTap,
  });

  final String label;
  final String valueText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                valueText.isEmpty ? '请选择' : valueText,
                style: valueText.isEmpty
                    ? T.body.copyWith(color: C.ink3)
                    : T.body,
              ),
            ),
            LineIcon('chevron_down', size: 18, color: C.ink3),
          ],
        ),
      ),
    );
  }
}
