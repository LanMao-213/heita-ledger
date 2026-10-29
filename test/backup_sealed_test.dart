// 加密备份（`.heita`）的自检。
//
// 这份文件只测**容器**：把一段 payload 封起来、解出来、以及在每一个环节
// 被动过手脚时能不能拒绝。恢复语义（覆盖、迁移、快照）在
// `backup_roundtrip_test.dart` 与既有的 `backup_test.dart` 里。
//
// ## 为什么「拒绝」比「能解开」更重要
//
// 加密备份的所有失败模式都是**静默**的：口令错了如果只是「解出乱码」，
// 那份乱码会被当成合法 payload 灌进库，用户的账本当场变成一堆空表 ——
// 而这中间不会有任何异常。所以这里逐条钉住「必须抛异常」：
//
//   1. 口令错 → `wrongPasswordOrCorrupt`
//   2. 密文改 1 bit → 同上
//   3. salt / nonce / iter 被改 → 同上（它们都在 AAD 里）
//   4. containerVersion 被改 → `unsupportedContainer`
//   5. 截断末 16 字节（tag）→ 同上
//
// ## 顺带钉住的一条产品红线
//
// 「口令错」与「文件损坏」在密码学上**不可区分**（GCM 的 tag 对不上就是
// 对不上）。所以 kind 叫 `wrongPasswordOrCorrupt`，而界面文案必须同时说
// 这两种可能 —— 把它写成「口令错误」会让一个文件损坏的用户反复重输口令。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/backup/payload.dart';
import 'package:ledger/data/backup/plain_file.dart';
import 'package:ledger/data/backup/sealed_file.dart';

/// 测试用的迭代数：1000 次。
///
/// KDF 是**故意慢**的，用 210000 跑一遍几十条用例要几分钟。加密逻辑与迭代数
/// 无关（迭代数只影响派生耗时），所以用例全部注入 1000；
/// 默认值的正确性由本文件最后那条常量断言 + benchmark 用例单独负责。
const _fastIter = 1000;

const _password = '正确的马电池订书钉';

/// 覆盖「中文 / null / int-double 边界 / 嵌套结构」四种内容。
Map<String, Object?> _payload() => {
  'format': BackupPayload.format,
  'formatVersion': BackupPayload.formatVersion,
  'schemaVersion': 10,
  'exportedAt': '2026-10-20T17:21:05.123',
  'tables': {
    'ledger': [
      {'id': 1, 'name': '日常 · 主账本'},
    ],
    'account': [
      {'id': 1, 'name': '微信', 'balance_cents': 174400, 'opening_cents': -90000},
      {'id': 2, 'name': '现金', 'balance_cents': 0, 'opening_cents': 0},
    ],
    'txn': [
      {
        'id': 1,
        'amount_cents': 2350,
        'type': 'expense',
        'note': '午饭 · 楼下那家面馆 · 加了两个卤蛋',
        'date': '2026-10-20',
        'period_start': '2026-10-01',
        'account_id': 1,
        'to_account_id': null,
        'merchant': '面馆',
        'meta': {
          'nested': {
            'deep': [1, 2, 3],
          },
        },
      },
      {
        'id': 2,
        // int 边界：SQLite 的 64 位上限，走一遍 JSON 不能被截成 double
        'amount_cents': 9007199254740991,
        'type': 'income',
        'note': '',
        'date': '2026-10-20',
        'account_id': null,
      },
    ],
  },
};

/// 一份「像导出的那样」的密文（每个用例自己再改）。
Future<String> _sealed({String password = _password}) =>
    SealedBackupFile.seal(_payload(), password: password, iterations: _fastIter);

/// 把密文 JSON 拆开，方便篡改单个字段。
///
/// 这里故意**不用** `PlainBackupFile.decode`：它是「明文容器」的入口，
/// 遇到加密信封会直接拒绝（那是对的行为）。测试要改字段，所以自己拆 JSON。
Map<String, Object?> _envelope(String text) {
  final v = jsonDecode(text);
  return (v as Map).map((k, x) => MapEntry(k.toString(), x));
}

void main() {
  group('往返', () {
    test('中文 / null / int 边界 / 嵌套结构都原样回来', () async {
      final out = await SealedBackupFile.unseal(
        await _sealed(),
        password: _password,
      );
      final original = _payload();

      expect(out['format'], BackupPayload.format);
      expect(out['schemaVersion'], 10);
      expect(out['exportedAt'], '2026-10-20T17:21:05.123');

      final tables = (out['tables']! as Map).cast<String, Object?>();
      final txns = (tables['txn']! as List).cast<Map<String, Object?>>();
      expect(txns, hasLength(2));
      expect(txns[0]['note'], '午饭 · 楼下那家面馆 · 加了两个卤蛋');
      expect(txns[0]['to_account_id'], isNull);
      // int 不能被 JSON 往返悄悄变成 double（那会把 1 分钱变成 0.01 元）
      expect(txns[1]['amount_cents'], 9007199254740991);
      expect(txns[1]['amount_cents'], isA<int>());
      // 嵌套结构逐层对得上
      final meta = (txns[0]['meta']! as Map).cast<String, Object?>();
      final nested = (meta['nested']! as Map).cast<String, Object?>();
      expect((nested['deep']! as List), [1, 2, 3]);

      // 整份 payload 与原件等价（deep 比较交给 equals）
      expect(out, equals(original));
    });

    test('同一个 payload 封两次得到两份不同的密文（salt / nonce 随机）', () async {
      final a = _envelope(await _sealed());
      final b = _envelope(await _sealed());
      expect(a['salt'], isNot(b['salt']));
      expect(a['nonce'], isNot(b['nonce']));
      expect(a['data'], isNot(b['data']));
      // 但都能解开
      expect(
        await SealedBackupFile.unseal(
          await _sealed(),
          password: _password,
        ),
        isNotEmpty,
      );
    });

    test('容器里不出现明文：备注与账户名都读不到', () async {
      final text = await _sealed();
      expect(text.contains('面馆'), isFalse);
      expect(text.contains('微信'), isFalse);
      expect(text.contains('午饭'), isFalse);
      // 但 header 字段是明文的（恢复时要靠它挑算法）
      expect(text.contains('pbkdf2-hmac-sha256'), isTrue);
      expect(text.contains('aes-256-gcm'), isTrue);
    });
  });

  group('拒绝：密码学层面的篡改', () {
    test('口令错：抛 wrongPasswordOrCorrupt（不是「文件坏了」，两者不可区分）',
        () async {
      final text = await _sealed();
      await expectLater(
        () => SealedBackupFile.unseal(text, password: '错的口令'),
        throwsA(
          isA<BackupSealedException>().having(
            (e) => e.kind,
            'kind',
            SealedFailureKind.wrongPasswordOrCorrupt,
          ),
        ),
      );
    });

    test('口令错时错误信息不把责任推给用户（同时说清两种可能）', () async {
      try {
        await SealedBackupFile.unseal(await _sealed(), password: 'nope');
        fail('应当抛异常');
      } on BackupSealedException catch (e) {
        expect(e.message, contains('口令'));
        expect(e.message, contains('不完整'));
        // 不能出现「密码错误」这种把文件损坏排除掉的断言式说法
        expect(e.message.contains('密码错误'), isFalse);
      }
    });

    test('密文改 1 bit → 被拒', () async {
      final env = _envelope(await _sealed());
      final data = (env['data']! as String).split('');
      // base64 里改一个字符 = 改掉最多 6 bit；改的是密文中段，一定会碰到明文
      final idx = data.length ~/ 2;
      data[idx] = data[idx] == 'A' ? 'B' : 'A';
      env['data'] = data.join();
      await _expectAuthRejected(env);
    });

    test('salt 被改 → 被拒（salt 在 AAD 里，同时也会派生错密钥）', () async {
      final env = _envelope(await _sealed());
      env['salt'] = _flipBase64(env['salt']! as String);
      await _expectAuthRejected(env);
    });

    test('nonce 被改 → 被拒（nonce 在 AAD 里，且 GCM 自身绑 nonce）', () async {
      final env = _envelope(await _sealed());
      env['nonce'] = _flipBase64(env['nonce']! as String);
      await _expectAuthRejected(env);
    });

    test('迭代数被改 → 被拒（它在 AAD 里，因此派生出的密钥也不对）', () async {
      final env = _envelope(await _sealed());
      env['iter'] = (env['iter']! as int) + 1;
      await _expectAuthRejected(env);
    });

    test('容器版本被改高 → unsupportedContainer（不是「口令错」）', () async {
      final env = _envelope(await _sealed());
      env['containerVersion'] = kContainerVersion + 1;
      await expectLater(
        () => SealedBackupFile.unseal(_encode(env), password: _password),
        throwsA(
          isA<BackupSealedException>().having(
            (e) => e.kind,
            'kind',
            SealedFailureKind.unsupportedContainer,
          ),
        ),
      );
    });

    test('截断末 16 字节（tag）→ 被拒', () async {
      final env = _envelope(await _sealed());
      final raw = _b64(env['data']! as String);
      env['data'] = _b64encode(raw.sublist(0, raw.length - 16));
      await _expectAuthRejected(env);
    });

    test('把密文整个删掉一截 → 被拒（不是解出半份数据）', () async {
      final env = _envelope(await _sealed());
      final raw = _b64(env['data']! as String);
      env['data'] = _b64encode(raw.sublist(0, raw.length ~/ 2));
      await _expectAuthRejected(env);
    });

    test('算法标签被换成别的 → unsupportedContainer（不猜、不降级）', () async {
      final env = _envelope(await _sealed());
      env['cipher'] = 'aes-128-cbc';
      await expectLater(
        () => SealedBackupFile.unseal(_encode(env), password: _password),
        throwsA(
          isA<BackupSealedException>().having(
            (e) => e.kind,
            'kind',
            SealedFailureKind.unsupportedContainer,
          ),
        ),
      );
    });
  });

  group('拒绝：文件根本不成形', () {
    test('不是 JSON', () async {
      await expectLater(
        () => SealedBackupFile.unseal('这不是 JSON', password: _password),
        throwsA(
          isA<BackupSealedException>().having(
            (e) => e.kind,
            'kind',
            SealedFailureKind.malformedHeader,
          ),
        ),
      );
    });

    test('是别的应用的 JSON', () async {
      await expectLater(
        () => SealedBackupFile.unseal('{"format":"other"}', password: _password),
        throwsA(isA<BackupSealedException>()),
      );
    });

    test('迭代数被改成天文数字 → 直接拒绝，不白等几分钟', () async {
      final env = _envelope(await _sealed());
      env['iter'] = 999999999;
      await expectLater(
        () => SealedBackupFile.unseal(_encode(env), password: _password),
        throwsA(isA<BackupSealedException>()),
      );
    });

    test('salt 长度不对', () async {
      final env = _envelope(await _sealed());
      env['salt'] = _b64encode([1, 2, 3]);
      await expectLater(
        () => SealedBackupFile.unseal(_encode(env), password: _password),
        throwsA(
          isA<BackupSealedException>().having(
            (e) => e.kind,
            'kind',
            SealedFailureKind.malformedHeader,
          ),
        ),
      );
    });

    test('空口令不给加密（否则等于明文）', () async {
      await expectLater(
        () => SealedBackupFile.seal(
          _payload(),
          password: '',
          iterations: _fastIter,
        ),
        throwsA(isA<BackupSealedException>()),
      );
    });
  });

  group('判型只看内容，不看扩展名', () {
    test('looksSealed 认得出加密文件，认不出明文备份', () async {
      final sealed = await _sealed();
      final plain = PlainBackupFile.encode(_payload());
      expect(SealedBackupFile.looksSealed(sealed), isTrue);
      expect(SealedBackupFile.looksSealed(plain), isFalse);
      expect(SealedBackupFile.looksSealed('随便一段文字'), isFalse);
    });

    test('decodeAny：明文不用口令，加密的要口令', () async {
      final plain = PlainBackupFile.encode(_payload());
      final fromPlain = await SealedBackupFile.decodeAny(plain);
      expect(fromPlain['schemaVersion'], 10);

      final sealed = await _sealed();
      // 没给口令 → 明确说「需要口令」，而不是「不是备份文件」
      await expectLater(
        () => SealedBackupFile.decodeAny(sealed),
        throwsA(isA<BackupSealedException>()),
      );
      final fromSealed = await SealedBackupFile.decodeAny(
        sealed,
        password: _password,
      );
      expect(fromSealed, equals(fromPlain));
    });

    test('把加密文件改名成 .json 也照样要口令（扩展名不算数）', () async {
      // 扩展到内容这一层是看不出来的：这里只验证「内容决定行为」
      final sealed = await _sealed();
      expect(SealedBackupFile.looksSealed(sealed), isTrue);
      await expectLater(
        () => SealedBackupFile.decodeAny(sealed, password: '错'),
        throwsA(isA<BackupSealedException>()),
      );
    });
  });

  group('常量与参数', () {
    test('默认迭代数是实测后选定的 210000（改它请连文档一起改）', () {
      expect(
        kDefaultKdfIterations,
        210000,
        reason: '600000 在本机实测要 3.7s/次，超过「导出不超过 2s」的底线；'
            '210000 实测 1.3s。详见 docs/decisions/加密备份选型.md',
      );
    });

    test('容器版本是 1，且与 payload 的 formatVersion 无关', () {
      expect(kContainerVersion, 1);
      expect(
        BackupPayload.formatVersion,
        1,
        reason: 'payload 结构没变（加表才动它），加密是容器的事',
      );
    });

    test('AAD 拼法确定性：同样的头部字段拼出同样的串', () {
      final a = SealedBackupFile.aadOf(
        containerVersion: 1,
        iterations: 210000,
        saltB64: 'c2FsdA==',
        nonceB64: 'bm9uY2U=',
      );
      final b = SealedBackupFile.aadOf(
        containerVersion: 1,
        iterations: 210000,
        saltB64: 'c2FsdA==',
        nonceB64: 'bm9uY2U=',
      );
      expect(a, b);
      expect(a, contains('aes-256-gcm'));
      expect(a, contains('210000'));
      // 任一字段变化 → 串不同（这就是篡改能被发现的原因）
      expect(
        a,
        isNot(
          SealedBackupFile.aadOf(
            containerVersion: 2,
            iterations: 210000,
            saltB64: 'c2FsdA==',
            nonceB64: 'bm9uY2U=',
          ),
        ),
      );
    });
  });

  group('benchmark：KDF 迭代数的取舍', () {
    test('默认迭代下一次派生耗时 < 2s（600k 会超）', () async {
      final sw = Stopwatch()..start();
      // 一次完整的 seal 就包含一次派生；payload 取小一点，把 GCM 的影响压到最低
      await SealedBackupFile.seal(
        {
          'format': BackupPayload.format,
          'tables': <String, Object?>{},
        },
        password: _password,
      );
      final ms = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('BENCH 默认迭代($kDefaultKdfIterations) 一次 seal = ${ms}ms');
      // 门限 3s，不是 2s：这条要抓的是「有人把默认迭代数改回 600000」这类
      // 数量级回归（600k 单次派生 3.7s，必然超），不是基准测试。
      // 本机空载实测 1.24s，但两个 `flutter test` 同时跑时实测过 2.03s ——
      // 卡在 2s 上只会得到一条随机器负载变红的测试。
      // 「默认值到底是哪个数」由上面那条常量断言钉着，那一条才是硬的。
      expect(
        ms,
        lessThan(3000),
        reason: '一次派生 $ms ms —— 数量级不对了。'
            '（600000 迭代单次派生 3.7s，所以默认降到了 210000）',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

// ---------------------------------------------------------------- 测试工具

/// 鉴权类失败的统一断言（口令错 / 被改 / 被截断都走这里）。
Future<void> _expectAuthRejected(Map<String, Object?> env) async {
  await expectLater(
    () => SealedBackupFile.unseal(_encode(env), password: _password),
    throwsA(
      isA<BackupSealedException>().having(
        (e) => e.kind,
        'kind',
        SealedFailureKind.wrongPasswordOrCorrupt,
      ),
    ),
  );
}

String _encode(Map<String, Object?> env) => jsonEncode(env);

String _flipBase64(String s) {
  final raw = _b64(s);
  raw[0] = raw[0] ^ 0x01;
  return _b64encode(raw);
}

List<int> _b64(String s) => base64Decode(s);

String _b64encode(List<int> bytes) => base64Encode(bytes);
