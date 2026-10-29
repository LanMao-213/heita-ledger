import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'common.dart';

// ---------------------------------------------------------------------------
// 口令输入：导出时设口令、恢复时输口令
// ---------------------------------------------------------------------------
//
// ## 为什么两个入口必须分开写
//
// 「设口令」要输两遍（第二遍是防手抖 —— 打错了自己看不见，加密完就再也
// 打不开），「输口令」只输一遍。把两者合成一个「输密码」组件、靠参数切行为，
// 结果一定是某次调用漏传那个参数，于是导出时没有二次确认。
//
// ## 文案的三条红线
//
// 1. **明说「我们不保存口令」**。这句话不是免责声明，是这个功能的**前提**：
//    口令存在设备上，加密导出就退化成「换了个格式的明文」。用户在这里
//    第一次、也是唯一一次被告知这件事，必须写在框旁边而不是折叠说明里。
// 2. **明说「忘了就打不开」**，而且要写「没有任何办法」——「找回」「重置」
//    这类词一个都不能出现，否则用户会去找那个不存在的按钮。
// 3. **明说「仍可以用明文导出」**。不给逃生路径的加密，会让「想把数据带走」
//    这件事在忘记口令那天彻底断掉 —— 而这份数据本来就允许明文导出（用户
//    自己的选择）。加密是选项，不是唯一出口。

/// 导出口令的最小长度。
///
/// 4 位数字在「文件已经离开这台手机」的场景里等于没有 —— 只有 10^4 种可能，
/// 拿到文件的人在本地跑一遍就知道了（迭代 21 万次 × 1 万次 ≈ 3 小时，一台
/// 笔记本一晚上）。6 位是个不精确但足够有说服力的下限；不强制大小写混排，
/// 那种规则只会把人逼去写 `Password1`。
const kMinPasswordLength = 6;

/// 让用户设一个导出口令。取消返回 null。
Future<String?> showExportPasswordSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const _ExportPasswordSheet(),
  );
}

/// 让用户输入恢复口令。[fileName] 只用来复述「你在打开哪个文件」。
/// 取消返回 null。
Future<String?> showUnlockPasswordSheet(
  BuildContext context, {
  String? fileName,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _UnlockPasswordSheet(fileName: fileName),
  );
}

class _ExportPasswordSheet extends StatefulWidget {
  const _ExportPasswordSheet();

  @override
  State<_ExportPasswordSheet> createState() => _ExportPasswordSheetState();
}

class _ExportPasswordSheetState extends State<_ExportPasswordSheet> {
  final _pw = TextEditingController();
  final _again = TextEditingController();
  bool _obscure = true;

  /// 提交过一次之后才显示错误：一开始就红一片，像在骂用户
  bool _tried = false;

  @override
  void dispose() {
    _pw.dispose();
    _again.dispose();
    super.dispose();
  }

  String? get _error {
    if (!_tried) return null;
    if (_pw.text.length < kMinPasswordLength) {
      return '口令至少要 $kMinPasswordLength 位';
    }
    if (_pw.text != _again.text) return '两次输入不一致';
    return null;
  }

  void _submit() {
    setState(() => _tried = true);
    if (_error == null) Navigator.pop(context, _pw.text);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: C.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.sheet)),
        ),
        padding: EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.lg + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(
              title: '设一个口令',
              action: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('取消', style: TextStyle(color: C.ink2)),
              ),
            ),
            Text(
              '这份备份用 AES-256 加密，只有拿对口令的人能打开。',
              style: T.body2,
            ),
            const SizedBox(height: S.md),
            _PasswordField(
              controller: _pw,
              label: '口令',
              obscure: _obscure,
              onToggleObscure: () => setState(() => _obscure = !_obscure),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: S.md),
            _PasswordField(
              controller: _again,
              label: '再输一遍',
              obscure: _obscure,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: S.sm),
              Text(_error!, style: T.caption.copyWith(color: C.over)),
            ],
            const SizedBox(height: S.md),
            // ★ 三条红线都在这块里。放在按钮上面，读不到就点不了下一步。
            Container(
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                color: C.bg2,
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我们不保存这个口令 —— 它只用来加密这一次导出的文件，'
                    '不写进 App 的任何地方。',
                    style: T.caption.copyWith(color: C.ink),
                  ),
                  const SizedBox(height: S.sm),
                  Text(
                    '所以：忘了口令就打不开这份文件，没有任何办法找回或重置。',
                    style: T.caption.copyWith(color: C.ink),
                  ),
                  const SizedBox(height: S.sm),
                  Text(
                    '不想记口令，可以改用「明文导出」—— 文件谁拿到谁能读，'
                    '适合只存在自己的电脑里。',
                    style: T.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: C.ink,
                  foregroundColor: C.onAccent,
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('加密导出'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnlockPasswordSheet extends StatefulWidget {
  const _UnlockPasswordSheet({this.fileName});

  final String? fileName;

  @override
  State<_UnlockPasswordSheet> createState() => _UnlockPasswordSheetState();
}

class _UnlockPasswordSheetState extends State<_UnlockPasswordSheet> {
  final _pw = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: C.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.sheet)),
        ),
        padding: EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.lg + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(
              title: '输入口令',
              action: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('取消', style: TextStyle(color: C.ink2)),
              ),
            ),
            if (widget.fileName != null) ...[
              Text(widget.fileName!, style: T.caption),
              const SizedBox(height: S.xs),
            ],
            Text(
              '这份备份是加密的，需要导出时设的那个口令。',
              style: T.body2,
            ),
            const SizedBox(height: S.md),
            _PasswordField(
              controller: _pw,
              label: '口令',
              obscure: _obscure,
              autofocus: true,
              onToggleObscure: () => setState(() => _obscure = !_obscure),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: S.md),
            // 忘口令的用户在这里，唯一有用的信息是「没办法，但你可以试试别的路」
            Text(
              '口令没有存在任何地方，忘了就打不开这份文件 —— '
              '如果还有明文备份，可以用它恢复。',
              style: T.caption,
            ),
            const SizedBox(height: S.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _pw.text),
                style: FilledButton.styleFrom(
                  backgroundColor: C.ink,
                  foregroundColor: C.onAccent,
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('打开'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 口令输入框：`TextField` 在这里出现两次，样式各写一遍就会有两次机会长歪。
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onSubmitted,
    this.onToggleObscure,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onToggleObscure;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      // 口令里不该有自动大写 / 自动纠错：它们会悄悄改掉用户记在纸上那串字符
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      keyboardType: TextInputType.visiblePassword,
      style: T.body,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: T.caption,
        filled: true,
        fillColor: C.bg2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: BorderSide.none,
        ),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                  color: C.ink3,
                ),
              ),
      ),
    );
  }
}
