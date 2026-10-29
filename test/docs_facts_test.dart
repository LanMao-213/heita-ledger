// 文档事实的机器守卫：README 里那些「手填的数字」必须和仓库真实情况一致。
//
// ## 为什么需要这条
//
// README 的「测试文件数」已经漂过两次：1.5.2 那轮从 78 改到 83（实际是 84），
// 1.6.0 这轮又从 84 改到 91。两次都不是有人「忘了改」，而是**一个靠人记的数字，
// 注定会在下一次加测试时再次过期**。同理，README 开头的「当前版本」停在了
// 1.4.6 却没人发现，也是同一个缺口。
//
// 所以这里的取舍是：
//   - **文件数**交给机器断言 —— 数一下目录就知道，改错了这条会红，并且直接告诉
//     你该写成什么；
//   - **测试条数**从 README 里删掉 —— 它无法被机器断言（要知道总数就得跑一遍
//     全部测试，而这条用例本身就在其中，会自指）。一个断言不了的数字，
//     写一次就要靠人记一辈子，所以改用「全部测试全绿」这类恒定成立的表述。
//
// 与 `version_consistency_test.dart` 的分工：那条管「版本号三处一致」
// （pubspec / kAppVersion / CHANGELOG），这条管「README 与仓库实体一致」。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// pubspec 的 `version:` 整行，形如 `1.6.0+26`
String _pubspecVersion() {
  final text = File('pubspec.yaml').readAsStringSync();
  final m = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(text);
  expect(m, isNotNull, reason: 'pubspec.yaml 里找不到 version: 行');
  return m!.group(1)!;
}

void main() {
  final readme = File('README.md').readAsStringSync();

  group('README 与仓库实体一致', () {
    test('「N 个测试文件」等于 test/ 下的实际 dart 文件数', () {
      final actual = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .length;

      final m = RegExp(r'(\d+)\s*个测试文件').firstMatch(readme);
      expect(
        m,
        isNotNull,
        reason: 'README 里找不到「N 个测试文件」这句话。'
            '这句话是规模事实的一部分，删掉它就没人能核对 test/ 到底有多少个文件',
      );
      expect(
        m!.group(1),
        '$actual',
        reason: 'README 写的是 ${m.group(1)} 个测试文件，test/ 下实际有 $actual 个。'
            '请把 README 改成「$actual 个测试文件」',
      );
    });

    test('README 开头声明的版本号等于 pubspec 的版本', () {
      final full = _pubspecVersion();
      expect(
        readme.contains(full),
        isTrue,
        reason: 'README 里找不到当前版本 "$full"。'
            'README 是唯一对外入口，它停在上一个版本会让接手的人按错前提动手 —— '
            '1.4.6 那次就是这么发生的',
      );
    });

    test('README 不再声明无法被机器断言的「N 条测试」', () {
      // 允许出现「条数」这个词，但不允许出现「123 条测试」这种具体数字：
      // 具体数字加一条用例就会过期，且没有任何门禁能发现。
      final m = RegExp(r'\d+\s*条测试').firstMatch(readme);
      expect(
        m,
        isNull,
        reason: 'README 里出现了「${m?.group(0)}」。'
            '测试条数无法被机器断言（数总数就得跑一遍全部用例，会自指），'
            '写死一个数字注定过期。请改用「全部测试全绿」这类表述，条数以 CI 输出为准',
      );
    });
  });
}
