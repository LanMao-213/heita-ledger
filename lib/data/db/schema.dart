/// schema v1 的**唯一定义源**：DDL、索引、列名清单。
///
/// 三条纪律（架构设计 §3.2）：
/// 1. 这里出现的每个列名都必须有写入口/读入口，**没有入口的列不建**
///    （原版 `txn.updated_at` / `ledger.archived` / `account.archived` /
///    `saving_goal.archived` 四个死列就是这么来的）。
/// 2. 金额列一律 `INTEGER`、单位**分**、列名以 `_cents` 结尾。
/// 3. 日期列一律 `TEXT`、格式 `YYYY-MM-DD`；月份 `YYYY-MM`；时刻 ISO8601 本地。
///
/// 四处「原版做不到、新库能做」的加强（都是踩过的坑）：
/// - `ux_txn_recurring_date` 部分唯一索引：补记重复从「三道闸都可能失效」变成物理不可能
/// - `ux_budget_total` / `ux_budget_cat` 部分唯一索引：表级 UNIQUE 对 NULL 不生效，
///   原版总预算因此可以插出多行，「可用额度」的分母不唯一
/// - `txn.period_start NOT NULL`：任何路径漏算归属期都会**插入失败**，
///   而不是悄悄消失在周期视图里
library;

/// 表名常量。repo 里不许出现裸字符串表名。
abstract final class Tables {
  static const String setting = 'setting';
  static const String ledger = 'ledger';
  static const String account = 'account';
  static const String category = 'category';
  static const String txn = 'txn';
  static const String budget = 'budget';
  static const String debt = 'debt';
  static const String recurring = 'recurring';
  static const String txnTemplate = 'txn_template';
  static const String savingGoal = 'saving_goal';

  /// 10 张表，**父表在前**：`replaceAll`（导入/恢复）按这个顺序 INSERT，
  /// 反过来会撞 `PRAGMA foreign_keys = ON`。
  static const List<String> all = <String>[
    setting,
    ledger,
    account,
    category,
    txn,
    budget,
    debt,
    recurring,
    txnTemplate,
    savingGoal,
  ];

  /// 清空顺序：**子表在前**。
  ///
  /// `setting` 故意不在名单里 —— 它只放机器状态与用户偏好（当前账本、配色、
  /// 触感开关），清账目不该顺手把「当前账本」抹成空。由 [seedFresh] 覆盖成新账本。
  static const List<String> wipeOrder = <String>[
    txn,
    budget,
    debt,
    recurring,
    txnTemplate,
    category,
    account,
    savingGoal,
    ledger,
  ];

  /// 业务表（不含 `setting`）。备份 dump / round-trip 断言用。
  static const List<String> business = <String>[
    ledger,
    account,
    category,
    txn,
    budget,
    debt,
    recurring,
    txnTemplate,
    savingGoal,
  ];
}

/// 全部 DDL 语句，按执行顺序排列。
///
/// **顺序不能乱**：索引语句必须在建表之后；`txn` 必须在 `ledger` 之后
/// （外键引用）。
const List<String> kSchemaStatements = <String>[
  // ---------------------------------------------------------------- setting
  '''
CREATE TABLE setting (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
)''',

  // ----------------------------------------------------------------- ledger
  '''
CREATE TABLE ledger (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT    NOT NULL,
  icon       TEXT    NOT NULL DEFAULT 'book',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT    NOT NULL
)''',

  // ---------------------------------------------------------------- account
  // 余额口径：balance_cents = opening_cents + 该账户流水合计（架构设计 §3.4）。
  // opening 是基准，任何自动流程不许改它 —— 否则「对不对」永远无法判定
  // （原版单列 balance 的病因）。
  '''
CREATE TABLE account (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  name             TEXT    NOT NULL,
  kind             TEXT    NOT NULL DEFAULT 'cash'
                   CHECK (kind IN ('cash','debit','credit','alipay','wechat','invest','other')),
  opening_cents    INTEGER NOT NULL DEFAULT 0,
  balance_cents    INTEGER NOT NULL DEFAULT 0,
  include_in_total INTEGER NOT NULL DEFAULT 1 CHECK (include_in_total IN (0,1)),
  sort_order       INTEGER NOT NULL DEFAULT 0
)''',

  // --------------------------------------------------------------- category
  '''
CREATE TABLE category (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  ledger_id  INTEGER NOT NULL REFERENCES ledger(id) ON DELETE CASCADE,
  type       TEXT    NOT NULL CHECK (type IN ('expense','income')),
  name       TEXT    NOT NULL,
  icon       TEXT    NOT NULL DEFAULT 'more',
  parent_id  INTEGER,
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived   INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0,1))
)''',
  'CREATE INDEX idx_category_ledger ON category (ledger_id, type, archived, sort_order)',
  'CREATE INDEX idx_category_parent ON category (parent_id)',

  // -------------------------------------------------------------------- txn
  // period_start 收紧为 NOT NULL（原版可空 → 新库不允许出现"没有归属期"的流水）。
  // updated_at 已删：原版 DDL 有、toMap 从不写、无人读 —— 死列。
  '''
CREATE TABLE txn (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  ledger_id     INTEGER NOT NULL REFERENCES ledger(id) ON DELETE CASCADE,
  type          TEXT    NOT NULL CHECK (type IN ('expense','income','transfer')),
  amount_cents  INTEGER NOT NULL,
  category_id   INTEGER,
  account_id    INTEGER,
  to_account_id INTEGER,
  date          TEXT    NOT NULL,
  period_start  TEXT    NOT NULL,
  note          TEXT    NOT NULL DEFAULT '',
  place_from    TEXT,
  place_to      TEXT,
  person        TEXT,
  subject       TEXT,
  debt_id       INTEGER,
  template_id   INTEGER,
  recurring_id  INTEGER,
  created_at    TEXT    NOT NULL
)''',
  // keyset 分页：ORDER BY date DESC, id DESC 的 WHERE 正好吃这条索引
  'CREATE INDEX idx_txn_ledger_date ON txn (ledger_id, date, id)',
  // 本期明细 / 本期合计
  'CREATE INDEX idx_txn_ledger_period ON txn (ledger_id, period_start, date, id)',
  'CREATE INDEX idx_txn_category ON txn (category_id)',
  'CREATE INDEX idx_txn_account ON txn (account_id)',
  'CREATE INDEX idx_txn_debt ON txn (debt_id)',
  'CREATE INDEX idx_txn_recurring ON txn (recurring_id, date)',
  // ★ 加强 ①：补记幂等的**最终保障**。原版建不了（老库已有重复行，建索引直接失败），
  // 新库从零开始，可以把它做成物理约束。
  '''
CREATE UNIQUE INDEX ux_txn_recurring_date ON txn (recurring_id, date)
  WHERE recurring_id IS NOT NULL''',

  // ----------------------------------------------------------------- budget
  // 预算按**归属期**存（不是自然月）。category_id IS NULL 表示总预算。
  '''
CREATE TABLE budget (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  ledger_id    INTEGER NOT NULL REFERENCES ledger(id) ON DELETE CASCADE,
  period_start TEXT    NOT NULL,
  category_id  INTEGER,
  amount_cents INTEGER NOT NULL DEFAULT 0
)''',
  // ★ 加强 ②：原版 UNIQUE(ledger_id,period_start,category_id) 对 NULL 无效，
  // 总预算能插出多行 → 「可用额度」的分母不唯一。用两条部分唯一索引各钉一件。
  '''
CREATE UNIQUE INDEX ux_budget_total ON budget (ledger_id, period_start)
  WHERE category_id IS NULL''',
  '''
CREATE UNIQUE INDEX ux_budget_cat ON budget (ledger_id, period_start, category_id)
  WHERE category_id IS NOT NULL''',

  // ------------------------------------------------------------------- debt
  // 本金必须 > 0；`repaid_cents` 是派生值，**不落库**（按 txn.debt_id 现算）。
  '''
CREATE TABLE debt (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  ledger_id       INTEGER NOT NULL REFERENCES ledger(id) ON DELETE CASCADE,
  direction       TEXT    NOT NULL CHECK (direction IN ('out','in')),
  counterparty    TEXT    NOT NULL,
  amount_cents    INTEGER NOT NULL CHECK (amount_cents > 0),
  account_id      INTEGER,
  date            TEXT    NOT NULL,
  due_date        TEXT,
  count_in_budget INTEGER NOT NULL DEFAULT 0 CHECK (count_in_budget IN (0,1)),
  closed_at       TEXT,
  note            TEXT    NOT NULL DEFAULT '',
  created_at      TEXT    NOT NULL
)''',
  'CREATE INDEX idx_debt_ledger ON debt (ledger_id, closed_at)',
  'CREATE INDEX idx_debt_due ON debt (ledger_id, due_date)',

  // -------------------------------------------------------------- recurring
  // interval / end_date 原版有列无入口（半套字段），新库补齐表单控件，
  // 因此这两列保留且必须真实生效。
  '''
CREATE TABLE recurring (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  ledger_id     INTEGER NOT NULL REFERENCES ledger(id) ON DELETE CASCADE,
  type          TEXT    NOT NULL CHECK (type IN ('expense','income')),
  amount_cents  INTEGER NOT NULL,
  category_id   INTEGER,
  account_id    INTEGER,
  note          TEXT    NOT NULL DEFAULT '',
  freq          TEXT    NOT NULL DEFAULT 'monthly'
                CHECK (freq IN ('daily','weekly','monthly','yearly')),
  interval      INTEGER NOT NULL DEFAULT 1 CHECK (interval BETWEEN 1 AND 12),
  next_run_date TEXT    NOT NULL,
  end_date      TEXT,
  enabled       INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1))
)''',
  'CREATE INDEX idx_recurring_next ON recurring (ledger_id, enabled, next_run_date)',

  // ----------------------------------------------------------- txn_template
  '''
CREATE TABLE txn_template (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  ledger_id    INTEGER NOT NULL REFERENCES ledger(id) ON DELETE CASCADE,
  name         TEXT    NOT NULL,
  icon         TEXT    NOT NULL DEFAULT 'tpl',
  type         TEXT    NOT NULL CHECK (type IN ('expense','income')),
  amount_cents INTEGER NOT NULL DEFAULT 0,
  category_id  INTEGER,
  account_id   INTEGER,
  note         TEXT    NOT NULL DEFAULT '',
  sort_order   INTEGER NOT NULL DEFAULT 0,
  use_count    INTEGER NOT NULL DEFAULT 0,
  last_used_at TEXT
)''',

  // ------------------------------------------------------------- saving_goal
  // 全局（跨账本）：储蓄目标跟着人走，不跟着账本走。
  '''
CREATE TABLE saving_goal (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  name         TEXT    NOT NULL,
  icon         TEXT    NOT NULL DEFAULT 'target',
  target_cents INTEGER NOT NULL DEFAULT 0,
  saved_cents  INTEGER NOT NULL DEFAULT 0 CHECK (saved_cents >= 0),
  due_month    TEXT,
  sort_order   INTEGER NOT NULL DEFAULT 0
)''',
];

/// 每张表的列名 → 声明类型。
///
/// **双向断言用**（`test/data/schema_test.dart`）：`PRAGMA table_info` 读回来的
/// 列名集合必须与这里完全相等 —— 缺一列（DDL 加了没登记）或多一列
/// （登记了但 DDL 没建）都是红。这条断言是「模型 `toMap` 漏列」的第一道网。
const Map<String, Map<String, String>> kTableColumns = <String, Map<String, String>>{
  Tables.setting: <String, String>{'k': 'TEXT', 'v': 'TEXT'},
  Tables.ledger: <String, String>{
    'id': 'INTEGER',
    'name': 'TEXT',
    'icon': 'TEXT',
    'sort_order': 'INTEGER',
    'created_at': 'TEXT',
  },
  Tables.account: <String, String>{
    'id': 'INTEGER',
    'name': 'TEXT',
    'kind': 'TEXT',
    'opening_cents': 'INTEGER',
    'balance_cents': 'INTEGER',
    'include_in_total': 'INTEGER',
    'sort_order': 'INTEGER',
  },
  Tables.category: <String, String>{
    'id': 'INTEGER',
    'ledger_id': 'INTEGER',
    'type': 'TEXT',
    'name': 'TEXT',
    'icon': 'TEXT',
    'parent_id': 'INTEGER',
    'sort_order': 'INTEGER',
    'archived': 'INTEGER',
  },
  Tables.txn: <String, String>{
    'id': 'INTEGER',
    'ledger_id': 'INTEGER',
    'type': 'TEXT',
    'amount_cents': 'INTEGER',
    'category_id': 'INTEGER',
    'account_id': 'INTEGER',
    'to_account_id': 'INTEGER',
    'date': 'TEXT',
    'period_start': 'TEXT',
    'note': 'TEXT',
    'place_from': 'TEXT',
    'place_to': 'TEXT',
    'person': 'TEXT',
    'subject': 'TEXT',
    'debt_id': 'INTEGER',
    'template_id': 'INTEGER',
    'recurring_id': 'INTEGER',
    'created_at': 'TEXT',
  },
  Tables.budget: <String, String>{
    'id': 'INTEGER',
    'ledger_id': 'INTEGER',
    'period_start': 'TEXT',
    'category_id': 'INTEGER',
    'amount_cents': 'INTEGER',
  },
  Tables.debt: <String, String>{
    'id': 'INTEGER',
    'ledger_id': 'INTEGER',
    'direction': 'TEXT',
    'counterparty': 'TEXT',
    'amount_cents': 'INTEGER',
    'account_id': 'INTEGER',
    'date': 'TEXT',
    'due_date': 'TEXT',
    'count_in_budget': 'INTEGER',
    'closed_at': 'TEXT',
    'note': 'TEXT',
    'created_at': 'TEXT',
  },
  Tables.recurring: <String, String>{
    'id': 'INTEGER',
    'ledger_id': 'INTEGER',
    'type': 'TEXT',
    'amount_cents': 'INTEGER',
    'category_id': 'INTEGER',
    'account_id': 'INTEGER',
    'note': 'TEXT',
    'freq': 'TEXT',
    'interval': 'INTEGER',
    'next_run_date': 'TEXT',
    'end_date': 'TEXT',
    'enabled': 'INTEGER',
  },
  Tables.txnTemplate: <String, String>{
    'id': 'INTEGER',
    'ledger_id': 'INTEGER',
    'name': 'TEXT',
    'icon': 'TEXT',
    'type': 'TEXT',
    'amount_cents': 'INTEGER',
    'category_id': 'INTEGER',
    'account_id': 'INTEGER',
    'note': 'TEXT',
    'sort_order': 'INTEGER',
    'use_count': 'INTEGER',
    'last_used_at': 'TEXT',
  },
  Tables.savingGoal: <String, String>{
    'id': 'INTEGER',
    'name': 'TEXT',
    'icon': 'TEXT',
    'target_cents': 'INTEGER',
    'saved_cents': 'INTEGER',
    'due_month': 'TEXT',
    'sort_order': 'INTEGER',
  },
};

/// 索引名 → (表名, 是否唯一)。`PRAGMA index_list` 断言用。
const Map<String, ({String table, bool unique})> kIndexes =
    <String, ({String table, bool unique})>{
  'idx_category_ledger': (table: Tables.category, unique: false),
  'idx_category_parent': (table: Tables.category, unique: false),
  'idx_txn_ledger_date': (table: Tables.txn, unique: false),
  'idx_txn_ledger_period': (table: Tables.txn, unique: false),
  'idx_txn_category': (table: Tables.txn, unique: false),
  'idx_txn_account': (table: Tables.txn, unique: false),
  'idx_txn_debt': (table: Tables.txn, unique: false),
  'idx_txn_recurring': (table: Tables.txn, unique: false),
  'ux_txn_recurring_date': (table: Tables.txn, unique: true),
  'ux_budget_total': (table: Tables.budget, unique: true),
  'ux_budget_cat': (table: Tables.budget, unique: true),
  'idx_debt_ledger': (table: Tables.debt, unique: false),
  'idx_debt_due': (table: Tables.debt, unique: false),
  'idx_recurring_next': (table: Tables.recurring, unique: false),
};
