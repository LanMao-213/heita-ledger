import 'package:flutter_test/flutter_test.dart';
import 'package:heita_ledger/core/failure.dart';
import 'package:heita_ledger/stores/shell_store.dart';
import 'package:heita_ledger/theme/palette.dart';

/// 外壳 Store：tab 同步、配色切换与落库、通知合并、启动标志。
void main() {
  group('tab', () {
    test('切到同一个 tab 不发通知（避免点一下抖一下）', () {
      final ShellStore store = ShellStore();
      int notified = 0;
      store.addListener(() => notified++);

      store.switchTab(ShellStore.tabDetail);

      expect(notified, 0);
      expect(store.tabIndex, ShellStore.tabDetail);
    });

    test('切到别的 tab → 1 次通知 + 值变更', () {
      final ShellStore store = ShellStore();
      int notified = 0;
      store.addListener(() => notified++);

      store.switchTab(ShellStore.tabPlan);

      expect(notified, 1);
      expect(store.tabIndex, ShellStore.tabPlan);
    });

    test('越界 tab 抛 ArgumentError，且不改状态', () {
      final ShellStore store = ShellStore();
      expect(() => store.switchTab(-1), throwsArgumentError);
      expect(() => store.switchTab(ShellStore.tabCount), throwsArgumentError);
      expect(store.tabIndex, ShellStore.tabDetail);
    });

    test('底栏 5 槽 ↔ 4 页的换算唯一且互逆', () {
      expect(ShellStore.barSlotOfTab(0), 0);
      expect(ShellStore.barSlotOfTab(1), 1);
      expect(ShellStore.barSlotOfTab(2), 3, reason: '中央浮钮占掉了槽位 2');
      expect(ShellStore.barSlotOfTab(3), 4);

      for (int tab = 0; tab < ShellStore.tabCount; tab++) {
        expect(ShellStore.tabOfBarSlot(ShellStore.barSlotOfTab(tab)), tab);
      }
      expect(ShellStore.tabOfBarSlot(2), isNull, reason: '槽位 2 是浮钮，不对应页面');
    });
  });

  group('配色', () {
    test('切到不同配色 → 1 次通知 + 落库回调收到 id', () async {
      final List<String> persisted = <String>[];
      final ShellStore store = ShellStore(
        persistPalette: (String id) async => persisted.add(id),
      );
      int notified = 0;
      store.addListener(() => notified++);

      store.setPalette(paletteAurora());
      await Future<void>.delayed(Duration.zero);

      expect(notified, 1);
      expect(store.palette.id, 'aurora');
      expect(persisted, <String>['aurora']);
    });

    test('切到同一套配色不发通知、不落库', () async {
      final List<String> persisted = <String>[];
      final ShellStore store = ShellStore(
        persistPalette: (String id) async => persisted.add(id),
      );
      int notified = 0;
      store.addListener(() => notified++);

      store.setPalette(paletteInk());
      await Future<void>.delayed(Duration.zero);

      expect(notified, 0);
      expect(persisted, isEmpty);
    });

    test('落库失败不影响本次切换（下次启动回落默认而已）', () async {
      final ShellStore store = ShellStore(
        persistPalette: (String id) async => throw StateError('磁盘满了'),
      );
      store.setPalette(paletteAurora());
      await Future<void>.delayed(Duration.zero);
      expect(store.palette.id, 'aurora');
    });

    test('setPaletteById 认不出脏值 → 回落 ink 且不抛', () {
      final ShellStore store = ShellStore();
      store.setPalette(paletteAurora());
      store.setPaletteById('midnight-blue');
      expect(store.palette.id, 'ink');
    });
  });

  group('通知合并', () {
    test('batchNotify 内多次改动只发 1 次（I12 的机制侧）', () {
      final ShellStore store = ShellStore();
      int notified = 0;
      store.addListener(() => notified++);

      store.batchNotify(() {
        store.switchTab(ShellStore.tabStats);
        store.setHapticsEnabled(false);
        store.switchTab(ShellStore.tabPlan);
      });

      expect(notified, 1);
      expect(store.tabIndex, ShellStore.tabPlan);
      expect(store.hapticsEnabled, isFalse);
    });

    test('batchNotifyAsync 跨 await 也只发 1 次（启动序列用）', () async {
      final ShellStore store = ShellStore();
      int notified = 0;
      store.addListener(() => notified++);

      await store.batchNotifyAsync<void>(() async {
        store.switchTab(1);
        await Future<void>.delayed(Duration.zero);
        store.switchTab(2);
        await Future<void>.delayed(Duration.zero);
        store.markReady();
      });

      expect(notified, 1);
      expect(store.ready, isTrue);
    });

    test('批处理体内抛异常也会把已发生的改动发出去（不丢通知）', () {
      final ShellStore store = ShellStore();
      int notified = 0;
      store.addListener(() => notified++);

      expect(
        () => store.batchNotify(() {
          store.switchTab(1);
          throw StateError('打桩');
        }),
        throwsStateError,
      );
      expect(notified, 1);
    });

    test('没有改动时 batchNotify 不发空通知', () {
      final ShellStore store = ShellStore();
      int notified = 0;
      store.addListener(() => notified++);
      store.batchNotify(() {});
      expect(notified, 0);
    });
  });

  group('启动标志', () {
    test('markReady → ready 为真、清空错误、1 次通知', () {
      final ShellStore store = ShellStore();
      int notified = 0;
      store.addListener(() => notified++);

      store.markReady();

      expect(store.ready, isTrue);
      expect(store.bootError, isNull);
      expect(notified, 1);
    });

    test('markReady 幂等：已经是 ready 再调不发通知', () {
      final ShellStore store = ShellStore();
      store.markReady();
      int notified = 0;
      store.addListener(() => notified++);

      store.markReady();
      expect(notified, 0);
    });

    test('failBoot → ready 保持 false、错误有值；clearBootError 后回到待启动', () {
      final ShellStore store = ShellStore();
      store.failBoot(const DbFailure('打不开'));

      expect(store.ready, isFalse);
      expect(store.bootError, isA<DbFailure>());

      store.clearBootError();
      expect(store.bootError, isNull);
    });

    test('applyBootFlags 按 id 定配色、按开关定触感，且只发 1 次', () {
      final ShellStore store = ShellStore();
      int notified = 0;
      store.addListener(() => notified++);

      store.applyBootFlags(hapticsEnabled: false, paletteId: 'aurora');

      expect(store.palette.id, 'aurora');
      expect(store.hapticsEnabled, isFalse);
      expect(notified, 1);
    });

    test('applyBootFlags 收到 null（老库没有这个键）→ 默认 ink + 触感开', () {
      final ShellStore store = ShellStore();
      store.applyBootFlags(hapticsEnabled: true, paletteId: null);
      expect(store.palette.id, 'ink');
      expect(store.hapticsEnabled, isTrue);
    });

    test('dispose 之后异步回来的通知不再发（不抛 "after dispose"）', () async {
      final ShellStore store = ShellStore();
      final Future<void> pending = store.batchNotifyAsync<void>(() async {
        store.switchTab(2);
        await Future<void>.delayed(Duration.zero);
      });
      store.dispose();
      await pending;
      expect(store.isDisposed, isTrue);
    });
  });
}
