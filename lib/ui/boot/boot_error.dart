import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/failure.dart';
import '../../data/db/db.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../widgets/toast.dart';

/// 启动失败页（M01-F07）。
///
/// ★ 这是必须修掉的原版缺陷（盘点 §6.4-3）：原版只有一个白屏 + 异常文本，
/// **用户没有任何出口** —— 既不能重试，也拿不到库文件，只能卸载重装（卸载会
/// 清空应用私有目录，账目全丢）。所以这一页固定提供三个出口：
///
/// 1. **重试** —— 很多启动失败是暂时的（存储忙、权限、别的进程占着库）。
/// 2. **导出数据库文件** —— 把 `.db` 复制到临时目录再走系统分享，
///    用户可以先存到网盘/发给自己，再考虑重装。
/// 3. **显示数据库路径** —— 排查和「手动取文件」都要它，路径用等宽字体显示。
///
/// 失败页本身也要能看：不显示栈、不显示英文异常名，只给一句中文 + 开发者细节的折叠区。
class BootErrorView extends StatefulWidget {
  const BootErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  /// 启动过程中抛出的异常（`AppFailure` 会翻译成中文，其余给通用文案）。
  final Object error;

  /// 点「重试」：清掉错误态并重跑启动序列。
  final VoidCallback onRetry;

  @override
  State<BootErrorView> createState() => _BootErrorViewState();
}

class _BootErrorViewState extends State<BootErrorView> {
  bool _showPath = false;
  bool _showDetail = false;
  bool _exporting = false;

  Future<void> _exportDatabase() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final String path = Db.filePath;
      if (path.isEmpty) {
        showToast(context, '数据库文件还没创建出来，暂时没有可导出的内容。', error: true);
        return;
      }
      final File source = File(path);
      if (!source.existsSync()) {
        showToast(context, '找不到数据库文件，可能是存储权限或目录已被清理。', error: true);
        return;
      }
      final Directory tempDir = await getTemporaryDirectory();
      final String stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final File copy = File(p.join(tempDir.path, 'heita-ledger-$stamp.db'));
      await source.copy(copy.path);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(copy.path)],
          subject: '黑塔账本数据库文件',
          text: '黑塔账本导出的数据库文件（未加密，请自行保管）。',
        ),
      );
    } catch (error) {
      if (mounted) {
        showToast(context, '导出失败：${detailOf(error)}', error: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette pal = context.pal;
    final String path = Db.filePath;

    // 用 Material 而不是 ColoredBox：这一页里有 InkWell（「技术细节」折叠），
    // InkWell 必须有一个 Material 祖先，否则直接断言失败。
    return Material(
      color: pal.bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.page, S.xxxl, S.page, S.xxl),
          children: <Widget>[
            Icon(Icons.error_outline, size: 40, color: pal.over),
            const SizedBox(height: S.lg),
            Text(
              '账本没能打开',
              style: Ts.title.copyWith(color: pal.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: S.sm),
            Text(
              userMessageOf(widget.error),
              style: Ts.body2.copyWith(color: pal.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: S.xxl),
            FilledButton(
              key: const ValueKey<String>('boot-retry'),
              onPressed: widget.onRetry,
              child: const Text('重试'),
            ),
            const SizedBox(height: S.md),
            OutlinedButton(
              key: const ValueKey<String>('boot-export-db'),
              onPressed: _exporting ? null : _exportDatabase,
              child: Text(_exporting ? '正在导出…' : '导出数据库文件'),
            ),
            const SizedBox(height: S.md),
            OutlinedButton(
              key: const ValueKey<String>('boot-show-path'),
              onPressed: () => setState(() => _showPath = !_showPath),
              child: Text(_showPath ? '收起数据库路径' : '显示数据库路径'),
            ),
            if (_showPath) ...<Widget>[
              const SizedBox(height: S.md),
              Container(
                padding: const EdgeInsets.all(S.md),
                decoration: BoxDecoration(
                  color: pal.surfaceSunk,
                  borderRadius: R.rMd,
                  border: Border.all(color: pal.line),
                ),
                child: SelectableText(
                  path.isEmpty ? '（数据库还没有打开，路径未知）' : path,
                  style: Ts.caption.copyWith(
                    color: pal.ink2,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: S.xxl),
            // 开发者细节默认折叠：用户不需要看，但排查时必须拿得到
            InkWell(
              onTap: () => setState(() => _showDetail = !_showDetail),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: S.sm),
                child: Text(
                  _showDetail ? '收起技术细节' : '技术细节',
                  style: Ts.caption.copyWith(color: pal.ink3),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (_showDetail)
              Container(
                padding: const EdgeInsets.all(S.md),
                decoration: BoxDecoration(
                  color: pal.surfaceSunk,
                  borderRadius: R.rMd,
                  border: Border.all(color: pal.line),
                ),
                child: SelectableText(
                  detailOf(widget.error),
                  style: Ts.caption.copyWith(color: pal.ink2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
