import 'package:flutter/material.dart';

import '../../core/failure.dart';
import '../../core/local_date.dart';
import '../../core/period.dart';
import '../../data/db/db.dart';
import '../../data/db/migrations.dart';
import '../../data/models/setting.dart';
import '../../data/repo/repo.dart';
import '../../stores/book_store.dart';
import '../../stores/catalog_store.dart';
import '../../stores/plan_store.dart';
import '../../stores/shell_store.dart';
import '../shell/home_shell.dart';
import 'boot_error.dart';
import 'splash.dart';

/// 启动序列的可注入签名。测试用它替换掉真实 IO。
typedef BootRunner = Future<void> Function(ShellStore shell);

/// 启动结果：给首帧后的「合并 toast」用（§4-⑦ 第 11 步）。
class BootOutcome {
  const BootOutcome({this.recurringAdded = 0, this.catsUpgraded = false});

  /// 本次补记了几笔周期账单。
  final int recurringAdded;

  /// 分类是否刚从旧结构升到两级（新库首次安装恒为 false）。
  final bool catsUpgraded;

  bool get isEmpty => recurringAdded == 0 && !catsUpgraded;

  /// 两者用「；」拼成**一条** toast（连弹两条会被前一条盖掉）。
  String get message {
    final List<String> parts = <String>[
      if (recurringAdded > 0) '已补记 $recurringAdded 笔周期账单',
      if (catsUpgraded) '分类已升级为两级',
    ];
    return parts.join('；');
  }
}

/// 默认启动序列（只有 ShellStore 的极简装配，如测试）。
Future<void> defaultBootRunner(ShellStore shell) => BootSequence.run(shell);

/// 启动序列（架构设计 §4-⑦，**12 步严格顺序**）。
///
/// `ShellStore.ready` 为真时整段跳过 —— 热重载 / 二次挂载都不会重开库。
/// 全程包在一个 `batchNotifyAsync` 里 → **启动只重建 1 次**。
class BootSequence {
  const BootSequence._();

  static Future<BootOutcome> run(
    ShellStore shell, {
    BookStore? book,
    CatalogStore? catalog,
    PlanStore? plan,
  }) {
    return shell.batchNotifyAsync<BootOutcome>(() async {
      // ① 打开库（onConfigure 开 PRAGMA foreign_keys）。失败 → DbFailure，整页失败。
      await Db.open();

      // ② 库版本比包新 → onDowngrade 抛 DbDowngradeException（文案已写好
      //    「不要卸载重装」）。这一步没有额外代码，靠 Db.open 抛。

      // ③ 补 period_start 为空的行。v1 里该列 NOT NULL，正常库恒为 0。
      await backfillMissingPeriods(await Db.database());

      // ④ 读用户偏好：触感（缺省开）、一次性提示标记。
      final String? hapticsRaw = await Db.readSetting(SettingKeys.uiHaptics);

      // ⑤ 配色必须在首帧之前定好，否则会「先白屏再变色」。
      final String? paletteRaw = await Db.readSetting(SettingKeys.themePalette);
      shell.applyBootFlags(
        hapticsEnabled: hapticsRaw != '0',
        paletteId: paletteRaw,
      );

      // ⑥ 取当前账本（含自愈：指针指错 → 回第一本；一本都没有 → 建一本并播种）。
      final int ledgerId = await Db.ensureCurrentLedgerId();

      // ⑦ 账单日（1–31，非法自愈）→ 游标回到「今天所在期」。
      final int cycleStartDay = await _ensureCycleStartDay();
      final Period cycle = Period.cycleRange(LocalDate.today(), cycleStartDay);
      await book?.bind(ledgerId: ledgerId, cycleStartDay: cycleStartDay);
      await plan?.bind(ledgerId: ledgerId, period: cycle);

      // ⑧ 周期账单补记（闸一按 ledgerId 判、闸二复用在飞 Future、闸三物理唯一）。
      final int added = await plan?.catchUp() ?? 0;

      // ⑨ 分类升级提示判定：新库首次安装恒为 false，不提示。
      const bool catsUpgraded = false;

      // ⑩ 一次查全 + 重查当期 + 重查计划；**统计只打脏标记，不在启动路径算**。
      await catalog?.loadCatalog(ledgerId);
      await book?.reloadCycle();
      await plan?.reload();
      plan?.markStatsStale();

      // ⑪ 就绪 + 1 次通知（合并 toast 由调用方在首帧后弹）。
      shell.markReady();

      // ⑫ 全程在 batchNotifyAsync 内 → 只重建 1 次。
      return BootOutcome(recurringAdded: added, catsUpgraded: catsUpgraded);
    });
  }

  /// 账单日自愈：缺失 / 非数字 / 越界都回落到 1 并写回。
  ///
  /// 不这么做的后果：别处写进一个 `'0'` 或 `'99'`，归属期会算出一个恒空或
  /// 恒跨月的区间，明细页看起来像「数据全丢了」。
  static Future<int> _ensureCycleStartDay() async {
    final String? raw = await Db.readSetting(SettingKeys.cycleStartDay);
    final int? parsed = raw == null ? null : int.tryParse(raw);
    if (parsed != null && parsed >= 1 && parsed <= 31) return parsed;
    await Db.writeSetting(SettingKeys.cycleStartDay, '1');
    return 1;
  }

  /// 重建默认库之后重置四层状态（清空 / 恢复路径用）。
  static Future<void> reloadAfterWipe({
    required ShellStore shell,
    required BookStore book,
    required CatalogStore catalog,
    required PlanStore plan,
  }) async {
    plan.resetScanCursor();
    await shell.batchNotifyAsync<void>(() async {
      final int ledgerId = await Repo.ledger.currentId();
      final int cycleStartDay = await Repo.setting.cycleStartDay();
      final Period cycle = Period.cycleRange(LocalDate.today(), cycleStartDay);
      await book.bind(ledgerId: ledgerId, cycleStartDay: cycleStartDay);
      await plan.bind(ledgerId: ledgerId, period: cycle);
      await catalog.loadCatalog(ledgerId);
      await book.reloadCycle();
      await plan.reload();
      plan.markStatsStale();
      shell.notifyListeners();
    });
  }
}

/// 启动闸：开屏 → 就绪后进壳；失败 → 失败页（三个出口）。
class BootGate extends StatefulWidget {
  const BootGate({super.key, required this.shell, this.runner});

  final ShellStore shell;

  /// 覆盖启动序列。测试传「只 markReady」的假实现，就不需要 SQLite。
  final BootRunner? runner;

  @override
  State<BootGate> createState() => _BootGateState();
}

enum _BootPhase { running, failed, done }

class _BootGateState extends State<BootGate> {
  _BootPhase _phase = _BootPhase.running;

  @override
  void initState() {
    super.initState();
    if (widget.shell.ready) {
      _phase = _BootPhase.done;
      return;
    }
    // 必须等首帧之后才跑序列：第 ⑤ 步会改 Store（定配色），在 initState 里
    // 同步改会在 build 期间触发通知 → 框架断言。顺带满足「首帧只画开屏」。
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    final BootRunner runner = widget.runner ?? defaultBootRunner;
    try {
      await runner(widget.shell);
    } catch (error) {
      widget.shell.failBoot(error);
    }
    if (!mounted) return;
    setState(() {
      _phase = widget.shell.ready ? _BootPhase.done : _BootPhase.failed;
    });
  }

  void _retry() {
    widget.shell.clearBootError();
    setState(() => _phase = _BootPhase.running);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _BootPhase.running:
        return const SplashScreen();
      case _BootPhase.failed:
        return BootErrorView(
          error: widget.shell.bootError ?? const DbFailure('启动失败（原因未知）'),
          onRetry: _retry,
        );
      case _BootPhase.done:
        return const HomeShell();
    }
  }
}
