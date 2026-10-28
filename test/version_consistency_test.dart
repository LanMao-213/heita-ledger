// 版本号一致性的守卫：pubspec / kAppVersion / CHANGELOG 三处必须说同一件事。
//
// 为什么需要这条：这三处不同步**不会有任何编译错误**，只会在用户眼前露馅 ——
// `pubspec.yaml` 的 `version:` 决定包内 versionName/versionCode，
// `lib/app.dart` 的 `kAppVersion` 决定「我的」页底部显示的那一行，
// 两份不一样时，安装包详情写着 1.5.1、App 里显示 1.5.0。
//
// 此前唯一的检查在 `tools/verify_apk.py` 里，而它要**手工打一个 release 包**
// 才跑得到（CI 没有签名密钥，打不了 release 包）。于是这类错误一路溜进过 main。
// 现在把同一件事挪进 `flutter test`：CI 每次 push / PR 都会跑，成本几乎为零。
//
// 同一份道理也适用于 CHANGELOG：发版那一版必须有一行写着完整版本号
// （`1.5.1+25`），否则「版本涨了、日志没写」照样能合进 main —— README 那次
// 停在 1.4.6 却没人发现，就是这个缺口的另一种形态。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// pubspec 的 `version: x.y.z+N` 整行
String _pubspecVersionLine() {
  final text = File('pubspec.yaml').readAsStringSync();
  final m = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(text);
  expect(m, isNotNull, reason: 'pubspec.yaml 里找不到 version: 行');
  return m!.group(1)!;
}

void main() {
  group('版本号一致性', () {
    test('pubspec 的版本号是 x.y.z+N 形态', () {
      final v = _pubspecVersionLine();
      final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$').firstMatch(v);
      expect(
        m,
        isNotNull,
        reason: '版本号 "$v" 不是 x.y.z+N 形态。'
            '`+N` 是构建号，Android 靠它判断能否覆盖升级，缺了会一律当作 0',
      );
      expect(
        int.parse(m!.group(4)!),
        greaterThan(0),
        reason: '构建号必须 ≥ 1：Android 里 versionCode 0 会被视为无效',
      );
    });

    test('kAppVersion 与 pubspec 的版本名一致（不含构建号）', () {
      final pubspecName = _pubspecVersionLine().split('+').first;
      final appDart = File('lib/app.dart').readAsStringSync();
      final m = RegExp(
        r"kAppVersion\s*=\s*'([^']+)'",
      ).firstMatch(appDart);
      expect(m, isNotNull, reason: 'lib/app.dart 里找不到 kAppVersion');

      final appVersion = m!.group(1)!;
      expect(
        appVersion,
        isNot(contains('+')),
        reason: 'kAppVersion 只放版本名，"我的" 页不显示构建号',
      );
      expect(
        appVersion,
        pubspecName,
        reason: '两处说的不是同一个版本。改版本号要同时改 '
            'pubspec.yaml 的 `version:` 与 lib/app.dart 的 `kAppVersion`',
      );
    });

    test('CHANGELOG 里有当前完整版本号（x.y.z+N）', () {
      final full = _pubspecVersionLine();
      final changelog = File('CHANGELOG.md').readAsStringSync();
      expect(
        changelog.contains(full),
        isTrue,
        reason: 'CHANGELOG.md 里找不到 "$full"。'
            '版本索引表那一行应写成 `| **$full** | 日期 | 标签 | 签名 | … |`，'
            '否则就会出现"版本涨了、日志没写"',
      );
    });
  });
}
