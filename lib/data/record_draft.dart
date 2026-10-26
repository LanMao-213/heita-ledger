import 'category_seed.dart';
import 'models.dart';

/// 保存一次记账时要做的事 —— **分支只由这一个枚举决定**。
///
/// 面板原来用两个布尔量（`_isLending` / `_isEdit`）在 `_save` 里嵌套判断，
/// 借贷分支还要提前 `return`。抽成枚举之后，「有几种存法」是一眼可见的，
/// 新增一种（比如转账）时也能让编译器提醒哪里有分支没覆盖。
enum RecordAction {
  /// 新记一笔
  insert,

  /// 改已有的一笔（原地刷新，不跳期）
  update,

  /// 借出 / 借入：建往来 + 本金流水，走另一条路径
  lend,
}

/// 记账面板的「草稿」：把表单值整理成待提交的结构。
///
/// ## 为什么值得单独一层
///
/// 面板的 `_save` 原先一手包办「读表单 → 判分支 → 拼 `Txn` → 调 Repo → 刷新」。
/// 其中**拼 `Txn` 是有真实规则的**：
/// - 编辑时必须保留 `id / createdAt / templateId / recurringId` —— 丢了
///   「改一笔」就变成「新记一笔」，`createdAt` 一刷新，列表排序也跟着乱；
/// - 借贷金额恒为正数，方向由 `type` 表示，不靠符号；
/// - 四个详情字段只写当前分类用得上的（裁剪规则在 `pruneDetails`）。
///
/// 这些规则原先只能靠点界面来验证。抽成不可变草稿之后，它们可以脱离 widget
/// 单测 —— 而这正是本轮把「保存」从 1,667 行面板里往外搬的第一步。
///
/// ## 边界
///
/// 它**不碰数据库，也不认识 `Store`**：写库与刷新由 UI 层按 [action]
/// 调对应的 Store 用例（`addTxn` / `updateTxn` / `addDebt`）。
/// 让草稿反过来依赖 Store 会把 `data → store` 这条反向依赖坐实，
/// 那是比「文件大」更贵的代价。
class RecordDraft {
  const RecordDraft({
    required this.ledgerId,
    required this.type,
    required this.amountCents,
    required this.date,
    required this.accountId,
    required this.categoryId,
    required this.note,
    required this.details,
    this.debt,
    this.editing,
    this.templateId,
  });

  final int ledgerId;
  final TxnType type;

  /// 借贷恒为正：方向看 [type]，不看符号
  final int amountCents;
  final String date;
  final int? accountId;
  final int? categoryId;
  final String note;

  /// 已按分类裁剪过的详情字段（`TxnField` → 文本）
  final Map<TxnField, String> details;

  /// 非空 = 借出/借入
  final Debt? debt;

  /// 非空 = 编辑
  final Txn? editing;

  /// 这次用到的模板（新增时记到账目上并累加使用次数）
  final int? templateId;

  RecordAction get action {
    if (debt != null) return RecordAction.lend;
    if (editing != null) return RecordAction.update;
    return RecordAction.insert;
  }

  /// 提交用的流水行。
  ///
  /// 借贷时也用它：本金流水与普通流水同构，只是额外挂了 `debt_id`
  /// （那一列由 `Repo.createDebt` 负责写，不在这里拼）。
  Txn toTxn() {
    final old = editing;
    return Txn(
      id: old?.id ?? 0,
      // 账本以老记录为准：编辑时即使中途切过账本，也不该把记录搬走
      ledgerId: old?.ledgerId ?? ledgerId,
      type: type,
      amountCents: amountCents,
      date: date,
      categoryId: categoryId,
      accountId: accountId,
      note: note,
      placeFrom: details[TxnField.from] ?? '',
      placeTo: details[TxnField.to] ?? '',
      person: details[TxnField.person] ?? '',
      subject: details[TxnField.subject] ?? '',
      // 编辑保留老模板：模板是「这笔当初从哪来」的溯源信息，不是本次输入
      templateId: old?.templateId ?? templateId,
      recurringId: old?.recurringId,
      // createdAt 缺失会让编辑后的记录重新排到列表最前
      createdAt: old?.createdAt ?? '',
    );
  }
}
