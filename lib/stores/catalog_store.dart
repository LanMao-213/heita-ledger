import '../data/models/models.dart';
import '../data/repo/account_repo.dart';
import '../data/repo/category_repo.dart';
import '../data/repo/debt_repo.dart';
import '../data/repo/goal_repo.dart';
import '../data/repo/ledger_repo.dart';
import '../data/repo/template_repo.dart';
import '../data/services/summary_service.dart';
import 'shell_store.dart';

/// 账户 / 分类树 / 模板 / 目标 / 净资产。
///
/// 「一次查全」：切账本、启动、记一笔之后都要用这几样，分开查就是 4 次 IO
/// 加 4 次重建。
class CatalogStore extends StoreBase {
  CatalogStore();

  final AccountRepo _accounts = const AccountRepo();
  final CategoryRepo _categories = const CategoryRepo();
  final TemplateRepo _templates = const TemplateRepo();
  final GoalRepo _goals = const GoalRepo();
  final DebtRepo _debts = const DebtRepo();

  List<Account> _accountList = <Account>[];
  CategoryTree _tree = CategoryTree.empty;
  List<TxnTemplate> _templateList = <TxnTemplate>[];
  List<SavingGoal> _goalList = <SavingGoal>[];
  RepaidIndex _repaidIndex = RepaidIndex.empty;
  int _netWorthCents = 0;
  int _receivableCents = 0;
  int _payableCents = 0;
  bool _loaded = false;
  String _ledgerName = '';

  List<Account> get accounts => _accountList;
  CategoryTree get tree => _tree;
  List<TxnTemplate> get templates => _templateList;
  List<SavingGoal> get goals => _goalList;
  RepaidIndex get repaidIndex => _repaidIndex;

  /// 净资产 = Σ账户（计入净资产的）+ 应收 − 应付。
  int get netWorthCents => _netWorthCents;
  int get receivableCents => _receivableCents;
  int get payableCents => _payableCents;

  /// 是否已经加载过一次（首帧骨架判定用）。
  bool get loaded => _loaded;

  /// 当前账本名（明细页顶部显示）。
  String get ledgerName => _ledgerName;

  Account? accountById(int? id) {
    if (id == null) return null;
    for (final Account a in _accountList) {
      if (a.id == id) return a;
    }
    return null;
  }

  String accountName(int? id) => accountById(id)?.name ?? '未指定账户';

  /// 分类显示名（`餐饮 · 正餐`；未分类返回「未分类」）。
  String displayName(int? id) => _tree.displayName(id);

  /// 一次查全（账户 / 分类树 / 模板 / 目标 / 往来与净资产）。
  Future<void> loadCatalog(int ledgerId) async {
    await batchNotifyAsync<void>(() async {
      _ledgerIdForWrites = ledgerId;
      _ledgerName = (await const LedgerRepo().current())?.name ?? '';
      _accountList = await _accounts.list();
      _tree = CategoryTree(await _categories.all(ledgerId));
      _templateList = await _templates.all(ledgerId);
      _goalList = await _goals.all();
      _repaidIndex = await _debts.repaidIndex(ledgerId);
      final ({int receivable, int payable}) totals =
          await _debts.totals(ledgerId);
      _receivableCents = totals.receivable;
      _payableCents = totals.payable;
      _netWorthCents = SummaryService.netWorth(
        accounts: _accountList,
        receivableOverride: _receivableCents,
        payableOverride: _payableCents,
      );
      _loaded = true;
      notifyListeners();
    });
  }

  /// 只重算账户与净资产（记一笔/还款后不必重查分类树）。
  Future<void> reloadMoney() async {
    await batchNotifyAsync<void>(() async {
      _accountList = await _accounts.list();
      _netWorthCents = SummaryService.netWorth(
        accounts: _accountList,
        receivableOverride: _receivableCents,
        payableOverride: _payableCents,
      );
      notifyListeners();
    });
  }

  /// 只重查模板（模板页拖拽/删除后不必重查分类与账户）。
  Future<void> reloadTemplates() async {
    await batchNotifyAsync<void>(() async {
      _templateList = await _templates.all(_ledgerIdForWrites);
      notifyListeners();
    });
  }

  /// 只重查分类树（分类管理页改完/停用后调；预算候选与录入选择器都跟着变）。
  Future<void> reloadCategories() async {
    await batchNotifyAsync<void>(() async {
      _tree = CategoryTree(await _categories.all(_ledgerIdForWrites));
      notifyListeners();
    });
  }

  /// 当前账本 id（分类/模板写入要用）。
  int _ledgerIdForWrites = 0;

  /// 记住当前账本（`loadCatalog` 时写入，供页面层写库时取）。
  int get ledgerId => _ledgerIdForWrites;

  /// 新建 / 编辑储蓄目标（`id == null` 即新建）。写完立刻重查列表，1 次通知。
  Future<void> saveGoal(SavingGoal goal) async {
    await batchNotifyAsync<void>(() async {
      if (goal.id == null) {
        await _goals.insert(goal);
      } else {
        await _goals.update(goal);
      }
      _goalList = await _goals.all();
      notifyListeners();
    });
  }

  Future<void> deleteGoal(int id) async {
    await batchNotifyAsync<void>(() async {
      await _goals.delete(id);
      _goalList = await _goals.all();
      notifyListeners();
    });
  }

  /// 存钱（正数）/ 取钱（负数）。返回兜底后的已存金额。
  ///
  /// **不生成流水**：存钱不是支出，进了流水会把预算与统计一起污染。
  Future<int> addGoalFunds(int id, int deltaCents) async {
    late int saved;
    await batchNotifyAsync<void>(() async {
      saved = await _goals.addFunds(id, deltaCents);
      _goalList = await _goals.all();
      notifyListeners();
    });
    return saved;
  }
}
