import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../data/integrity.dart';
import '../design/hairline.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/restore_flow.dart';

/// 数据安全：自动快照的查看 / 恢复 / 清理。
///
/// 为什么要有这一页：1.4.1 的「清空全部数据」因为异常被吞掉 + 删除与重建不在
/// 一个事务里，出现过「点了没反应、数据还在、库里已经半残」的事故。事务修好
/// 之后还剩另一半 —— **单向操作没法回退**。「从备份恢复」一直有覆盖前留快照的
/// 兜底，「清空」却没有，快照也只能从恢复结果弹窗里看到路径、捞不回来。
///
/// 这一页把快照变成可操作的东西：看得见、能恢复、能删。清空和恢复都会在这里
/// 留一条，所以手滑之后有路可走。
class SafetyPage extends StatefulWidget {
  const SafetyPage({super.key});

  @override
  State<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<SafetyPage> {
  List<SnapshotInfo> _items = const [];
  bool _loading = true;
  bool _busy = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await BackupService.listSnapshots();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  /// 现在存一份。给「今天动了手，但不想先清空再恢复」的场景用。
  Future<void> _backupNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BackupService.writeSnapshot(reason: 'manual');
      await _load();
      if (mounted) showToast(context, '已存一份快照');
    } catch (e) {
      if (mounted) showToast(context, '存不了快照：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(SnapshotInfo info) async {
    if (_busy) return;
    final Map<String, Object?> payload;
    final BackupSummary summary;
    try {
      payload = await BackupService.readFile(info.path);
      summary = BackupService.summarize(payload);
    } on BackupException catch (e) {
      if (mounted) showToast(context, e.message);
      return;
    }
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final done = await runRestoreFlow(
        context,
        payload: payload,
        summary: summary,
        sourceLabel: '${info.reasonLabel} · ${info.timeLabel}',
      );
      if (!mounted) return;
      // 恢复本身也会留一份「恢复前」快照，列表要跟着刷新
      if (done) await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(SnapshotInfo info) async {
    try {
      await BackupService.share(info.path);
    } catch (e) {
      if (mounted) showToast(context, '分享失败：$e');
    }
  }

  Future<void> _delete(SnapshotInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这份快照？', style: T.section),
        content: Text(
          '${info.reasonLabel} · ${info.timeLabel}\n${info.contentLabel}',
          style: T.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: C.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: C.over)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BackupService.deleteSnapshot(info.path);
      await _load();
      if (mounted) showToast(context, '已删除');
    } on BackupException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  /// 数据体检：只读检查，发现问题后可以让用户主动点「重算余额」。
  ///
  /// 为什么放在这一页、而不是启动时自动跑：体检要读全表，放在启动路径上会
  /// 拖慢冷启动；而这一页本来就是「数据出事了来这儿」的入口。
  Future<void> _runCheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final report = await Integrity.check();
      if (!mounted) return;
      await _showReport(report);
    } catch (e) {
      if (mounted) showToast(context, '检查失败：$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showReport(IntegrityReport report) async {
    final fix = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          report.ok ? '数据正常' : '发现 ${report.issues.length} 项问题',
          style: T.section,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(report.summary, style: T.caption),
              if (!report.ok) const SizedBox(height: S.md),
              for (final issue in report.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.sm),
                  child: Text(
                    '${issue.kind.label}：${issue.detail}',
                    style: T.body2,
                  ),
                ),
              if (report.hasFixable) ...[
                const SizedBox(height: S.sm),
                const Text(
                  '「重算余额」按「期初 + 流水合计」把余额改回来，'
                  '不会动期初值（你手填的那个基准）。',
                  style: T.caption,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('关闭', style: TextStyle(color: C.ink2)),
          ),
          if (report.hasFixable)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重算余额', style: TextStyle(color: C.ink)),
            ),
        ],
      ),
    );
    if (fix != true) return;

    final fixed = await Integrity.recalcBalances();
    // 余额变了，内存里的账户副本还是旧的，首页/统计会继续显示错数字
    await Store.i.afterAccountChange();
    if (!mounted) return;
    showToast(context, fixed == 0 ? '没有需要修正的账户' : '已修正 $fixed 个账户的余额');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('数据安全'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const LineIcon('arrow_left', semanticLabel: '返回', size: 22, color: C.ink),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _backupNow,
            child: const Text(
              '现在备份',
              style: T.body2,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: C.ink4),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: S.xxl),
              children: [
                const SectionTitle('数据体检'),
                SectionCard(
                  // 列表卡：SettingRow 自带左右 16，卡片只留上下 8
                  padding: const EdgeInsets.symmetric(vertical: S.sm),
                  child: SettingRow(
                    icon: 'shield',
                    title: '检查数据完整性',
                    subtitle: _checking ? '正在检查…' : '核对余额、归属期、借贷与引用',
                    trailing: const LineIcon(
                      'chevron_right',
                      size: 20,
                      color: C.ink3,
                    ),
                    onTap: _checking ? null : _runCheck,
                  ),
                ),
                const SizedBox(height: S.md),
                const SectionTitle('自动快照'),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const LineIcon('shield', size: 20, color: C.ink2),
                          const SizedBox(width: S.md),
                          Text(
                            '清空、恢复之前自动留底',
                            style: T.body.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: S.sm),
                      const Text(
                        '只保留最近 3 份、最多 7 天。快照存在应用私有目录里，'
                        '卸载应用会一起清掉 —— 要长期保存请用「我的 → 备份全部数据」'
                        '导出到手机或网盘。',
                        style: T.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: S.sm),
                if (_items.isEmpty)
                  const EmptyHint(
                    icon: 'shield',
                    text: '还没有快照',
                    hint: '清空或恢复数据时会自动留一份；也可以点右上角「现在备份」',
                  )
                else
                  SectionCard(
                    // 列表卡：行间有分隔线，行自己带左右 16，卡片只留上下 8
                    padding: const EdgeInsets.symmetric(vertical: S.sm),
                    child: Column(
                      children: [
                        for (var i = 0; i < _items.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: hairlineOf(context),
                              color: C.line,
                              indent: 52,
                            ),
                          _SnapshotRow(
                            info: _items[i],
                            onRestore: _busy ? null : () => _restore(_items[i]),
                            onShare: () => _share(_items[i]),
                            onDelete: () => _delete(_items[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: S.md),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: S.lg),
                  child: Text(
                    '恢复是覆盖式的：会先把当前数据再存一份快照，然后整库替换。'
                    '所以「恢复错了」也还有退路。',
                    style: T.caption,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 一条快照：时间 + 来源 + 体积，右侧菜单（恢复 / 分享 / 删除）
class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    required this.info,
    required this.onRestore,
    required this.onShare,
    required this.onDelete,
  });

  final SnapshotInfo info;

  /// 为 null 表示正忙，整行菜单不可用
  final VoidCallback? onRestore;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final canRestore = info.readable && onRestore != null;
    return SettingRow(
      icon: 'shield',
      title: info.timeLabel,
      subtitle:
          '${info.reasonLabel} · ${info.contentLabel} · ${info.sizeLabel}',
      onTap: canRestore ? onRestore : null,
      trailing: PopupMenuButton<String>(
        icon: const LineIcon('more', semanticLabel: '更多', size: 20, color: C.ink3),
        padding: EdgeInsets.zero,
        onSelected: (v) {
          switch (v) {
            case 'restore':
              onRestore?.call();
            case 'share':
              onShare();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          if (canRestore)
            const PopupMenuItem(value: 'restore', child: Text('用它恢复')),
          const PopupMenuItem(value: 'share', child: Text('导出这一份')),
          const PopupMenuItem(
            value: 'delete',
            child: Text('删除', style: TextStyle(color: C.over)),
          ),
        ],
      ),
    );
  }
}
