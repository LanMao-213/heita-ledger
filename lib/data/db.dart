import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 本地 SQLite 存储。
///
/// ★ 单机应用的前提：**不发任何 HTTP 请求、不接任何统计/崩溃上报/广告 SDK**。
///   华为官方口径是「断网后所有核心功能可用」即为单机应用，可勾选「单机APP」免备案。
///   这里是那条红线的落点 —— 数据只进本地 SQLite，不出去。
///
/// ★ 金额统一 INTEGER 存「分」；日期统一 TEXT `YYYY-MM-DD`。
class Db {
  Db._();

  static Database? _db;

  static const _fileName = 'heita_ledger.db';

  /// 库文件名。测试会改成别的名字 —— `flutter test` 是并行跑多个测试文件，
  /// 共用一个文件名时两个进程会抢同一个 sqlite 文件（Windows 上直接删不掉）。
  static String fileName = _fileName;

  /// 2：`txn_template` 增加 `use_count` / `last_used_at`（模板按使用频率排序）
  static const _version = 2;

  static Future<Database> open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, fileName),
      version: _version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seed(db);
      },
      // 老版本装过的手机走这里：只加列，不动已有数据。
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE txn_template ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE txn_template ADD COLUMN last_used_at TEXT',
          );
        }
      },
    );
    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 危险操作：清空全部业务数据（保留设置）
  static Future<void> wipeAllData() async {
    final db = await open();
    await db.transaction((txn) async {
      await txn.delete('txn');
      await txn.delete('budget');
      await txn.delete('saving_goal');
      await txn.delete('recurring');
      await txn.delete('txn_template');
      await txn.delete('category');
      await txn.delete('account');
      await txn.delete('ledger');
    });
    await _seed(db);
  }

  static Future<void> _createSchema(Database db) async {
    const statements = <String>[
      '''
      CREATE TABLE ledger (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        icon        TEXT    NOT NULL DEFAULT 'book',
        sort_order  INTEGER NOT NULL DEFAULT 0,
        archived    INTEGER NOT NULL DEFAULT 0,
        created_at  TEXT    NOT NULL DEFAULT ''
      )''',

      '''
      CREATE TABLE account (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        name             TEXT    NOT NULL,
        kind             TEXT    NOT NULL DEFAULT 'cash',
        balance_cents    INTEGER NOT NULL DEFAULT 0,
        include_in_total INTEGER NOT NULL DEFAULT 1,
        sort_order       INTEGER NOT NULL DEFAULT 0,
        archived         INTEGER NOT NULL DEFAULT 0
      )''',

      '''
      CREATE TABLE category (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id   INTEGER NOT NULL,
        type        TEXT    NOT NULL,
        name        TEXT    NOT NULL,
        icon        TEXT    NOT NULL DEFAULT 'more',
        parent_id   INTEGER,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        archived    INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (ledger_id) REFERENCES ledger(id) ON DELETE CASCADE
      )''',

      '''
      CREATE TABLE txn (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id     INTEGER NOT NULL,
        type          TEXT    NOT NULL,
        amount_cents  INTEGER NOT NULL,
        category_id   INTEGER,
        account_id    INTEGER,
        to_account_id INTEGER,
        date          TEXT    NOT NULL,
        note          TEXT    NOT NULL DEFAULT '',
        template_id   INTEGER,
        recurring_id  INTEGER,
        created_at    TEXT    NOT NULL DEFAULT '',
        updated_at    TEXT    NOT NULL DEFAULT '',
        FOREIGN KEY (ledger_id) REFERENCES ledger(id) ON DELETE CASCADE
      )''',

      // 月统计与明细列表的核心索引
      'CREATE INDEX idx_txn_ledger_date ON txn (ledger_id, date)',
      'CREATE INDEX idx_txn_category ON txn (category_id)',
      'CREATE INDEX idx_txn_account ON txn (account_id)',

      '''
      CREATE TABLE budget (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id    INTEGER NOT NULL,
        month        TEXT    NOT NULL,
        category_id  INTEGER,
        amount_cents INTEGER NOT NULL DEFAULT 0,
        UNIQUE (ledger_id, month, category_id)
      )''',

      '''
      CREATE TABLE saving_goal (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        name         TEXT    NOT NULL,
        icon         TEXT    NOT NULL DEFAULT 'target',
        target_cents INTEGER NOT NULL DEFAULT 0,
        saved_cents  INTEGER NOT NULL DEFAULT 0,
        due_month    TEXT,
        sort_order   INTEGER NOT NULL DEFAULT 0,
        archived     INTEGER NOT NULL DEFAULT 0
      )''',

      '''
      CREATE TABLE recurring (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id     INTEGER NOT NULL,
        type          TEXT    NOT NULL,
        amount_cents  INTEGER NOT NULL,
        category_id   INTEGER,
        account_id    INTEGER,
        note          TEXT    NOT NULL DEFAULT '',
        freq          TEXT    NOT NULL DEFAULT 'monthly',
        interval      INTEGER NOT NULL DEFAULT 1,
        next_run_date TEXT    NOT NULL,
        end_date      TEXT,
        enabled       INTEGER NOT NULL DEFAULT 1
      )''',

      'CREATE INDEX idx_recurring_next ON recurring (enabled, next_run_date)',

      '''
      CREATE TABLE txn_template (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id    INTEGER NOT NULL,
        name         TEXT    NOT NULL,
        icon         TEXT    NOT NULL DEFAULT 'tpl',
        type         TEXT    NOT NULL,
        amount_cents INTEGER NOT NULL DEFAULT 0,
        category_id  INTEGER,
        account_id   INTEGER,
        note         TEXT    NOT NULL DEFAULT '',
        sort_order   INTEGER NOT NULL DEFAULT 0,
        use_count    INTEGER NOT NULL DEFAULT 0,
        last_used_at TEXT
      )''',

      '''
      CREATE TABLE setting (
        k TEXT PRIMARY KEY,
        v TEXT NOT NULL
      )''',
    ];

    for (final s in statements) {
      await db.execute(s);
    }
  }

  /// 首次安装的默认数据：一个账本、几个常用账户、原型里的全套分类。
  /// **不预置任何交易记录** —— 账本应该从用户自己的第一笔开始。
  static Future<void> _seed(Database db) async {
    final ledgerId = await db.insert('ledger', {
      'name': '日常账本',
      'icon': 'book',
      'sort_order': 0,
      'archived': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    const accounts = [
      {'name': '现金', 'kind': 'cash', 'sort_order': 0},
      {'name': '支付宝', 'kind': 'alipay', 'sort_order': 1},
      {'name': '微信', 'kind': 'wechat', 'sort_order': 2},
      {'name': '储蓄卡', 'kind': 'debit', 'sort_order': 3},
    ];
    for (final a in accounts) {
      await db.insert('account', {
        ...a,
        'balance_cents': 0,
        'include_in_total': 1,
        'archived': 0,
      });
    }

    await _seedCategories(db, ledgerId);

    await db.insert('setting', {'k': 'current_ledger_id', 'v': '$ledgerId'});
    await db.insert('setting', {'k': 'app_name', 'v': '黑塔消费日记'});
    await db.insert('setting', {'k': 'schema_ready', 'v': '1'});
  }

  /// 默认分类 —— 图标键与原型 `CATS` 一一对应
  static Future<void> _seedCategories(Database db, int ledgerId) async {
    const expense = [
      ('餐饮', 'food'),
      ('交通', 'transport'),
      ('购物', 'shopping'),
      ('居住', 'home'),
      ('娱乐', 'fun'),
      ('医疗', 'medical'),
      ('学习', 'study'),
      ('通讯', 'comm'),
      ('人情', 'gift'),
      ('其他', 'more'),
    ];
    const income = [
      ('工资', 'salary'),
      ('奖金', 'bonus'),
      ('兼职', 'parttime'),
      ('理财', 'invest'),
      ('红包', 'redpacket'),
      ('其他', 'more'),
    ];

    var order = 0;
    for (final (name, icon) in expense) {
      await db.insert('category', {
        'ledger_id': ledgerId,
        'type': 'expense',
        'name': name,
        'icon': icon,
        'sort_order': order++,
        'archived': 0,
      });
    }
    order = 0;
    for (final (name, icon) in income) {
      await db.insert('category', {
        'ledger_id': ledgerId,
        'type': 'income',
        'name': name,
        'icon': icon,
        'sort_order': order++,
        'archived': 0,
      });
    }
  }
}
