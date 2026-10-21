/// 两级分类的种子数据 —— **唯一的定义源**。
///
/// 建库播种、新建账本、分类管理页、图标总览都读这里，不允许在别处再抄一份分类名。
/// 抄两份的下场是「数据库里叫出行、界面上叫交通」。
///
/// 结构约束（与 repo 层的两级硬校验一致）：
/// - 只有两级：[SeedCat] 是一级，[SeedSub] 挂在它下面，**不允许再深**
/// - 交易的 `category_id` 可以指向任意一级，指向一级 = 这笔没细分
///
/// 分类名与图标照抄原版 `lib/data/category_seed.dart`（用户定稿的 2026-10 体系），
/// 数量是硬指标，被 `test/data/seed_test.dart` 钉住：
/// **支出 9 一级 / 49 子；收入 6 一级 / 24 子。**
library;

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'schema.dart';

/// 一个子分类：名称 + 图标 + 需要额外记录的字段（可空）。
class SeedSub {
  const SeedSub(this.name, this.icon, {this.fields = const <TxnField>[]});

  final String name;
  final String icon;
  final List<TxnField> fields;

  bool get hasFields => fields.isNotEmpty;
}

/// 一个一级分类。
class SeedCat {
  const SeedCat(
    this.name,
    this.icon,
    this.subs, {
    this.legacyNames = const <String>[],
  });

  final String name;
  final String icon;
  final List<SeedSub> subs;

  /// 历史名字。迁移旧备份时新名找不到、旧名找到了，就**原地改名**
  /// （不动交易的 `category_id`），这样老账目自动跟着新名字走。
  /// 不写在这里的名字等于「没有历史包袱」。
  final List<String> legacyNames;
}

/// 老的一级分类降级成子分类的映射。
///
/// 和改名不同：这类分类在旧库里是一级、在新表里是别人的子级 —— 必须原地改
/// `parent_id`，否则历史交易会挂在一个「已经不该存在的层级」上。
class DemotedCat {
  const DemotedCat(this.type, this.oldName, this.parentName, this.newName);

  /// `'expense'` / `'income'`。
  final String type;

  /// 旧库里的一级分类名。
  final String oldName;

  /// 新体系里的父级名（必须是一级）。
  final String parentName;

  /// 新体系里的子分类名。
  final String newName;
}

/// 旧备份导入 / 老库升级时用的降级表。
const List<DemotedCat> kDemotedCats = <DemotedCat>[
  // 话费宽带是每月固定支出，但用户定稿的「居家」里没有它的位置，
  // 于是降级成居家的第 7 个子分类 —— 历史话费记录一条都不用改
  DemotedCat('expense', '通讯', '居家', '话费网费'),
  // 收入侧：v3 补进来的「提成」和「奖金」本质相同，收进奖金当子分类，
  // 顺带解决两者图标撞车（都曾是 bonus）
  DemotedCat('income', '提成', '奖金', '提成'),
];

/// 支出：9 个一级 / 49 个子分类。
///
/// 两条已经过用户确认的取舍：
/// - 「借款」「代付」不在这里：借出去的钱不是消费，记成支出会让当月支出虚高、
///   预算失效，改用「借贷往来 + 借出账户」。
/// - 「通讯」不在这里：由迁移脚本把老「通讯」降级为「居家 / 话费网费」。
const List<SeedCat> kExpenseSeed = <SeedCat>[
  SeedCat('餐饮', 'utensils', [
    SeedSub('正餐', 'spoon'),
    SeedSub('食材', 'basket'),
    SeedSub('饮品', 'cup'),
    SeedSub('零食', 'snack'),
    SeedSub('烟酒', 'wine'),
    SeedSub('聚餐', 'group'),
  ]),
  SeedCat(
    '出行',
    'transport',
    [
      SeedSub('公共交通', 'transport', fields: [TxnField.from, TxnField.to]),
      SeedSub('打车', 'taxi', fields: [TxnField.from, TxnField.to]),
      SeedSub('加油充电', 'fuel'),
      SeedSub('停车过路', 'parking'),
      SeedSub('共享单车', 'bike'),
      SeedSub('车辆养护', 'car'),
    ],
    legacyNames: ['交通'],
  ),
  SeedCat(
    '居家',
    'home',
    [
      SeedSub('房租房贷', 'key'),
      SeedSub('水电燃气', 'drop'),
      SeedSub('物业', 'building'),
      SeedSub('日用百货', 'shopping'),
      SeedSub('家居家电', 'sofa'),
      SeedSub('维修保洁', 'wrench'),
      // 第 7 项：老「通讯」分类的落脚点。用户定稿时只列了 6 个，但话费宽带
      // 是每月固定支出，删掉会让历史记录无处可去（只能落到父级变成未细分）
      SeedSub('话费网费', 'comm'),
    ],
    legacyNames: ['居住'],
  ),
  SeedCat('购物', 'shopping', [
    SeedSub('服饰鞋包', 'shirt'),
    SeedSub('美妆个护', 'cosmetic'),
    SeedSub('数码电器', 'laptop'),
    SeedSub('母婴用品', 'baby'),
    SeedSub('宠物用品', 'paw'),
  ]),
  SeedCat(
    '健康',
    'medical',
    [
      SeedSub('医疗挂号', 'medical'),
      SeedSub('药品', 'pill'),
      SeedSub('体检', 'pulse'),
      SeedSub('口腔眼科', 'eye'),
      SeedSub('健身运动', 'dumbbell'),
      SeedSub('心理咨询', 'chat'),
    ],
    legacyNames: ['医疗'],
  ),
  SeedCat('娱乐', 'fun', [
    SeedSub('电影演出', 'film'),
    SeedSub('旅行度假', 'plane'),
    SeedSub('游戏充值', 'gamepad'),
    SeedSub('会员订阅', 'crown'),
    SeedSub('休闲玩乐', 'fun'),
  ]),
  SeedCat('人情', 'gift', [
    SeedSub('红包份子', 'redpacket', fields: [TxnField.person]),
    SeedSub('送礼', 'gift', fields: [TxnField.person]),
    SeedSub('请客招待', 'toast', fields: [TxnField.person]),
    SeedSub('孝敬长辈', 'elder', fields: [TxnField.person]),
    SeedSub('公益捐赠', 'heart', fields: [TxnField.person]),
  ]),
  SeedCat(
    '成长',
    'study',
    [
      SeedSub('课程培训', 'certificate', fields: [TxnField.subject]),
      SeedSub('书籍', 'book', fields: [TxnField.subject]),
      SeedSub('考试报名', 'doc'),
      SeedSub('知识付费', 'bulb'),
      SeedSub('工具软件', 'gear'),
    ],
    legacyNames: ['学习'],
  ),
  SeedCat('其他', 'more', [
    SeedSub('保险', 'shield'),
    SeedSub('手续费', 'percent'),
    SeedSub('罚款', 'alert'),
    SeedSub('不明支出', 'more'),
  ]),
];

/// 收入：6 个一级 / 24 个子分类。
const List<SeedCat> kIncomeSeed = <SeedCat>[
  SeedCat('工资', 'salary', [
    SeedSub('月薪', 'salary'),
    SeedSub('加班费', 'moon'),
    SeedSub('津贴补贴', 'coin'),
    SeedSub('补发工资', 'rec'),
  ]),
  SeedCat('奖金', 'bonus', [
    SeedSub('年终奖', 'bonus'),
    SeedSub('季度奖', 'calendar'),
    SeedSub('绩效奖金', 'chart'),
    SeedSub('提成', 'percent'),
  ]),
  SeedCat('兼职', 'parttime', [
    SeedSub('稿费', 'pen'),
    SeedSub('外包', 'parttime'),
    SeedSub('家教', 'board'),
    SeedSub('副业', 'coin'),
  ]),
  SeedCat('理财', 'invest', [
    SeedSub('利息', 'coin'),
    SeedSub('分红', 'pie'),
    SeedSub('基金收益', 'invest'),
    SeedSub('股票收益', 'chart'),
    SeedSub('房租收入', 'key'),
  ]),
  SeedCat('红包', 'redpacket', [
    SeedSub('压岁钱', 'redpacket'),
    SeedSub('过节红包', 'envelope'),
    SeedSub('礼金', 'gift'),
  ]),
  SeedCat('其他', 'more', [
    SeedSub('报销', 'receipt'),
    SeedSub('退款', 'rec'),
    SeedSub('卖二手', 'tag'),
    SeedSub('中奖', 'star'),
  ]),
];

/// 子分类名 → 需要额外记录的字段。
///
/// 键用**名字**而不是 id：种子每次建库都会重新分配 id，名字才是稳定标识，
/// 也才能被「用户能自己改名」的分类管理页共用。代价是用户把「公共交通」
/// 改成别的名字之后就不再有出发地/目的地 —— 他自己起的名字，我们猜不出
/// 要填什么。用户新建的分类不在表里 = 不要详情字段，这是刻意的默认。
final Map<String, List<TxnField>> kSubFieldSpecs = <String, List<TxnField>>{
  for (final SeedCat c in <SeedCat>[...kExpenseSeed, ...kIncomeSeed])
    for (final SeedSub s in c.subs)
      if (s.hasFields) s.name: s.fields,
};

/// 某个分类名需要填哪些详情字段（自建 / 已改名的分类返回空）。
List<TxnField> fieldsOfSub(String? name) {
  if (name == null) return const <TxnField>[];
  return kSubFieldSpecs[name] ?? const <TxnField>[];
}

/// 按分类过滤详情值：只保留 [fieldsOfSub] 认可的那几项，其余一律置空。
///
/// 字段是按**子分类名**绑定的，换分类之后控件里上一类残留的值必须丢掉 ——
/// 否则界面上看不见的「出发地」会跟着写进一笔买书。录入面板的「保存」和
/// 「切换分类」共用这一个规则，避免两处各写一遍、日后只改了一处。
///
/// 同一组字段的场景（公共交通 ⇄ 打车，都是出发地/目的地）不会被清掉，
/// 用户切错再切回来不用重填。
Map<TxnField, String> pruneDetails(
  String? subName,
  Map<TxnField, String> values,
) {
  final List<TxnField> active = fieldsOfSub(subName);
  return <TxnField, String>{
    for (final TxnField f in TxnField.values)
      f: active.contains(f) ? (values[f] ?? '').trim() : '',
  };
}

/// 这些子分类的详情**默认折叠**在「＋ 详情」里。
///
/// 分界线是信息量：地点两端多数人懒得填，常驻两行只是白占屏幕高度；
/// 而人情/成长的「对象、名称」正是这几类支出的核心信息 —— 记了红包份子
/// 却不知道给谁，这条记录基本没有价值，所以必须平铺、一眼可见。
const Set<String> kFoldedSubs = <String>{'公共交通', '打车'};

/// 播种结果。数字要能被测试直接断言，所以不返回 void。
class SeedResult {
  const SeedResult({
    required this.ledgerId,
    required this.topCount,
    required this.subCount,
  });

  final int ledgerId;

  /// 一级分类数（支出 9 + 收入 6 = 15）。
  final int topCount;

  /// 子分类数（支出 49 + 收入 24 = 73）。
  final int subCount;

  @override
  String toString() =>
      'SeedResult(ledger=$ledgerId, top=$topCount, sub=$subCount)';
}

/// 给某本账本灌入**完整两级**分类，返回一级/子分类计数。
///
/// 每一次「新建账本」都必须调它（原版 c-5/b-1 的坑就是新建账本只灌了旧的
/// 扁平 10/6 分类，且没有任何测试钉住，于是活到了 1.4.5）。
///
/// 幂等性由调用方保证（新账本才调）；本函数不查重 —— 查重会让「用户故意
/// 建两个同名分类」变成不可能。
Future<SeedResult> seedCategories(
  DatabaseExecutor db,
  int ledgerId,
) async {
  int topCount = 0;
  int subCount = 0;

  Future<void> seedType(String type, List<SeedCat> cats) async {
    int topOrder = 0;
    for (final SeedCat cat in cats) {
      final int topId = await db.insert(Tables.category, <String, Object?>{
        'ledger_id': ledgerId,
        'type': type,
        'name': cat.name,
        'icon': cat.icon,
        'parent_id': null,
        'sort_order': topOrder++,
        'archived': 0,
      });
      topCount++;

      int subOrder = 0;
      for (final SeedSub sub in cat.subs) {
        await db.insert(Tables.category, <String, Object?>{
          'ledger_id': ledgerId,
          'type': type,
          'name': sub.name,
          'icon': sub.icon,
          'parent_id': topId,
          'sort_order': subOrder++,
          'archived': 0,
        });
        subCount++;
      }
    }
  }

  await seedType('expense', kExpenseSeed);
  await seedType('income', kIncomeSeed);

  return SeedResult(
    ledgerId: ledgerId,
    topCount: topCount,
    subCount: subCount,
  );
}

/// 建库 / 清空 / 自愈时的**完整种子**：默认账本 + 默认账户 + 两级分类 + 必要设置。
///
/// 只在 `onCreate`、`wipeAllData`、以及「库里一本账本都没有」的自愈路径里调用。
/// `setting` 只写三个键，其余键（配色、触感）由 boot 序列读出来再决定要不要补默认值 ——
/// 播种不该覆盖用户偏好。
Future<SeedResult> seedFresh(DatabaseExecutor db, {String? nowIso}) async {
  final String now = nowIso ?? DateTime.now().toIso8601String();

  final int ledgerId = await db.insert(Tables.ledger, <String, Object?>{
    'name': '我的账本',
    'icon': 'book',
    'sort_order': 0,
    'created_at': now,
  });

  await db.insert(Tables.account, <String, Object?>{
    'name': '现金',
    'kind': 'cash',
    'opening_cents': 0,
    'balance_cents': 0,
    'include_in_total': 1,
    'sort_order': 0,
  });

  final SeedResult result = await seedCategories(db, ledgerId);

  await _putSetting(db, SettingKeys.currentLedgerId, '$ledgerId');
  await _putSetting(db, SettingKeys.cycleStartDay, '1');

  return result;
}

/// 写一个设置项（覆盖写）。只在播种与启动自愈里用；日常读写走 `SettingRepo`。
Future<void> _putSetting(DatabaseExecutor db, String key, String value) async {
  await db.insert(
    Tables.setting,
    <String, Object?>{'k': key, 'v': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
