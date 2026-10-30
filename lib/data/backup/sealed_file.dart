import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'payload.dart';
import 'plain_file.dart';

// ---------------------------------------------------------------------------
// 加密容器：AES-256-GCM，口令走 PBKDF2-HMAC-SHA256
// ---------------------------------------------------------------------------
//
// ## 为什么是这两个算法
//
// AES-256-GCM 是**带认证**的对称加密：解出来的东西要么完整、要么直接失败，
// 没有第三种可能。这一点对这个功能是刚需 —— 口令错了必须表现为「打不开」，
// 而不是「解出一堆乱码然后写进库里」。
//
// 口令不能直接当密钥（人能记住的字符串熵太低），必须先拉伸。PBKDF2-HMAC-SHA256
// 是唯一一个「每个平台都自带实现、不需要额外原生库」的选择，强度够用，
// 参数只有迭代数一个，好解释。
//
// ## 为什么不用别的
//
// - **pointycastle**：功能全，但它是「把密码学当工具包」的库，API 面很大
//   （BlockCipher / PaddedBlockCipher / AEAD 三套并存），用错模式不会报错，
//   只会安静地少一层认证。我们只需要一件事：认证加密一段字节。
// - **MethodChannel 调系统 Keystore / CryptoKit**：能把密钥锁进 TEE，
//   但（a）需要原生代码 + 每个平台各写一遍，（b）导出文件是要**跨设备**恢复的，
//   平台密钥帮不上忙（换了手机就解不开），（c）`tools/check_no_network.sh`
//   之外还要再加一层平台通道审计。收益全在「本机存储」，而我们要的是
//   「带走的那份文件」。本机存储的敏感数据本来就没有（不联网、无账号）。
// - **dart:ffi + OpenSSL**：多一个原生二进制、多一份 ABI 兼容风险、
//   多一处过审时被问「这个 .so 是什么」。为了几百毫秒的 KDF 不值得。
// - **自己拼 AES 分组模式（CBC + HMAC）**：加密与认证两套密钥的派生顺序、
//   先加密后 MAC 还是先 MAC 后加密，每一个细节写错都「看起来能用」。
//   GCM 把这件事收进一个原语里。
//
// ## 继承关系与「忘口令不可恢复」
//
// `BackupSealedException` 继承 `BackupException`：界面原来那套
// `catch (BackupException)` 不用改一行，新错误类型照样能弹出一句话。
// 多出来的 `kind` 只给界面用来**选文案**。
//
// ★ **我们不保存口令，忘了就打不开** —— 这句话必须出现在用户输口令的地方，
//   不能只写在文档里。这不是偷懒：口令存在设备上，「加密导出」就退回成
//   「换了个格式的明文」；而这份文件的目的正是「离开这台设备之后仍然只有
//   我能读」。
//
// ## 认证失败为什么不能叫「口令错误」
//
// 密码学上「口令错了」与「文件被改了一个 bit」**不可区分** —— 两者都只是
// GCM 的 tag 对不上。所以 `kind` 叫 `wrongPasswordOrCorrupt`，界面文案必须
// 同时给这两种可能（「口令不对，或文件不完整」）。把它写成「口令错误」会让
// 一个文件损坏的用户反复重输口令，最后以为自己的密码丢了。

/// 加密容器里能出现的那几种失败。
///
/// 只有三种，因为**只有这三种对用户有意义**：搞不清是口令还是文件、
/// 文件来自更新的版本、文件头根本不成形。再细分下去（比如「salt 长度不对」
/// 单独一类）用户也做不了任何不同的事。
enum SealedFailureKind {
  /// 认证失败：口令不对，或者密文/头部被改过。**两者不可区分。**
  wrongPasswordOrCorrupt,

  /// 容器版本 / 算法比当前应用新。
  unsupportedContainer,

  /// 文件头缺字段、字段类型不对、base64 解不开。
  malformedHeader,
}

/// 加密容器的读写错误。`kind` 只用来选文案，判定逻辑不要在界面里重写一遍。
class BackupSealedException extends BackupException {
  BackupSealedException(this.kind, String message) : super(message);

  final SealedFailureKind kind;
}

/// 默认 KDF 迭代数。
///
/// 取值依据只有一条：**在本机能接受的耗时内取最大**。
///
/// 设计意图是 600000，但本机实测**一次派生就要 3.7s**（`flutter_tester`、纯 Dart
/// PBKDF2，见 `test/backup_sealed_test.dart` 的 benchmark 用例）—— 那意味着导出
/// 要等近 4 秒、恢复再等近 4 秒，用户会以为卡死。按事先定好的规则（"本机 >
/// 2s 就降到 210000"）取 210000，实测 1.3s。
///
/// 完整的实测表与理由在 `docs/decisions/加密备份选型.md`；改这个常量请连那份
/// 文档一起改（`backup_sealed_test.dart` 有一条断言钉着这个数）。
const kDefaultKdfIterations = 210000;

/// 容器版本。与 payload 的 `formatVersion`、库的 `schemaVersion` **无关**。
const kContainerVersion = 1;

const _containerSealed = 'sealed';
const _kdfLabel = 'pbkdf2-hmac-sha256';
const _cipherLabel = 'aes-256-gcm';

const _saltBytes = 16;
const _nonceBytes = 12;

/// GCM 的 tag 长度。**丢一个字节能被立刻发现，就是靠它。**
const _macBytes = 16;

/// 加密备份的读写。
abstract final class SealedBackupFile {
  /// 导出的扩展名。扩展名是**给人看**的，判型只看顶层 `container` 字段。
  static const extension = 'heita';

  static final _aes = AesGcm.with256bits();

  /// 这份文本是不是加密备份。判型只看 `container` 字段，不看扩展名。
  static bool looksSealed(String text) {
    final map = _tryDecode(text);
    return map != null && map['container'] == _containerSealed;
  }

  /// 加密 → 文件内容（缩进两格的 JSON，外面看像普通备份，里面是二进制）。
  ///
  /// [iterations] 只给测试注入用小值；生产路径永远用 [kDefaultKdfIterations]。
  static Future<String> seal(
    Map<String, Object?> payload, {
    required String password,
    int iterations = kDefaultKdfIterations,
  }) async {
    if (password.isEmpty) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '口令不能为空',
      );
    }
    final salt = _randomBytes(_saltBytes);
    final nonce = _randomBytes(_nonceBytes);
    final saltB64 = base64Encode(salt);
    final nonceB64 = base64Encode(nonce);

    // AAD 把头部每个字段都钉死：改 salt / nonce / iter / containerVersion
    // 中任何一个，tag 都对不上（见 `_aadOf`）。
    final aad = _aadOf(
      containerVersion: kContainerVersion,
      iterations: iterations,
      saltB64: saltB64,
      nonceB64: nonceB64,
    );

    final key = await _deriveKey(password, salt, iterations);
    final clear = utf8.encode(jsonEncode(payload));
    final box = await _aes.encrypt(
      clear,
      secretKey: key,
      nonce: nonce,
      aad: aad,
    );

    return const JsonEncoder.withIndent('  ').convert({
      'format': BackupPayload.format,
      'container': _containerSealed,
      'containerVersion': kContainerVersion,
      'kdf': _kdfLabel,
      'iter': iterations,
      'salt': saltB64,
      'cipher': _cipherLabel,
      'nonce': nonceB64,
      // 密文与 tag 拼在一起：少一个字段就少一次「忘了存 tag」的机会
      'data': base64Encode([...box.cipherText, ...box.mac.bytes]),
    });
  }

  /// 解密 → payload。任何一步不对都抛 [BackupSealedException]。
  static Future<Map<String, Object?>> unseal(
    String text, {
    required String password,
  }) async {
    final header = _parseHeader(text);
    final key = await _deriveKey(password, header.saltBytes, header.iterations);

    final Uint8List raw;
    try {
      raw = base64Decode(header.dataB64);
    } on FormatException {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '加密备份的密文不是有效的 base64，文件可能被改过',
      );
    }
    // 密文至少要有 tag 那么长：截断末 16B 就是从这里被挡下的
    if (raw.length <= _macBytes) {
      throw BackupSealedException(
        SealedFailureKind.wrongPasswordOrCorrupt,
        '这份加密备份不完整（密文太短），可能没下载完或被截断了',
      );
    }
    final cipherText = raw.sublist(0, raw.length - _macBytes);
    final mac = Mac(raw.sublist(raw.length - _macBytes));

    final List<int> clear;
    try {
      clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: header.nonce, mac: mac),
        secretKey: key,
        aad: header.aad,
      );
    } on SecretBoxAuthenticationError {
      // 口令错与文件被改，在密码学上无法区分 —— 文案必须同时说这两种
      throw BackupSealedException(
        SealedFailureKind.wrongPasswordOrCorrupt,
        '打不开：口令不对，或者这份文件不完整。',
      );
    }

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(clear));
    } on FormatException {
      throw BackupSealedException(
        SealedFailureKind.wrongPasswordOrCorrupt,
        '打不开：解出来的内容不是有效数据，文件可能不完整。',
      );
    }
    if (json is! Map) {
      throw BackupSealedException(
        SealedFailureKind.wrongPasswordOrCorrupt,
        '打不开：解出来的内容不是备份结构。',
      );
    }
    return json.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 不管拿到的是明文还是加密文件，都解成 payload。
  ///
  /// [password] 只在加密文件时需要；明文文件传了也不会用到（**不看扩展名**，
  /// 只看内容）。
  static Future<Map<String, Object?>> decodeAny(
    String text, {
    String? password,
  }) async {
    if (!looksSealed(text)) return PlainBackupFile.decode(text);
    if (password == null || password.isEmpty) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '这是一份加密备份，需要输入口令才能恢复',
      );
    }
    return unseal(text, password: password);
  }

  /// AAD 的确定性拼法。**导出与恢复必须逐字一致**，否则自己都解不开。
  ///
  /// 为什么用字符串而不是二进制：出问题时能直接肉眼比对两份文件头。
  static String aadOf({
    required int containerVersion,
    required int iterations,
    required String saltB64,
    required String nonceB64,
  }) => utf8.decode(
    _aadOf(
      containerVersion: containerVersion,
      iterations: iterations,
      saltB64: saltB64,
      nonceB64: nonceB64,
    ),
  );

  // ------------------------------------------------------------------ 内部

  static Uint8List _aadOf({
    required int containerVersion,
    required int iterations,
    required String saltB64,
    required String nonceB64,
  }) => Uint8List.fromList(
    utf8.encode(
      '${BackupPayload.format}|$containerVersion|$_kdfLabel|$iterations|'
      '$saltB64|$_cipherLabel|$nonceB64',
    ),
  );

  static Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) async {
    // PBKDF2 210000 次是**纯 CPU 死算**，在主 isolate 上约 1.2s。这段时间里
    // 事件循环被完全占满：`runWithBusy` 的 `showDialog` 连一帧都画不出来，
    // 用户看到的是「点了加密，界面僵住一秒多，然后弹窗一闪」。输错口令重试
    // 还要再来一次。丢到后台 isolate，主线程只等结果。
    //
    // `SecretKey` 不能跨 isolate 传输，所以只把派生出的字节带回来。
    // 参数（口令 / salt / 迭代数）都是可序列化的简单类型，无需 Transferable。
    final bytes = await Isolate.run(() async {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );
      final key = await pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      return key.extractBytes();
    });
    return SecretKeyData(bytes);
  }

  static Map<String, Object?>? _tryDecode(String text) {
    try {
      final v = jsonDecode(text);
      return v is Map ? v.map((k, x) => MapEntry(k.toString(), x)) : null;
    } on FormatException {
      return null;
    }
  }

  /// 头部字段的解析与校验。**在碰密码学之前**就要把不成形的文件挡掉：
  /// 一个 iter 写成 10 亿的文件可以让界面卡死一分钟才报错。
  static _SealedHeader _parseHeader(String text) {
    final map = _tryDecode(text);
    if (map == null) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '这个文件不是 JSON，可能选错了',
      );
    }
    if (map['format'] != BackupPayload.format) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '这不是「黑塔消费日记」的备份文件',
      );
    }
    if (map['container'] != _containerSealed) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '这不是加密备份（没有 encrypted 容器标记）',
      );
    }
    final cv = map['containerVersion'];
    if (cv is! int) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '加密备份缺少容器版本',
      );
    }
    if (cv > kContainerVersion) {
      throw BackupSealedException(
        SealedFailureKind.unsupportedContainer,
        '这份加密备份来自更新的版本（容器 v$cv），请先升级应用',
      );
    }
    if (map['kdf'] != _kdfLabel || map['cipher'] != _cipherLabel) {
      throw BackupSealedException(
        SealedFailureKind.unsupportedContainer,
        '这份加密备份用了当前版本不认识的算法（${map['kdf']} / ${map['cipher']}）',
      );
    }
    final iter = map['iter'];
    if (iter is! int || iter < 1) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '加密备份的迭代数不成形',
      );
    }
    // 迭代数上限：正常导出是 6 位数量级，超过 10 倍默认值只可能是文件被改过。
    // 不设这个上限，一个被篡改成 10^9 的文件会让界面白等好几分钟。
    if (iter > kDefaultKdfIterations * 10) {
      throw BackupSealedException(
        SealedFailureKind.unsupportedContainer,
        '加密备份声明的迭代数大得不正常（$iter），拒绝解析',
      );
    }

    final salt = _decodeBytes(map['salt'], 'salt', _saltBytes);
    final nonce = _decodeBytes(map['nonce'], 'nonce', _nonceBytes);
    final data = map['data'];
    if (data is! String || data.isEmpty) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '加密备份里没有密文',
      );
    }

    final saltB64 = base64Encode(salt);
    final nonceB64 = base64Encode(nonce);
    return _SealedHeader(
      iterations: iter,
      saltBytes: salt,
      nonce: nonce,
      dataB64: data,
      // AAD 用**重新编码后的** base64，与导出时的拼法一致
      aad: _aadOf(
        containerVersion: cv,
        iterations: iter,
        saltB64: saltB64,
        nonceB64: nonceB64,
      ),
    );
  }

  static Uint8List _decodeBytes(Object? raw, String field, int expected) {
    if (raw is! String) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '加密备份缺少 $field',
      );
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(raw);
    } on FormatException {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '加密备份的 $field 不是有效的 base64',
      );
    }
    if (bytes.length != expected) {
      throw BackupSealedException(
        SealedFailureKind.malformedHeader,
        '加密备份的 $field 长度不对（应为 $expected 字节）',
      );
    }
    return bytes;
  }

  static Uint8List _randomBytes(int n) {
    // Random.secure()：普通 Random 的种子在同一台设备上可预测，
    // nonce 一旦重复，GCM 的认证就被彻底击穿（同密钥同 nonce = 明文泄漏）。
    final rnd = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(n, (_) => rnd.nextInt(256)),
    );
  }
}

/// 解析后的文件头。
class _SealedHeader {
  const _SealedHeader({
    required this.iterations,
    required this.saltBytes,
    required this.nonce,
    required this.dataB64,
    required this.aad,
  });

  final int iterations;
  final Uint8List saltBytes;
  final List<int> nonce;
  final String dataB64;
  final Uint8List aad;
}
