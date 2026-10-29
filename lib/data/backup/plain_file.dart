import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'payload.dart';

// ---------------------------------------------------------------------------
// 明文容器：一个 JSON 文件，就是 payload 本身
// ---------------------------------------------------------------------------
//
// ## 为什么明文不套壳
//
// 1.5.x 到 1.6.0 导出的备份就是 `{format, formatVersion, schemaVersion,
// exportedAt, tables}` 平铺在顶层。给明文套一层 `{container, payload: {...}}`
// 会让**所有老备份都变成「不认识的格式」**，而「数据必须能带走」包含「老文件
// 必须还能导回来」。所以明文的容器就是「没有容器」：`container` 字段缺省，
// `containerVersion` 也就不需要出场。
//
// 加密那份（`sealed_file.dart`）必须套壳 —— 它要放 salt / nonce / 迭代数，
// 没地方塞。于是判型只看顶层 `container` 字段：
//
//   - 没有 / `"plain"` → 明文，`tables` 直接在顶层（老文件也是这个形状）
//   - `"sealed"`       → 加密，走 `sealed_file.dart`
//
// ★ **只按 `container`（以及 `format`）判型，不按扩展名。** 扩展名是给人看的：
//   加密导出用 `.heita`，明文导出仍用 `.json`；但用户在文件管理器里把它改成
//   `a.txt`、或者用微信存成 `.bin`，恢复入口都必须能认出来。反过来说，
//   扩展名写对了但内容是加密的，也不能当明文读。
//
// ## 这个文件不知道「加密」的存在
//
// 它不 import `sealed_file.dart`，签名里也没有口令。所以「快照会不会被悄悄
// 加密」这个问题在这里是**编译期不可能**，而不是「约定好不这么做」。

/// 明文备份文件的读写。
abstract final class PlainBackupFile {
  /// 导出的扩展名。加密那份是 `.heita`（见 `sealed_file.dart`）。
  static const extension = 'json';

  static const _encoder = JsonEncoder.withIndent('  ');

  /// payload → 文件内容。
  ///
  /// 缩进两格、UTF-8：这份文件可能被人用任何编辑器打开，能读比紧凑重要。
  static String encode(Map<String, Object?> payload) =>
      _encoder.convert(payload);

  /// 文件内容 → payload。格式不对一律抛 [BackupException]（界面直接弹这句）。
  static Map<String, Object?> decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw BackupException('这个文件不是 JSON，可能选错了');
    }
    if (json is! Map) throw BackupException('备份文件内容不是 JSON 对象');
    final map = json.map((k, v) => MapEntry(k.toString(), v));

    // 加密备份也是 `.json` 之外的形状：这里认出来并给一句人话，而不是让
    // `format` 校验报「这不是黑塔的备份」—— 那会让用户以为文件选错了。
    if (map['container'] == 'sealed') {
      throw BackupException(
        '这是一份加密备份，恢复时需要输入导出时设的口令（.heita 通常是它）',
      );
    }
    return map;
  }

  /// 写到临时目录并返回路径（配合分享发出去）。
  static Future<String> writeToTempFile(
    Map<String, Object?> payload, {
    String? stamp,
  }) => writeTempFile(
    '黑塔消费日记-备份-${stamp ?? stampOf(DateTime.now())}.json',
    encode(payload),
  );

  /// 写一个临时文件，返回路径。
  ///
  /// 文件名（含扩展名）由调用方给：明文是 `.json`，加密是 `.heita`。
  /// 扩展名只影响用户在文件管理器里看到什么，恢复入口**只按内容判型**。
  static Future<String> writeTempFile(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsString(content);
    return file.path;
  }

  /// 读一份文件成 payload。
  static Future<Map<String, Object?>> readFile(String path) async {
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (e) {
      throw BackupException('读不了这个文件：${e.message}');
    }
    return decode(text);
  }

  /// 让用户挑一个备份文件，返回 `(原始内容, 文件名)`；取消返回 null。
  ///
  /// 用 `FileType.any` 而不是限定 json：Android 上不少文件管理器会把
  /// `.json` / `.heita` 识别成 `application/octet-stream`，限定类型反而选不到。
  ///
  /// 返回**原始文本**而不是解好的 payload：调用方要先判断这是不是加密文件
  /// （见 `sealed_file.dart` 的 `decodeAny`），读文件这一步不该替它决定。
  static Future<(String, String)?> pickText() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    final path = files.first.path;
    if (path == null) return null;

    try {
      return (await File(path).readAsString(), files.first.name);
    } catch (e) {
      throw BackupException('读不了这个文件：$e');
    }
  }

  /// `20261020-172105`
  static String stampOf(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
