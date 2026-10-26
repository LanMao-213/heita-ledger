import '../data/db.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../store.dart';

/// 是否为这个构建预置演示数据。
///
/// **编译期常量**，构建时用 `--dart-define=HEITA_SEED=1`（或 `true`）打开。正式包
/// 不带这个 define，`kSeedDemoData` 是 false，下面的分支被编译器整段消掉 —— 所以这段
/// 代码不会在用户装到的包里跑，也不会在店里看到「张三借了 5000」这种假账。
///
/// ⚠️ 不能写 `bool.fromEnvironment('HEITA_SEED')`：它只认字符串 `"true"` / `"false"`，
/// 传 `1` 会静默得到 false（踩过一次 —— 包打出来了，首页还是空的）。这里按字符串比。
const String _seedFlag = String.fromEnvironment('HEITA_SEED');
const bool kSeedDemoData = _seedFlag == '1' || _seedFlag == 'true';

/// 启动时调用：带 seed 的构建 + 库里一条流水都没有 → 灌一份演示数据。
///
/// 已有数据时**绝不覆盖** —— 真机上你已经开始记了，重装同版本包不该把账清掉。
Future<void> seedDemoDataIfNeeded() async {
  if (!kSeedDemoData) return;
  final db = await Db.open();
  final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM txn');
  if (((rows.first['n'] as int?) ?? 0) > 0) return;
  await seedDemoData(Store.i.ledgerId);
}

/// 演示数据本体。测试直接调这个（不经过 [kSeedDemoData] 开关）。
///
/// 覆盖要看的几块：两级分类、详情字段（出发地/对象/名称）、收入与预算、
/// 借贷的三种状态（未还、部分还、借入且计入预算、已逾期）。
Future<void> seedDemoData(int ledgerId) async {
  final s = Store.i;
  final now = DateTime.now();

  int? cat(String name) {
    for (final c in s.allExpenseCats) {
      if (c.name == name) return c.id;
    }
    for (final c in s.allIncomeCats) {
      if (c.name == name) return c.id;
    }
    return null;
  }

  // 本月第 d 天 / 上月第 d 天。取 1–18 号，任何月份都存在（不会撞到 2 月）
  String thisMonth(int day) => Fmt.date(DateTime(now.year, now.month, day));
  String lastMonth(int day) =>
      Fmt.date(DateTime(now.year, now.month - 1, day));
  String plusDays(int days) =>
      Fmt.date(DateTime(now.year, now.month, now.day + days));

  // ---------------------------------------------------------------- 账户
  //
  // **复用建库时已经种好的账户**（现金 / 支付宝 / 微信 / 储蓄卡）。
  // 第一版这里是直接 insertAccount，结果真机上「现金」出现了两行、「微信」两行，
  // 房租还把新建的那个现金账户刷成 -7000 —— 空账本看起来像出了 bug。
  // 只在同名账户不存在时才补建。
  Future<int> account(
    String name,
    AccountKind kind, {
    int initialCents = 0,
    int sortOrder = 0,
  }) async {
    for (final a in await Repo.listAccounts(includeArchived: true)) {
      if (a.name != name) continue;
      if (a.balanceCents != initialCents) {
        // 期初余额：只动余额，不动账户本身的名字/图标
        // 改的是「这个账户如今有多少钱」，必须走 saveAccount：
        // 它会反算期初，保持 余额 = 期初 + 流水 成立
        await Repo.saveAccount(
          Account(
            id: a.id,
            name: a.name,
            kind: a.kind,
            includeInTotal: a.includeInTotal,
            sortOrder: a.sortOrder,
            archived: a.archived,
          ),
          initialCents,
        );
      }
      return a.id;
    }
    return Repo.insertAccount(
      Account(
        id: 0,
        name: name,
        kind: kind,
        balanceCents: initialCents,
        sortOrder: sortOrder,
      ),
    );
  }

  // 微信留给日常小额，期初 5000；工资与房租走储蓄卡，账面不会出现负数
  final wechat = await account('微信', AccountKind.wechat, initialCents: 500000);
  final savings = await account('储蓄卡', AccountKind.debit, sortOrder: 2);

  // ---------------------------------------------------------------- 流水
  Future<void> spend(
    String date,
    String category, {
    required int cents,
    int? account,
    String note = '',
    String? from,
    String? to,
    String? person,
    String? subject,
  }) => Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.expense,
      amountCents: cents,
      date: date,
      categoryId: cat(category),
      accountId: account ?? wechat,
      note: note,
      placeFrom: from,
      placeTo: to,
      person: person,
      subject: subject,
    ),
  );

  Future<void> earn(
    String date,
    String category,
    int cents, {
    String note = '',
    int? account,
  }) => Repo.insertTxn(
    Txn(
      id: 0,
      ledgerId: ledgerId,
      type: TxnType.income,
      amountCents: cents,
      date: date,
      categoryId: cat(category),
      accountId: account ?? wechat,
      note: note,
    ),
  );

  // 本月（工资与房租走储蓄卡，日常小额走微信）
  await earn(thisMonth(10), '月薪', 1500000, note: '10 月', account: savings);
  await spend(thisMonth(15), '房租房贷', cents: 350000, account: savings);
  await spend(thisMonth(3), '水电燃气', cents: 18600);
  await spend(thisMonth(18), '正餐', cents: 4800, note: '午饭');
  // 分类名必须是 category_seed.dart 里真实存在的子分类，否则 categoryId 是 null，
  // 明细里会显示「未分类」。测试里有断言兜这个（见 test/seed_test.dart）
  await spend(thisMonth(18), '正餐', cents: 3200, note: '加班点的外卖');
  await spend(
    thisMonth(17),
    '打车',
    cents: 2600,
    from: '公司',
    to: '家',
    note: '下雨',
  );
  await spend(thisMonth(17), '公共交通', cents: 600, from: '家', to: '公司');
  await spend(thisMonth(16), '日用百货', cents: 8900, note: '纸巾洗衣液');
  await spend(
    thisMonth(14),
    '送礼',
    cents: 29900,
    person: '张三',
    note: '生日礼物',
  );
  await spend(thisMonth(13), '书籍', cents: 9900, subject: '代码大全');
  await spend(thisMonth(12), '药品', cents: 4500);
  await spend(thisMonth(11), '话费网费', cents: 9900);
  await spend(thisMonth(9), '电影演出', cents: 8000, note: '两张');
  await spend(thisMonth(6), '聚餐', cents: 24000, note: '同事聚餐');
  await spend(thisMonth(5), '加油充电', cents: 30000);

  // 上月（让统计页的月度对比、饼图都有东西看）
  await earn(lastMonth(10), '月薪', 1500000, note: '9 月', account: savings);
  await spend(lastMonth(15), '房租房贷', cents: 350000, account: savings);
  await spend(lastMonth(18), '正餐', cents: 5200);
  await spend(lastMonth(12), '服饰鞋包', cents: 39900, note: '外套');
  await spend(
    lastMonth(7),
    '打车',
    cents: 3100,
    from: '家',
    to: '机场',
    note: '赶飞机',
  );
  await spend(lastMonth(4), '会员订阅', cents: 2500, note: '视频会员');

  // ---------------------------------------------------------------- 预算
  // 总预算挂在「本期」上：预算按月/周期存，取 Store 算好的 cycleFrom
  final period = s.cycleFrom.isEmpty ? Fmt.month(now) : s.cycleFrom;
  await Repo.setBudget(
    ledgerId: ledgerId,
    periodStart: period,
    amountCents: 600000,
  );
  await Repo.setBudget(
    ledgerId: ledgerId,
    periodStart: period,
    categoryId: cat('餐饮'),
    amountCents: 150000,
  );
  await Repo.setBudget(
    ledgerId: ledgerId,
    periodStart: period,
    categoryId: cat('居家'),
    amountCents: 400000,
  );

  // ---------------------------------------------------------------- 借贷
  Future<int> lend({
    required String who,
    required DebtDirection dir,
    required int cents,
    required String date,
    String? due,
    bool inBudget = false,
    String note = '',
  }) => Repo.createDebt(
    Debt(
      id: 0,
      ledgerId: ledgerId,
      direction: dir,
      counterparty: who,
      amountCents: cents,
      date: date,
      accountId: wechat,
      dueDate: due,
      countInBudget: inBudget,
      note: note,
    ),
    Txn(
      id: 0,
      ledgerId: ledgerId,
      // 方向由 Repo 按借贷方向覆盖，这里给支出只是占位
      type: TxnType.expense,
      amountCents: cents,
      date: date,
      accountId: wechat,
      note: note,
    ),
  );

  // 部分还款：还 2000，剩 3000，用来验「已还 / 剩余 / 净应收」
  final zhang = await lend(
    who: '张三',
    dir: DebtDirection.lent,
    cents: 500000,
    date: thisMonth(4),
    due: plusDays(9),
    note: '垫付电脑',
  );
  await Repo.repayDebt(
    debt: (await Repo.listDebts(ledgerId: ledgerId))
        .firstWhere((d) => d.id == zhang),
    amountCents: 200000,
    accountId: wechat,
    date: thisMonth(16),
  );

  // 逾期：应还日已过 6 天，用来验往来页的「逾期 N 天」标红
  await lend(
    who: '李四',
    dir: DebtDirection.lent,
    cents: 120000,
    date: lastMonth(20),
    due: plusDays(-6),
    note: '房租周转',
  );

  // 借入且计入预算：验「可用金额含借入」与预算卡上的标注
  await lend(
    who: '王五',
    dir: DebtDirection.borrowed,
    cents: 300000,
    date: thisMonth(2),
    due: plusDays(21),
    inBudget: true,
    note: '装修先借的',
  );

  // ---------------------------------------------------------------- 模板
  await Repo.insertTemplate(
    TxnTemplate(
      id: 0,
      ledgerId: ledgerId,
      name: '午饭',
      icon: 'tpl',
      type: TxnType.expense,
      amountCents: 0,
      categoryId: cat('正餐'),
      accountId: wechat,
      note: '午饭',
    ),
  );
  await Repo.insertTemplate(
    TxnTemplate(
      id: 0,
      ledgerId: ledgerId,
      name: '打车回家',
      icon: 'taxi',
      type: TxnType.expense,
      amountCents: 0,
      categoryId: cat('打车'),
      accountId: wechat,
    ),
  );

  // 灌完把内存里的 Store 拉到最新，否则界面还停在「空账本」。
  // 不用手动 notify：这段跑在启动 future 里，HomeShell 的首帧在这之后才建。
  await s.afterTxnChange();
  // 模板列表也要拉一次：`afterTxnChange` 只重算当期投影，不碰模板。
  // 走 `loadTemplates()` 而不是给两个字段赋值 —— 后者在「结构整理」之后编译不过（字段已私有化）。
  await s.loadTemplates();
}
