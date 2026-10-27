import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'category_seed.dart';

/// 库里的数据版本比当前 App 新（用户装回了旧包）。
///
/// 不处理的话 sqflite 会抛一条英文堆栈，用户在启动页看到的是「启动失败 +
/// DatabaseException(… onDowngrade …)」。账本类应用里这句噪音很危险：
/// 用户的第一反应是「卸载重装」，而卸载 = 本地账目全清。
class DbDowngradeException implements Exception {
  const DbDowngradeException({required this.found, required this.supported});

  /// 磁盘上那份库的版本
  final int found;

  /// 当前 App 支持的版本
  final int supported;

  @override
  String toString() =>
      '这份账本来自更新的版本（数据版本 $found），当前应用只支持到 $supported。\n'
      '请装回最新版本后再打开。\n'
      '账目都还在，不要卸载重装 —— 卸载会把它们一起清掉。';
}

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
  /// 3：收入分类补「提成」
  /// 4：`txn` 增加 `period_start`（归属期，F5 阶段 2 —— 加列但**不改查询**）
  /// 5：`budget` 由「自然月」改为「归属期」存储（D13 改口径，预算也按周期）
  /// 6：分类改两级（复用 `parent_id`）+ `txn` 加 4 个详情列。
  ///    **不动任何一笔交易**：老分类靠改名/降级落位，没有对应子分类的记录
  ///    留在父级，明细里显示为一级分类名。
  /// 7：新增 `debt`（借贷往来）+ `txn.debt_id`。借贷产生的流水挂在 debt 上，
  ///    统计一律排除；老数据 `debt_id` 全为 NULL，行为不变。
  /// 8：`account` 增加 `opening_cents`（期初 / 手工校准值）。
  ///    **余额从此可对账**：`balance_cents = opening_cents + 流水合计`。
  ///    老库按 `opening = 余额 − 流水合计` 回填，升级后余额一分不变。
  /// 9：加两条**部分唯一索引**，把两类重复从「代码里挡」变成「物理上不可能」：
  ///    · `txn(recurring_id, date)`：同一周期同一天生成两条流水；
  ///    · `budget(ledger_id, period_start) WHERE category_id IS NULL`：
  ///      同一账本同一期存两份总预算（表级 UNIQUE 对 NULL 不生效，这是漏洞所在）。
  ///    迁移前先清存量重复：周期流水只把多余那条的 `recurring_id` 置 NULL
  ///    （**不删流水，钱一分不动**）；重复的总预算保留最新一条（预算是设置项）。
  static const _version = 9;

  /// 当前 schema 版本。备份文件里会记下来，恢复时用来判断兼容性。
  static int get schemaVersion => _version;

  /// 这次启动是否真的把老库升成了两级分类（全新安装为 false）。
  ///
  /// 只用来决定「要不要给用户一句提示」：分类被改名、多出一层子分类之后，
  /// 老用户打开会以为数据被改乱了。提示只出一次，见 [Store.boot]。
  static bool upgradedToTwoLevel = false;

  /// 已经打开的连接，没有则为 null。
  ///
  /// 给 [WriteGateway] 用：库已经开着的时候不必再经过一次 `await`。
  /// 少一个异步跳转在真机上无感，但在 `testWidgets` 的假时钟里，
  /// 每多一次 await 就要多一次 pump 才能推进 —— 界面里触发写入的用例
  /// 会因为「差一个微任务」而断言到旧数据。
  static Database? get cached => _db;

  static Future<Database> open() async {
    if (_db != null) return _db!;    final dir = await getDatabasesPath();
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
        if (oldVersion < 3) {
          // 补后加的种子分类。用户自己建过同名的就不插，避免出现两个「提成」
          await _addMissingIncomeCategories(db);
        }
        if (oldVersion < 4) {
          await _addPeriodStartColumn(db);
        }
        if (oldVersion < 5) {
          await _moveBudgetToPeriod(db);
        }
        if (oldVersion < 6) {
          await _migrateTwoLevelCategories(db);
          upgradedToTwoLevel = true;
        }
        if (oldVersion < 7) {
          await _addDebtTable(db);
        }
        if (oldVersion < 8) {
          await _addOpeningBalanceColumn(db);
        }
        if (oldVersion < 9) {
          await _addUniqueIndexes(db);
        }
      },
      // 装了旧版本（库里的 schema 比这个包新）时走到这里。sqflite 默认会直接
      // 抛异常，用户在启动页只看到一行英文堆栈。这里换成一句能看懂的话 ——
      // 账目都还在，别卸载重装（卸载等于清空）。
      onDowngrade: (db, oldVersion, newVersion) async {
        throw DbDowngradeException(found: oldVersion, supported: newVersion);
      },
    );
    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 从**旧版本备份**恢复之后调用，把恢复回来的扁平分类升成两级。
  ///
  /// 为什么需要：`onUpgrade` 只在「手机上的老库被新版应用打开」时触发；
  /// 备份恢复是直接往已经建好的新库表里灌行，那条路径根本不会走进 onUpgrade。
  /// 少了这一步，从 v5 备份恢复的账本会一直是「交通 / 通讯」那套平铺分类，
  /// 而界面上按两级渲染的分类管理页会显示成「一级分类 + 0 个子分类」。
  ///
  /// 迁移本身幂等（见 [_migrateTwoLevelCategories]），重复调用只会补缺。
  static Future<void> upgradeRestoredData() async {
    final db = await open();
    await _migrateTwoLevelCategories(db);
  }

  /// 清空时**子表在前、主表在后**：顺序错了会撞 `foreign_keys = ON`。
  ///
  /// `setting` 故意不在名单里 —— 它只放机器状态（当前账本、实验开关、提示是否
  /// 出过），清账目不该顺手把「当前账本」抹成空串。[_seed] 会把它覆盖成新账本。
  static const _wipeOrder = <String>[
    'txn',
    'debt',
    'budget',
    'saving_goal',
    'recurring',
    'txn_template',
    'category',
    'account',
    'ledger',
  ];

  /// 危险操作：清空全部业务数据（保留设置，重建默认账本/账户/分类）。
  ///
  /// ★ **删除与重建必须在同一个事务里**。1.4.1 及以前是「事务里只删、事务
  /// 外再 `_seed`」：`_seed` 往 `setting` 插 `current_ledger_id` 撞主键抛异常，
  /// 而删除已经提交 —— 结果是数据被删了一半（分类账户重建了、账本序号变了），
  /// `Store.reboot()` 也没执行，界面还挂着内存里的旧数据。用户看到的就是
  /// 「点了没反应、数据还在」；下次冷启动 `current_ledger_id` 指向已删除的
  /// 账本，明细与分类全空。事务化之后，任何一步失败都整体回滚，
  /// 调用方可以放心对用户说「数据未改动」。
  static Future<void> wipeAllData() async {
    final db = await open();
    await db.transaction((txn) async {
      for (final table in _wipeOrder) {
        await txn.delete(table);
      }
      await _seed(txn);
    });
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
        -- v8：期初 / 手工校准值。余额 = opening_cents + 流水合计，
        -- 有了这个基准才能对账（见 Integrity.check）
        opening_cents    INTEGER NOT NULL DEFAULT 0,
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
        period_start  TEXT,
        note          TEXT    NOT NULL DEFAULT '',
        -- 详情字段（v6）：挂到子分类上，全部可空，不填也能存
        place_from    TEXT,
        place_to      TEXT,
        person        TEXT,
        subject       TEXT,
        -- 借贷往来（v7）：非空表示这笔是某笔借出/借入的本金或还款，
        -- 统计一律排除，明细里按「借出 · 张三」渲染
        debt_id       INTEGER,
        template_id   INTEGER,
        recurring_id  INTEGER,
        created_at    TEXT    NOT NULL DEFAULT '',
        updated_at    TEXT    NOT NULL DEFAULT '',
        FOREIGN KEY (ledger_id) REFERENCES ledger(id) ON DELETE CASCADE
      )''',

      // 月统计与明细列表的核心索引
      'CREATE INDEX idx_txn_ledger_date ON txn (ledger_id, date)',
      // 周期归集：按「归属期」取明细/合计/统计（F5 阶段 3 起才会被查询用到）
      'CREATE INDEX idx_txn_ledger_period ON txn (ledger_id, period_start)',
      'CREATE INDEX idx_txn_category ON txn (category_id)',
      'CREATE INDEX idx_txn_account ON txn (account_id)',
      // ★ 借贷流水按 debt_id 反查（借贷详情页、结清校验）。
      //   这条索引原先只在 `_addDebtTable`（**升级路径**）里建，
      //   于是「全新装机的库」一直缺它 —— 由 `schema_equivalence_test` 当场抓到。
      //   写成 IF NOT EXISTS 是为了与升级路径重复执行时也不报错。
      'CREATE INDEX IF NOT EXISTS idx_txn_debt ON txn (debt_id)',
      // ★ v9：把「同一周期同一天生成两条流水」变成物理不可能。
      //   `WHERE recurring_id IS NOT NULL` 是必需的，不是保险措施 ——
      //   SQLite 的唯一索引不比较 NULL，手工记的流水 `recurring_id` 全是 NULL，
      //   不加 WHERE 的话任意多条 NULL 组合都能插进去，等于没加。
      '''
      CREATE UNIQUE INDEX IF NOT EXISTS ux_txn_recurring_date
        ON txn (recurring_id, date) WHERE recurring_id IS NOT NULL''',

      '''
      CREATE TABLE budget (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id    INTEGER NOT NULL,
        period_start TEXT    NOT NULL,
        category_id  INTEGER,
        amount_cents INTEGER NOT NULL DEFAULT 0,
        UNIQUE (ledger_id, period_start, category_id)
      )''',

      // ★ v9：上面那条表级 UNIQUE 对 NULL 不生效 —— `category_id IS NULL` 表示
      //   「总预算」，而 NULL 彼此永不相等，于是同一账本同一期能插出多份总预算，
      //   「可用额度」的分母就不唯一了。这条部分唯一索引把总预算钉成一份。
      //   （分类预算已被表级 UNIQUE 覆盖，不需要再加一条等价的索引。）
      '''
      CREATE UNIQUE INDEX IF NOT EXISTS ux_budget_total
        ON budget (ledger_id, period_start) WHERE category_id IS NULL''',

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
    // 借贷往来表：DDL 只有一份，新建库和 v6→v7 升级共用
    await _createDebtTable(db);
  }

  /// 建 `debt` 表与索引（幂等）。
  ///
  /// 单独抽出来是因为它有两个调用点：全新安装（[_createSchema]）和
  /// 老库升级（[_addDebtTable]）。两处各抄一遍 DDL，改字段时必有一处漏掉。
  static Future<void> _createDebtTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id       INTEGER NOT NULL,
        -- out = 借出（别人欠我），in = 借入（我欠别人）
        direction       TEXT    NOT NULL,
        counterparty    TEXT    NOT NULL,
        -- 本金，单位「分」，与全项目一致
        amount_cents    INTEGER NOT NULL,
        account_id      INTEGER,
        date            TEXT    NOT NULL,
        due_date        TEXT,
        -- 借入时是否算进本期可用；借出恒为 0
        count_in_budget INTEGER NOT NULL DEFAULT 0,
        -- 非空 = 已结清（可能提前结清，所以显式存，不靠剩余金额推算）
        closed_at       TEXT,
        note            TEXT    NOT NULL DEFAULT '',
        created_at      TEXT    NOT NULL DEFAULT '',
        FOREIGN KEY (ledger_id) REFERENCES ledger(id) ON DELETE CASCADE
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_debt_ledger ON debt (ledger_id, closed_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_debt_due ON debt (ledger_id, due_date)',
    );
  }

  /// v6 → v7：建 `debt` 表 + `txn.debt_id`。
  ///
  /// 只加表和空列，**不动任何一笔交易**：老记录的 `debt_id` 全是 NULL，
  /// 「排除借贷流水」的统计条件对它们天然成立，行为与升级前完全一致。
  static Future<void> _addDebtTable(Database db) async {
    await _createDebtTable(db);
    // 升级测试造的是只含 ledger/category 的极简老库，没有 txn 表。
    // 真实的 v1 以上库一定有，这里只是不让简化库把升级整条打断。
    final hasTxn = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'txn'",
    );
    if (hasTxn.isEmpty) return;
    final cols = await db.rawQuery('PRAGMA table_info(txn)');
    if (!cols.any((c) => c['name'] == 'debt_id')) {
      await db.execute('ALTER TABLE txn ADD COLUMN debt_id INTEGER');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_txn_debt ON txn (debt_id)',
    );
  }

  /// v7 → v8：`account` 增加 `opening_cents`（期初 / 手工校准值）。
  ///
  /// 为什么需要：余额一直是「用户手填的数字」和「流水增减的结果」混在一起的
  /// **同一个字段**。于是「余额对不对」这件事根本无法校验 —— 没有基准，
  /// 任何比对都会把用户手填的那部分当成漂移。把基准单独存一份之后，
  /// 余额变成 `opening_cents + 流水合计`，成了可重算、可对账的派生值：
  ///
  /// - 老库：按 `opening = 当前余额 − 流水合计` 回填，升级后**余额一分不变**，
  ///   而「数据体检」从第一次启动就能用；
  /// - 新库 / 新建账户：`opening` 默认 0，用户手填余额时同步写 opening。
  ///
  /// 幂等：只在真的新加了这一列之后回填（重复回填会把漂移"吃"进 opening，
  /// 等于把问题藏起来）。
  static Future<void> _addOpeningBalanceColumn(Database db) async {
    final hasAccount = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'account'",
    );
    if (hasAccount.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(account)');
    if (cols.any((c) => c['name'] == 'opening_cents')) return;

    await db.execute(
      'ALTER TABLE account ADD COLUMN opening_cents INTEGER NOT NULL DEFAULT 0',
    );

    // 没有 txn 表（测试造的极简库）就没有流水，opening 直接等于余额。
    final hasTxn = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'txn'",
    );
    if (hasTxn.isEmpty) {
      await db.execute('UPDATE account SET opening_cents = balance_cents');
      return;
    }

    // 回填公式必须与 `Repo._applyBalanceDelta` 逐字对应，
    // 否则升级完第一次体检就会报一堆假的"余额不一致"。
    await db.execute('''
      UPDATE account SET opening_cents = balance_cents - COALESCE((
        SELECT SUM(CASE
          WHEN t.type = 'income'                                THEN  t.amount_cents
          WHEN t.type = 'expense'                               THEN -t.amount_cents
          WHEN t.type = 'transfer' AND t.account_id    = account.id THEN -t.amount_cents
          WHEN t.type = 'transfer' AND t.to_account_id = account.id THEN  t.amount_cents
          ELSE 0 END)
        FROM txn t
        WHERE t.account_id = account.id OR t.to_account_id = account.id
      ), 0)
    ''');
  }

  /// v9：加两条部分唯一索引，把两类重复从「代码里挡」改成「物理上不可能」。
  ///
  /// 顺序必须是**先清存量重复、再建索引**：老库若已存在重复行，直接
  /// `CREATE UNIQUE INDEX` 会让整条迁移抛异常，用户看到的是启动页打不开。
  ///
  /// 两类重复的代价完全不同，所以处理方式也必须不同：
  /// - **周期流水**：重复生成的那条，钱已经记进余额了，**绝不能删**。只把多余那条
  ///   的 `recurring_id` 置 NULL —— 它降级成一笔普通流水，余额、统计、明细全不变，
  ///   只是不再被「周期」认领。每组保留 id 最小的一条作为周期归属。
  /// - **总预算**：预算是设置项不是账目，重复的两条最终只有一份生效，
  ///   保留 id 最大（最近一次设置）的一条。
  ///
  /// 幂等：两张表都先探测存在再操作（测试会造只含单表的极简库），
  /// 索引一律 `IF NOT EXISTS`，重复执行不报错。
  static Future<void> _addUniqueIndexes(Database db) async {
    final hasTxn = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'txn'",
    );
    if (hasTxn.isNotEmpty) {
      await db.execute('''
        UPDATE txn SET recurring_id = NULL
        WHERE recurring_id IS NOT NULL
          AND id NOT IN (
            SELECT MIN(id) FROM txn
            WHERE recurring_id IS NOT NULL
            GROUP BY recurring_id, date
          )
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS ux_txn_recurring_date
          ON txn (recurring_id, date) WHERE recurring_id IS NOT NULL
      ''');
    }

    final hasBudget = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'budget'",
    );
    if (hasBudget.isNotEmpty) {
      await db.execute('''
        DELETE FROM budget
        WHERE category_id IS NULL
          AND id NOT IN (
            SELECT MAX(id) FROM budget
            WHERE category_id IS NULL
            GROUP BY ledger_id, period_start
          )
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS ux_budget_total
          ON budget (ledger_id, period_start) WHERE category_id IS NULL
      ''');
    }
  }

  /// 首次安装的默认数据：一个账本、几个常用账户、原型里的全套分类。
  ///
  /// **不预置任何交易记录** —— 账本应该从用户自己的第一笔开始。
  ///
  /// 参数是 [DatabaseExecutor] 而不是 `Database`：清空数据时它要在**事务里**
  /// 重建（见 [wipeAllData]），事务对象同样满足这个接口。
  ///
  /// 写 setting 一律用 [ConflictAlgorithm.replace]：这个函数会被「首次建库」和
  /// 「清空重建」两条路径共用，后者库里的 setting 还在（当前账本、实验开关、
  /// 各种「提示只出一次」的标记），直接 insert 会撞 `k` 主键。
  /// 覆盖是对的：账本 id 变了，「当前账本」必须跟着换。
  static Future<void> _seed(DatabaseExecutor db) async {
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

    await seedCategories(db, ledgerId);

    for (final (k, v) in [
      ('current_ledger_id', '$ledgerId'),
      ('app_name', '黑塔消费日记'),
      ('schema_ready', '1'),
    ]) {
      await db.insert('setting', {
        'k': k,
        'v': v,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// 默认分类 —— 全部来自 `category_seed.dart`，这里不写死任何一个分类名。
  ///
  /// 两级结构：先插一级（`parent_id` 为空），再挂子分类。
  /// `sort_order` 在每一层内部各自从 0 开始 —— 查询时按父级分组取，
  /// 一级与子级的编号互不干扰。
  ///
  /// **公开**给 `Repo.insertLedger` 用：新建账本必须和首启账本长得一模一样，
  /// 抄第二份分类表的下场就是「新建账本只有一级、选不到正餐/地铁」。
  static Future<void> seedCategories(
    DatabaseExecutor db,
    int ledgerId,
  ) async {
    await _seedGroup(db, ledgerId, 'expense', kExpenseSeed);
    await _seedGroup(db, ledgerId, 'income', kIncomeSeed);
  }

  static Future<void> _seedGroup(
    DatabaseExecutor db,
    int ledgerId,
    String type,
    List<SeedCat> cats,
  ) async {
    for (var i = 0; i < cats.length; i++) {
      final cat = cats[i];
      final parentId = await db.insert('category', {
        'ledger_id': ledgerId,
        'type': type,
        'name': cat.name,
        'icon': cat.icon,
        'parent_id': null,
        'sort_order': i,
        'archived': 0,
      });
      for (var j = 0; j < cat.subs.length; j++) {
        final sub = cat.subs[j];
        await db.insert('category', {
          'ledger_id': ledgerId,
          'type': type,
          'name': sub.name,
          'icon': sub.icon,
          'parent_id': parentId,
          'sort_order': j,
          'archived': 0,
        });
      }
    }
  }

  /// 老用户升级时补齐后来新增的收入分类。
  ///
  /// 三条纪律：
  /// 1. **按「账本 + 类型 + 名称」查重**：用户可能早早自建了同名分类，
  ///    直接 insert 会出现两个「提成」，在筛选和统计里各算一半。
  /// 2. **紧跟「奖金」**：工资 / 奖金 / 提成 都属于劳动所得，视觉上应该相邻。
  ///    插到末尾会跟「兼职 / 理财 / 红包」混在一起，看起来像另一类东西。
  /// 3. **实在找不到锚点就排到最后**：收入分类的 sort_order 是独立编号的
  ///    （expense / income 各自从 0 开始，同账本内有重复值），所以 UPDATE
  ///    必须限定 type，否则会把支出分类一起往后推。
  static Future<void> _addMissingIncomeCategories(Database db) async {
    // 迁移链是多版本叠加的：从 v1 直接升上来时，中间版本建的表不一定齐
    // （单测里就有只建 txn_template 的库）。缺表就跳过，别让整个升级抛异常
    // —— 那会让 App 在启动阶段直接打不开，比少一个分类严重得多。
    final hasTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ledger'",
    );
    if (hasTable.isEmpty) return;

    const added = [('提成', 'bonus')];
    final ledgers = await db.query('ledger', columns: ['id']);
    for (final row in ledgers) {
      final ledgerId = row['id'] as int;
      for (final (name, icon) in added) {
        final dup = await db.query(
          'category',
          columns: ['id'],
          where: 'ledger_id = ? AND type = ? AND name = ?',
          whereArgs: [ledgerId, 'income', name],
          limit: 1,
        );
        if (dup.isNotEmpty) continue;

        // 锚点：奖金（插在它后面）> 其他（插在它前面）> 末尾
        int? anchor;
        for (final (key, after) in const [('奖金', true), ('其他', false)]) {
          final hit = await db.query(
            'category',
            columns: ['sort_order'],
            where: 'ledger_id = ? AND type = ? AND name = ?',
            whereArgs: [ledgerId, 'income', key],
            limit: 1,
          );
          if (hit.isNotEmpty) {
            anchor = (hit.first['sort_order'] as int) + (after ? 1 : 0);
            break;
          }
        }

        final int order;
        if (anchor != null) {
          // 「其他」当前占着这个位子，往后让一格；提到奖金后面时同理
          order = anchor;
          await db.execute(
            "UPDATE category SET sort_order = sort_order + 1 "
            "WHERE ledger_id = ? AND type = 'income' AND sort_order >= ?",
            [ledgerId, anchor],
          );
        } else {
          final maxRow = await db.rawQuery(
            "SELECT MAX(sort_order) AS m FROM category "
            "WHERE ledger_id = ? AND type = 'income'",
            [ledgerId],
          );
          order = ((maxRow.first['m'] as int?) ?? -1) + 1;
        }

        await db.insert('category', {
          'ledger_id': ledgerId,
          'type': 'income',
          'name': name,
          'icon': icon,
          'sort_order': order,
          'archived': 0,
        });
      }
    }
  }

  /// v3 → v4：`txn` 加归属期列 + 索引。
  ///
  /// **只加列，不改任何查询** —— 加完这一列，明细/合计/统计仍然按 `date` 走，
  /// 行为 100% 与 v3 相同。回填也不在这里做：算归属期要读 `cycle_start_day`
  /// 设置和分类白名单，交给 `Repo.backfillMissingPeriods()` 在 `boot()` 里跑，
  /// 迁移代码保持「只动结构、不读业务数据」。
  ///
  /// 幂等 + 容错：缺表跳过、列已存在跳过、索引建过跳过。迁移链是多版本叠加的，
  /// 升级阶段抛异常会让 App 直接打不开，比少一列严重得多。
  static Future<void> _addPeriodStartColumn(Database db) async {
    final hasTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'txn'",
    );
    if (hasTable.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(txn)');
    final hasColumn = cols.any((c) => c['name'] == 'period_start');
    if (!hasColumn) {
      await db.execute('ALTER TABLE txn ADD COLUMN period_start TEXT');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_txn_ledger_period '
      'ON txn (ledger_id, period_start)',
    );
  }

  /// v4 → v5：`budget` 由自然月改成归属期（预算也按周期走）。
  ///
  /// 老数据是 `month`（`2026-10`），一行对应一期；账单日默认 1 时该期第一天
  /// 就是月初，所以 `month || '-01'` 是**无损**的一对一换算，不需要按金额合并。
  /// 结算口径变了，但钱没变、条数没变 —— 这是这次迁移唯一要保证的事。
  ///
  /// SQLite 不能改列名之外的约束，只能重建表：建新表 → 搬数据 → 删旧表 → 改名。
  /// 幂等：已有 `period_start` 列就直接返回。
  static Future<void> _moveBudgetToPeriod(Database db) async {
    final hasTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'budget'",
    );
    if (hasTable.isEmpty) return;

    final cols = await db.rawQuery('PRAGMA table_info(budget)');
    if (cols.any((c) => c['name'] == 'period_start')) return;

    await db.execute('''
      CREATE TABLE budget_v5 (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id    INTEGER NOT NULL,
        period_start TEXT    NOT NULL,
        category_id  INTEGER,
        amount_cents INTEGER NOT NULL DEFAULT 0,
        UNIQUE (ledger_id, period_start, category_id)
      )''');
    await db.execute('''
      INSERT INTO budget_v5 (id, ledger_id, period_start, category_id, amount_cents)
      SELECT id, ledger_id, month || '-01', category_id, amount_cents FROM budget
    ''');
    await db.execute('DROP TABLE budget');
    await db.execute('ALTER TABLE budget_v5 RENAME TO budget');
  }

  // ------------------------------------------------------------ v5 → v6

  /// 分类从「一层平铺」改为「一级 + 子分类」两级。
  ///
  /// 三条纪律：
  /// 1. **不动 `txn` 任何一行**，只加 4 个空列。老交易靠 `category_id` 被动
  ///    跟随分类改名；找不到对应子分类的记录留在父级，明细里显示为「未细分」。
  /// 2. **不猜**。不根据备注推断子分类、不合并重名分类。猜错比不猜更难发现。
  /// 3. **幂等**。全部按「账本 + 类型 + 父级 + 名字」查重，重复执行只会补充、
  ///    不会生成第二套分类。
  static Future<void> _migrateTwoLevelCategories(Database db) async {
    final hasTxn = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'txn'",
    );
    if (hasTxn.isNotEmpty) {
      final cols = await db.rawQuery('PRAGMA table_info(txn)');
      for (final f in TxnField.values) {
        if (cols.any((c) => c['name'] == f.column)) continue;
        await db.execute('ALTER TABLE txn ADD COLUMN ${f.column} TEXT');
      }
    }

    final hasCat = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'category'",
    );
    if (hasCat.isEmpty) return;

    // 老库（v1 起）本来就有 parent_id；万一遇到被裁剪过的库，补上再继续
    final catCols = await db.rawQuery('PRAGMA table_info(category)');
    if (!catCols.any((c) => c['name'] == 'parent_id')) {
      await db.execute('ALTER TABLE category ADD COLUMN parent_id INTEGER');
    }

    final ledgers = await db.query('ledger', columns: ['id']);
    for (final row in ledgers) {
      final ledgerId = row['id'] as int;

      // 先降级再补齐。反过来的话，_syncGroup 会先建一个同名子分类，
      // 老的那个一级分类就留在外面成了孤儿（同一件事两个分类）
      for (final d in kDemotedCats) {
        await _demoteCategory(db, ledgerId, d);
      }
      await _syncGroup(db, ledgerId, 'expense', kExpenseSeed);
      await _syncGroup(db, ledgerId, 'income', kIncomeSeed);
    }
  }

  /// 按「账本 + 类型 + 名字 + 父级」找一个分类，返回 id。
  /// [topOnly] 为 true 时只在一级里找（`parent_id IS NULL`——
  /// SQLite 里 `parent_id = NULL` 永远不成立，必须单独写）。
  static Future<int?> _findCategory(
    Database db,
    int ledgerId,
    String type,
    String name, {
    int? parentId,
    bool topOnly = false,
  }) async {
    final rows = await db.query(
      'category',
      columns: ['id'],
      where: topOnly
          ? 'ledger_id = ? AND type = ? AND name = ? AND parent_id IS NULL'
          : 'ledger_id = ? AND type = ? AND name = ? AND parent_id = ?',
      whereArgs: topOnly
          ? [ledgerId, type, name]
          : [ledgerId, type, name, parentId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// 保证一级分类存在并返回 id：新名优先 → 历史名原地改名 → 都没有才新建。
  ///
  /// 「原地改名」是这次迁移能做到「不动交易」的关键：改的是 `category.name`，
  /// 交易的 `category_id` 指向没变，历史账目自动跟着新名字走。
  static Future<int> _ensureTopCategory(
    Database db,
    int ledgerId,
    String type,
    SeedCat cat,
  ) async {
    final hit = await _findCategory(
      db,
      ledgerId,
      type,
      cat.name,
      topOnly: true,
    );
    if (hit != null) {
      await db.update(
        'category',
        {'icon': cat.icon},
        where: 'id = ?',
        whereArgs: [hit],
      );
      return hit;
    }
    for (final legacy in cat.legacyNames) {
      final old = await _findCategory(
        db,
        ledgerId,
        type,
        legacy,
        topOnly: true,
      );
      if (old == null) continue;
      await db.update(
        'category',
        {'name': cat.name, 'icon': cat.icon},
        where: 'id = ?',
        whereArgs: [old],
      );
      return old;
    }
    return db.insert('category', {
      'ledger_id': ledgerId,
      'type': type,
      'name': cat.name,
      'icon': cat.icon,
      'parent_id': null,
      'sort_order': 0, // 稍后由 _normalizeTopOrder 统一重排
      'archived': 0,
    });
  }

  /// 老的一级分类原地降级成某个一级的子分类（改 `parent_id` + 改名）。
  static Future<void> _demoteCategory(
    Database db,
    int ledgerId,
    DemotedCat d,
  ) async {
    final seed = d.type == 'expense' ? kExpenseSeed : kIncomeSeed;
    final parent = seed.where((c) => c.name == d.parentName).firstOrNull;
    if (parent == null) return;

    // 老名已经不在一级了 = 之前跑过（或用户本来就没有），直接跳过。
    // 注意这里查的是**旧名**：幂等的关键，重跑时旧名已经变成子分类了。
    final old = await _findCategory(
      db,
      ledgerId,
      d.type,
      d.oldName,
      topOnly: true,
    );
    if (old == null) return;

    final parentId = await _ensureTopCategory(db, ledgerId, d.type, parent);
    await db.update(
      'category',
      {'name': d.newName, 'parent_id': parentId},
      where: 'id = ?',
      whereArgs: [old],
    );
  }

  /// 把种子里的两级结构同步进某个账本：缺什么补什么，已有的只刷新图标。
  static Future<void> _syncGroup(
    Database db,
    int ledgerId,
    String type,
    List<SeedCat> cats,
  ) async {
    for (final cat in cats) {
      final parentId = await _ensureTopCategory(db, ledgerId, type, cat);
      for (var i = 0; i < cat.subs.length; i++) {
        final sub = cat.subs[i];
        final hit = await _findCategory(
          db,
          ledgerId,
          type,
          sub.name,
          parentId: parentId,
        );
        if (hit == null) {
          await db.insert('category', {
            'ledger_id': ledgerId,
            'type': type,
            'name': sub.name,
            'icon': sub.icon,
            'parent_id': parentId,
            'sort_order': i,
            'archived': 0,
          });
        } else {
          // 已存在：只对齐图标和排序，**不碰 archived**
          // （用户主动归档过的子分类，迁移不该给他恢复出来）
          await db.update(
            'category',
            {'icon': sub.icon, 'sort_order': i},
            where: 'id = ?',
            whereArgs: [hit],
          );
        }
      }
    }
    await _normalizeTopOrder(db, ledgerId, type, cats);
  }

  /// 按种子顺序给一级分类重排 `sort_order`，用户自建的一级排到最后
  /// （彼此保持原来的相对顺序）。不这么做的话，改名保留下来的老分类
  /// 会带着旧编号，跟新补的分类编号撞在一起，顺序随 id 漂移。
  static Future<void> _normalizeTopOrder(
    Database db,
    int ledgerId,
    String type,
    List<SeedCat> cats,
  ) async {
    final rows = await db.query(
      'category',
      columns: ['id', 'name'],
      where: 'ledger_id = ? AND type = ? AND parent_id IS NULL',
      whereArgs: [ledgerId, type],
      orderBy: 'sort_order, id',
    );
    final index = <String, int>{
      for (var i = 0; i < cats.length; i++) cats[i].name: i,
    };
    var next = cats.length;
    for (final r in rows) {
      final name = r['name'] as String;
      final order = index[name] ?? next++;
      await db.update(
        'category',
        {'sort_order': order},
        where: 'id = ?',
        whereArgs: [r['id'] as int],
      );
    }
  }
}
