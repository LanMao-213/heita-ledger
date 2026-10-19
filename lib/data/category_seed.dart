/// 两级分类的种子数据（2026-10 分类体系改造）。
///
/// **唯一的定义源**：建库播种、旧库迁移、分类管理页、图标总览图都读这里，
/// 不允许在别处再抄一份分类名 —— 抄两份的下场是「数据库里叫出行、界面上叫交通」。
///
/// 结构约束（与 repo 层校验一致）：
/// - 只有两级：本文件的 [SeedCat] 是一级，[SeedSub] 挂在它下面，不允许再深
/// - 交易的 `category_id` 可以指向任意一级，指向一级 = 这笔没细分
library;

/// 交易详情字段。挂到子分类上，全部选填。
///
/// 为什么是四个固定字段而不是 JSON / 属性表：
/// 这四类信息（地点两端、人、名称）需要能 `GROUP BY` 出「给某人花了多少」，
/// 塞进 JSON 就只能全表解析。代价是 4 列里经常有 3 列为空，SQLite 存 NULL 不心疼。
enum TxnField {
  from('出发地'),
  to('目的地'),
  person('对象'),
  subject('名称');

  const TxnField(this.label);

  /// 录入框上的中文标签
  final String label;

  /// 数据库列名。加字段时**只能往后加**，不能改名 —— 老库靠这个列名迁移。
  String get column => switch (this) {
    TxnField.from => 'place_from',
    TxnField.to => 'place_to',
    TxnField.person => 'person',
    TxnField.subject => 'subject',
  };
}

/// 一个子分类：名称 + 图标 + 需要额外记录的字段（可空）
class SeedSub {
  const SeedSub(this.name, this.icon, {this.fields = const []});

  final String name;
  final String icon;
  final List<TxnField> fields;

  bool get hasFields => fields.isNotEmpty;
}

/// 一个一级分类
class SeedCat {
  const SeedCat(this.name, this.icon, this.subs);

  final String name;
  final String icon;
  final List<SeedSub> subs;
}

/// 支出：9 个一级 / 48 个子分类
///
/// 两条已经过用户确认的取舍：
/// - 「借款」「代付」不在这里：借出去的钱不是消费，记成支出会让当月支出虚高、
///   预算失效，改用「转账 + 借出账户」。
/// - 「通讯」不在这里：话费和宽带并进「居家 / 水电燃气」之外的日用语义，
///   由迁移脚本把老「通讯」分类降级为「居家」的子分类。
const kExpenseSeed = <SeedCat>[
  SeedCat('餐饮', 'food', [
    SeedSub('正餐', 'food'),
    SeedSub('食材', 'basket'),
    SeedSub('饮品', 'cup'),
    SeedSub('零食', 'snack'),
    SeedSub('烟酒', 'wine'),
    SeedSub('聚餐', 'group'),
  ]),
  SeedCat('出行', 'transport', [
    SeedSub('公共交通', 'transport', fields: [TxnField.from, TxnField.to]),
    SeedSub('打车', 'taxi', fields: [TxnField.from, TxnField.to]),
    SeedSub('加油充电', 'fuel'),
    SeedSub('停车过路', 'parking'),
    SeedSub('共享单车', 'bike'),
    SeedSub('车辆养护', 'car'),
  ]),
  SeedCat('居家', 'home', [
    SeedSub('房租房贷', 'key'),
    SeedSub('水电燃气', 'drop'),
    SeedSub('物业', 'building'),
    SeedSub('日用百货', 'shopping'),
    SeedSub('家居家电', 'sofa'),
    SeedSub('维修保洁', 'wrench'),
  ]),
  SeedCat('购物', 'shopping', [
    SeedSub('服饰鞋包', 'shirt'),
    SeedSub('美妆个护', 'cosmetic'),
    SeedSub('数码电器', 'laptop'),
    SeedSub('母婴用品', 'baby'),
    SeedSub('宠物用品', 'paw'),
  ]),
  SeedCat('健康', 'medical', [
    SeedSub('医疗挂号', 'medical'),
    SeedSub('药品', 'pill'),
    SeedSub('体检', 'pulse'),
    SeedSub('口腔眼科', 'eye'),
    SeedSub('健身运动', 'dumbbell'),
    SeedSub('心理咨询', 'chat'),
  ]),
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
  SeedCat('成长', 'study', [
    SeedSub('课程培训', 'certificate', fields: [TxnField.subject]),
    SeedSub('书籍', 'book', fields: [TxnField.subject]),
    SeedSub('考试报名', 'doc'),
    SeedSub('知识付费', 'bulb'),
    SeedSub('工具软件', 'gear'),
  ]),
  SeedCat('其他', 'more', [
    SeedSub('保险', 'shield'),
    SeedSub('手续费', 'percent'),
    SeedSub('罚款', 'alert'),
    SeedSub('不明支出', 'more'),
  ]),
];

/// 收入：6 个一级 / 23 个子分类
const kIncomeSeed = <SeedCat>[
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
