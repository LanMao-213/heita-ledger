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

  group('备份的分层边界', () {
    /// 「快照永远明文、只有用户主动导出才加密」这条口径，必须**在 import 图上**
    /// 成立，而不是靠调用方自觉。
    ///
    /// 自觉型口径的破法很具体：某天有人想「顺便把快照也加密吧」，他会在
    /// `snapshot.dart` 里加一个 `password` 参数，然后在调用链上补参数 ——
    /// 三步都通得过 code review，因为每一步单看都合理。等发现「用户忘了口令
    /// 就再也捞不回兜底」时，已经发版了。
    ///
    /// 所以这里两件事一起守：
    ///   1. `snapshot.dart` 里不许出现 `password`，也不许 import 加密件；
    ///   2. `payload.dart`（内容层）同样不许 —— 那一层拿不到口令，
    ///      就没有「顺手加密一下」的机会。
    ///
    /// `plain_file.dart` 也一并钉住：它是「明文容器」，不认识加密才对。
    test('快照与 payload 层拿不到口令，也看不见加密件', () {
      const guarded = [
        'lib/data/backup/payload.dart',
        'lib/data/backup/snapshot.dart',
        'lib/data/backup/plain_file.dart',
      ];
      final offenders = <String>[];
      // 只看**代码行**：注释里点名这条规则是必须的（否则下一个人不知道为什么
      // 不能这么写），把注释也算进去就变成了「解释规则的人被规则罚」。
      bool isComment(String line) {
        final t = line.trimLeft();
        return t.startsWith('//') || t.startsWith('/*') || t.startsWith('*');
      }

      for (final path in guarded) {
        final lines = _read(path).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (isComment(line)) continue;
          // 大小写不敏感：`password` / `Password` / `PASSWORD` 都算
          if (RegExp(r'password', caseSensitive: false).hasMatch(line)) {
            offenders.add('$path:${i + 1} 出现口令：${line.trim()}');
          }
          if (RegExp(r'sealed_file|SealedBackupFile').hasMatch(line)) {
            offenders.add('$path:${i + 1} 碰到加密件：${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '快照与 payload 必须永远明文、永远不需要口令：\n'
            '${offenders.join('\n')}\n'
            '加密只发生在 lib/data/backup/sealed_file.dart，只由用户点「加密导出」触发。',
      );
    });

    test('依赖方向：加密件可以看明文件，反过来不行', () {
      // sealed_file → plain_file（decodeAny 要判断「这份是不是明文的」）是设计；
      // plain_file → sealed_file 才是错的方向。这条断言看着像废话，但它把方向
      // 写进了测试 —— 下次有人想「在 plain_file 里顺便认一下加密文件」时会先看到这里。
      final sealed = _read('lib/data/backup/sealed_file.dart');
      expect(
        RegExp(r"import 'plain_file\.dart';").hasMatch(sealed),
        isTrue,
        reason: '加密容器需要判型（明文 / 加密），这个方向是允许的',
      );
      expect(
        RegExp(r"import '[^']*sealed_file\.dart';")
            .hasMatch(_read('lib/data/backup/plain_file.dart')),
        isFalse,
      );
    });
  });

  group('record_sheet 的分部边界', () {
    /// 「记一笔」拆成三份：门面 + 状态机、行为方法、展示型组件。
    ///
    /// 拆的理由写在三个文件的注释头里。这里守的是**拆完之后又长回去**：
    /// 下次要加一个展示型 widget，最顺手的位置是主文件末尾；要加一个动作
    /// 方法，最顺手的是塞回状态类。这两种「顺手」都不会让任何行为测试变红，
    /// 半年后这个文件就重新变回一千六百行。
    const facade = 'lib/widgets/record_sheet.dart';

    test('主文件只放状态机与布局，展示型组件在 rows.dart、行为方法在 actions.dart', () {
      // 允许的顶层声明，只有这三个
      const allowed = {
        'class RecordOutcome {',
        'class RecordSheet extends StatefulWidget {',
        'class _RecordSheetState extends State<RecordSheet> {',
      };
      final decls = _read(facade)
          .split('\n')
          .map((l) => l.trimRight())
          .where((l) => l.startsWith('class ') || l.startsWith('enum '))
          .toSet();
      expect(
        decls.difference(allowed),
        isEmpty,
        reason: '新的类/枚举请放进 record_sheet/ 下的分部：'
            '${decls.difference(allowed).join(' | ')}',
      );
      expect(
        allowed.difference(decls),
        isEmpty,
        reason: '主文件少了预期声明（被改名或搬走了？改完请同步这条守卫）',
      );
    });

    test('行为方法只经 _rebuild 触发重建（extension 调不了 setState）', () {
      final src = _read('lib/widgets/record_sheet/actions.dart');
      expect(
        src.contains('setState('),
        isFalse,
        reason: 'extension 不是 State 子类，setState 是 @protected；'
            '请改用 _rebuild(...)，它在状态类里只做转发',
      );
    });

    test('主文件的 part 声明与 record_sheet/ 目录一致', () {
      final declared = RegExp(r"part 'record_sheet/([a-z_]+)\.dart';")
          .allMatches(_read(facade))
          .map((m) => '${m.group(1)}.dart')
          .toSet();
      final onDisk = Directory('lib/widgets/record_sheet')
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

    /// 布局计算必须是**纯计算**：能脱离 widget 树、脱离 pumpWidget 被推到任意
    /// 精度断言。
    ///
    /// `record_sheet/layout.dart` 是 part，编译器管不了它的 import（part 继承
    /// 主文件的 import），所以这里用源码探针替编译器守：出现任何一个 Flutter
    /// 类型就红。
    ///
    /// 为什么值得单独立一条：这条算式是「面板顶边抽搐」那个 bug 的全部答案
    /// （恒等式见文件头）。它一旦长回 widget 树里，就再也测不出「1dp 的跳」——
    /// 只能靠真机盯屏。
    test('layout.dart 是纯计算：不碰 Flutter 类型，且 ≤ 300 行', () {
      const layout = 'lib/widgets/record_sheet/layout.dart';
      final src = _read(layout);

      final flutterApi = RegExp(
        r'\b(Widget|BuildContext|Color|Colors|MediaQuery|EdgeInsets|SizedBox|'
        r'Container|Column|Row|Stack|Alignment|BoxDecoration|TextStyle|'
        r'State|StatefulWidget|StatelessWidget|Theme|Text)\b',
      );
      final hits = <String>[];
      for (final line in src.split('\n')) {
        // 注释里点名 Flutter 是允许的：那是解释，不是依赖
        final code = line.trimLeft();
        if (code.startsWith('//')) continue;
        final m = flutterApi.firstMatch(code);
        if (m != null) hits.add('${m.group(1)} ← ${code.trim()}');
      }
      expect(
        hits,
        isEmpty,
        reason: '布局计算必须是纯函数（不 pumpWidget 就能测）：${hits.take(5).join(' | ')}',
      );
      expect(
        src.contains('package:flutter/'),
        isFalse,
        reason: 'part 不该有 import，出现了说明有人把它改成了独立文件',
      );

      // 行数预算只对新分部生效：rows.dart（818 行）/ actions.dart（317 行）是
      // #10 挂账的历史文件，等那次拆分一起处理，不在这条守卫的射程内。
      final lines = src.split('\n').length;
      expect(
        lines,
        lessThanOrEqualTo(300),
        reason: '$layout 已经 $lines 行 —— 纯算式长到这个量级说明它在做别的事',
      );
    });
  });
}
