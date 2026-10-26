import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 结构护栏：把「分层方向」「门面只做转发」「Store 没有公开可变字段」
/// 这三条**已经靠约定维持了很久**的规则变成会红的测试。
///
/// ## 为什么值得专门写一组读源码的测试
///
/// 这三条都不是运行时行为，普通单测碰不到：
/// - 有人给 `lib/data` 加一行 `import 'package:flutter/material.dart'`，
///   编译通过、测试全绿，但数据层从此离不开 UI，纯 Dart 复用就废了；
/// - 有人嫌转发麻烦，直接把实现写回 `repo.dart` 的门面里，
///   文件会重新长回一千八百行，而且**没有任何测试会红**；
/// - 有人图省事在 `Store` 上加一个公开可变字段，页面就能直接改投影，
///   投影与库分叉的入口又打开了。
///
/// 探针式测试（读源码、按行匹配）确实比行为测试脆，所以这里刻意只匹配
/// **声明形状**，不匹配具体内容：改方法名、改实现都不会误报。

String _read(String path) => File(path).readAsStringSync();

List<String> _dartFilesUnder(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.path.replaceAll(r'\', '/'))
    .toList();

void main() {
  group('分层方向', () {
    test('lib/data 不依赖 Flutter，也不反向依赖 design 层', () {
      final offenders = <String>[];
      for (final path in _dartFilesUnder('lib/data')) {
        final src = _read(path);
        if (src.contains('package:flutter/')) offenders.add('$path → flutter');
        if (RegExp(r"import\s+'[^']*design/").hasMatch(src)) {
          offenders.add('$path → design');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '数据层必须能脱离 UI 独立测试：${offenders.join('、')}',
      );
    });
  });

  group('门面只做转发', () {
    /// 门面文件里每个 `static` 方法都必须是转发，不能藏实现。
    ///
    /// 按**声明块**判断而不是按行：签名跨行（命名参数一行一个）是常态，
    /// 按行看会把合法的多行转发误判成实现。
    ///
    /// 判据两条，都很窄：
    /// 1. 声明块里必须有 `=> <implPrefix>`（真的转发出去了）；
    /// 2. 声明块里不能有块体（`) {` / `) async {`）—— 那是实现的样子。
    ///
    /// 所以「把实现搬回门面」会立刻变红，而改签名、改注释不会误报。
    void expectFacadeOnly(String path, String implPrefix) {
      final src = _read(path);
      final bad = <String>[];
      // 以 `  static ` 切块，每块截到第一条语句结束（`;\n`）
      for (final chunk in src.split(RegExp(r'^  static ', multiLine: true)).skip(1)) {
        if (chunk.startsWith('const ')) continue;
        final end = chunk.indexOf(';\n');
        final decl = end >= 0 ? chunk.substring(0, end) : chunk;
        final head = 'static ${decl.split('\n').first}';
        final forwards = decl.contains('=> $implPrefix');
        final hasBlockBody = RegExp(r'\)\s*(async\s*)?\{').hasMatch(decl);
        if (!forwards || hasBlockBody) bad.add(head);
      }
      expect(
        bad,
        isEmpty,
        reason: '$path 的门面只允许转发，实现在对应分部文件里：'
            '${bad.take(5).join(' | ')}',
      );
    }

    test('Repo 门面只做转发（实现在 lib/data/repo/*.dart）', () {
      expectFacadeOnly('lib/data/repo.dart', '_repo');
    });

    test('BillCsv 门面只做转发（实现在 lib/data/bill/*.dart）', () {
      expectFacadeOnly('lib/data/bill_csv.dart', '_');
    });
  });

  group('库入口只做装配', () {
    /// `models.dart` 是**库入口**：只放 import、`part` 指令和库私有 helper。
    /// 实体与枚举必须在 `models/*.dart` 里。
    ///
    /// 不守这条的话，下次加实体最顺手的位置就是 `models.dart` 末尾，
    /// 一年后它又会长回一千行 —— 这轮拆分就白做了。
    test('models.dart 不含公开顶层声明', () {
      final offenders = <String>[];
      for (final line in _read('lib/data/models.dart').split('\n')) {
        if (RegExp(r'^(class|enum|typedef|extension|abstract) ').hasMatch(line)) {
          offenders.add(line.trim());
        }
        // 公开的顶层函数也不行（私有 `_x` 允许：库里公用的归一化 helper）
        final fn = RegExp(r'^[A-Za-z][\w<>?, ]*\s([a-zA-Z]\w*)\s*\(')
            .firstMatch(line);
        if (fn != null && !line.trimLeft().startsWith('//')) {
          offenders.add(line.trim());
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '实体请放进 lib/data/models/<域>.dart 并在 models.dart 里 part：'
            '${offenders.take(5).join(' | ')}',
      );
    });

    test('models.dart 声明的 part 与目录里的文件一致', () {
      final src = _read('lib/data/models.dart');
      final declared = RegExp(r"part 'models/([a-z_]+)\.dart';")
          .allMatches(src)
          .map((m) => '${m.group(1)}.dart')
          .toSet();
      final onDisk = Directory('lib/data/models')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.dart'))
          .toSet();
      expect(declared, isNotEmpty);
      expect(
        onDisk.difference(declared),
        isEmpty,
        reason: '目录里有文件没被 part，永远不会被编译',
      );
      expect(
        declared.difference(onDisk),
        isEmpty,
        reason: 'part 指向了不存在的文件',
      );
    });
  });

  group('Store 的可变状态', () {
    test('没有公开可变字段（写入只能走 Store 的方法）', () {
      final lines = _read('lib/store.dart').split('\n');
      // 形如 `  List<Txn> txns = [];`：缩进 2、以 `= ` 赋值、不是 late/static/私有
      final fieldDecl = RegExp(r'^  [A-Za-z][A-Za-z0-9<>?,\s]*\s([a-z][A-Za-z0-9_]*) = ');
      final offenders = <String>[];
      for (final line in lines) {
        final m = fieldDecl.firstMatch(line);
        if (m == null) continue;
        if (line.contains(' late ') || line.contains('static')) continue;
        offenders.add(line.trim());
      }
      expect(
        offenders,
        isEmpty,
        reason: '公开可变字段能让页面直接改投影、与库分叉；'
            '只读投影请加在 lib/store/state.dart：${offenders.take(5).join(' | ')}',
      );
    });

    test('只读投影与私有字段一一对应（没有指向空气的 getter）', () {
      final store = _read('lib/store.dart');
      final state = _read('lib/store/state.dart');
      // state.dart 里每个 `X get name => _name;` 都要能在 store.dart 找到 `_name`
      final getters = RegExp(r'get\s+([A-Za-z_]\w*)\s*=>\s*_([A-Za-z0-9_]+)\s*;')
          .allMatches(state);
      expect(getters, isNotEmpty, reason: 'state.dart 应当有只读投影');
      for (final g in getters) {
        final backing = '_${g.group(2)}';
        expect(
          store.contains(backing),
          isTrue,
          reason: 'getter ${g.group(1)} 指向的 $backing 在 store.dart 里不存在',
        );
      }
    });
  });
}
