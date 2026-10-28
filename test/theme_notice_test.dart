// 「默认皮肤变了」这条一次性提示的自检。
//
// 为什么要测：1.5.1 把出厂默认从「黑塔 · 永夜」（深色）换成了「圣地 · 审判白」
// （亮色）。从没手动切过皮肤的老用户升级后，界面毫无征兆地变浅 —— 他没做过任何
// 操作，只能理解成 bug。但提示弹多了同样是 bug：每次都弹等于没有「一次性」，
// 对着空库弹则是纯打扰（全新安装看到的就是新默认色，本来没有"变化"可解释）。
//
// 所以四个用例逐个钉住四种处境：
//   1) 有账目、没选过皮肤、没提示过 → **要弹**
//   2) 承接 1 再启动一次        → **不弹**（只弹一次）
//   3) 有账目但用户自己选过皮肤  → **不弹**（他知道自己能选，也可能就是他选的这套）
//   4) 空库（全新安装）         → **不弹**（没有"变化"可解释）
//
// 判据里没有「升级标记」可用：这次只换默认色、表结构一列没动，升级路径上不产生
// 任何信号。于是改用反向判据「库里有账目 = 不是全新安装」—— 这条正是本测试在验的东西。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/db.dart';
import 'package:ledger/data/models.dart';
import 'package:ledger/data/repo.dart';
import 'package:ledger/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'test_theme_notice.db';

/// 提示标记的键，与 `Store._kThemeNotice` 同一个字符串。
///
/// 测试里重复一遍而不是把它暴露成 public：这个键是库内约定，不该为了让测试少写
/// 一个常量就扩大 API。改键名时这条会跟着红，正好提醒同步。
const _kThemeNotice = 'ui.theme_notice';

Future<String> _dbPath() async =>
    p.join(await databaseFactory.getDatabasesPath(), _dbName);

/// 造一笔最小账目。
///
/// 只服务于「库里有数据」这一条判据，所以不关心它记了什么 —— 金额、日期都取
/// 随手能拿到的默认值。先 boot 一次再调它：默认账本与分类是 boot 时种下的。
Future<void> _seedOneTxn() async {
  final s = Store.i;
  await Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: s.ledgerId,
      type: TxnType.expense,
      amountCents: 100,
      date: Fmt.today(),
      categoryId: s.expenseCats.first.id,
    ),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.fileName = _dbName;
  });

  setUp(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  tearDown(() async {
    await Db.close();
    final f = File(await _dbPath());
    if (f.existsSync()) f.deleteSync();
  });

  test('有账目 + 没选过皮肤 → 提示，且标记落库', () async {
    // 第一次 boot 用的是空库：建表、种默认账本与分类，此时没有账目 → 不该提示
    await Store.i.boot();
    expect(
      Store.i.themeDefaultNotice,
      isFalse,
      reason: '空库就弹提示，等于每次全新安装都被打扰一遍',
    );

    await _seedOneTxn();

    // 老用户的下一次冷启动
    await Store.i.boot();
    expect(Store.i.themeDefaultNotice, isTrue, reason: '老用户界面变浅了却没人告诉他');
    expect(
      await Repo.getSetting(_kThemeNotice),
      '1',
      reason: '标记没落库 → 下次启动还会再弹一次，那就不叫"一次性"了',
    );
  });

  test('再启动一次就不再提示（只弹一次）', () async {
    await Store.i.boot();
    await _seedOneTxn();
    await Store.i.boot();
    expect(Store.i.themeDefaultNotice, isTrue, reason: '前置条件没成立，后面的断言没意义');

    await Store.i.boot();
    expect(Store.i.themeDefaultNotice, isFalse, reason: '提示过还被置真，等于每次启动都弹');
  });

  test('用户自己选过皮肤 → 不提示', () async {
    await Store.i.boot();
    await _seedOneTxn();
    // 「选过」的标志就是 ui.theme 有值 —— 有它说明用户进过主题页并做了选择，
    // 默认值变没变与他无关
    await Repo.setSetting('ui.theme', 'cold');

    await Store.i.boot();
    expect(Store.i.themeDefaultNotice, isFalse);
    expect(
      await Repo.getSetting(_kThemeNotice),
      isNull,
      reason: '没用上提示就不该把标记烧掉（将来这个键还要不要另说，别提前写脏数据）',
    );
  });

  test('空库（全新安装）→ 不提示', () async {
    await Store.i.boot();
    expect(Store.i.themeDefaultNotice, isFalse);
    expect(await Repo.getSetting(_kThemeNotice), isNull);
  });
}
