import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/bill_csv.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/menu.dart';

/// 从支付宝 / 微信账单 CSV 导入。
///
/// ## 四步，但只有第二个界面
///
/// 选文件 → 解析 → **逐行过目** → 确认写入。中间不切页：
/// 预览就在这一页上完成，用户改的是同一份列表的勾选状态。
/// 之所以不拆成向导，是因为「来回翻页确认」在手机上最容易点错。
///
/// ## 三条口径，写死在实现里
///
/// 1. **余额不动**：写入走 `Repo.importBillRows`，它按账户反补期初
///    （详见该方法注释）。用户看到的是「历史补进来了，卡里的钱没变」。
/// 2. **收入行默认不算入**：账单里的「收入」经常是退款 / 转账 / 理财赎回，
///    混进收入会污染收支结构。默认不勾，但要给勾的入口（算入权）。
/// 3. **疑似重复只提示、不自动排除**：误删一笔真账用户很难发现。
class ImportBillPage extends StatefulWidget {
  const ImportBillPage({super.key, required this.ledgerId});

  final int ledgerId;

  @override
  State<ImportBillPage> createState() => _ImportBillPageState();
}

class _ImportBillPageState extends State<ImportBillPage> {
  List<Account> _accounts = const [];
  List<Category> _categories = const [];

  BillParseResult? _parsed;
  String _fileName = '';
  int? _accountId;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    final accounts = await Repo.listAccounts();
    final cats = await Repo.listCategories(widget.ledgerId);
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _categories = cats;
      _accountId = accounts.isNotEmpty ? accounts.first.id : null;
      _loading = false;
    });
  }

  // ------------------------------------------------------------------ 选文件

  Future<void> _pick() async {
    if (_busy) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      final bytes = File(path).readAsBytesSync();
      final parsed = BillCsv.parse(bytes);

      // 拉取账单日期范围内的已有记录做重复比对。
      // 用 basis: date —— 比对的是「哪天花的」，不是「算在哪一期」。
      final dates = parsed.importable.map((r) => r.date).toList()..sort();
      final existing = await Repo.rangeListTxns(
        ledgerId: widget.ledgerId,
        from: dates.first,
        to: dates.last,
        basis: DateBasis.date,
        limit: 2000,
      );
      BillCsv.markDuplicates(parsed.rows, existing);

      // 账户默认值：拿第一行的「收/付款方式」去猜，猜不中就用第一个账户
      final guess = _guessAccount(parsed.importable.isNotEmpty
          ? parsed.importable.first.payMethod
          : '');
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _fileName = path.split(Platform.pathSeparator).last;
        if (guess != null) _accountId = guess;
      });
    } on BillParseException catch (e) {
      if (mounted) {
        await showAppNotice(
          context,
          title: _errorTitle(e.error),
          message: e.message,
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '读取失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _guessAccount(String payMethod) {
    if (payMethod.isEmpty) return null;
    for (final a in _accounts) {
      if (payMethod.contains(a.name) || a.name.contains(payMethod)) return a.id;
    }
    if (payMethod.contains('支付宝')) {
      for (final a in _accounts) {
        if (a.name.contains('支付宝')) return a.id;
      }
    }
    if (payMethod.contains('微信')) {
      for (final a in _accounts) {
        if (a.name.contains('微信')) return a.id;
      }
    }
    return null;
  }

  /// 按「对方 + 商品说明」里的关键词猜一级分类。
  ///
  /// 猜不中就留空 → 落「未分类」，等用户在明细页批量改（T2 那条）。
  /// **绝不自动建分类**：分类带预算语义，被账单灌出一堆杂分类之后很难收拾。
  int? _guessCategory(BillRow r) {
    final text = '${r.counterparty} ${r.note}';
    const rules = <String, List<String>>{
      '餐饮': ['餐饮', '外卖', '美团', '饿了么', '星巴克', '瑞幸', '咖啡', '奶茶', '餐厅', '快餐', '食堂', '烧烤', '火锅'],
      '出行': ['交通', '打车', '滴滴', '地铁', '公交', '高铁', '火车', '机票', '加油', '停车', '单车'],
      '居家': ['房租', '物业', '水费', '电费', '燃气', '宽带', '家居', '家政'],
      '购物': ['购物', '淘宝', '京东', '拼多多', '天猫', '超市', '便利店', '商场', '服饰', '数码'],
      '健康': ['医疗', '医院', '药', '挂号', '体检', '诊所', '保健'],
      '娱乐': ['电影', '游戏', '娱乐', '会员', '视频', '音乐', '演出', 'KTV'],
      '人情': ['红包', '送礼', '请客', '份子', '礼金'],
      '成长': ['书店', '图书', '课程', '培训', '教育', '学费', '文具', '考试'],
    };
    for (final entry in rules.entries) {
      if (!entry.value.any(text.contains)) continue;
      for (final c in _categories) {
        if (c.parentId == null && c.type == r.type && c.name == entry.key) {
          return c.id;
        }
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ 写入

  Future<void> _import() async {
    final parsed = _parsed;
    if (parsed == null || _busy) return;
    final accountId = _accountId;
    if (accountId == null) {
      showToast(context, '先选一个账户');
      return;
    }

    final chosen = parsed.importable.where((r) => r.include).toList();
    if (chosen.isEmpty) {
      showToast(context, '一条都没勾选');
      return;
    }

    setState(() => _busy = true);
    try {
      final txns = <Txn>[
        for (final r in chosen)
          Txn(
            id: 0,
            ledgerId: widget.ledgerId,
            type: r.type,
            amountCents: r.amountCents,
            date: r.date,
            accountId: accountId,
            categoryId: _guessCategory(r),
            note: _noteFor(r),
          ),
      ];
      await Repo.importBillRows(txns: txns);
      await Store.i.afterTxnChange();
      if (!mounted) return;

      // 三个数字必须分开写：用户要能对上「我勾了多少、我排除了多少、
      // 系统因为重复帮我跳了多少」。合成一句「导入 87 条」等于把账算糊了。
      final manualExcluded = parsed.importable.length - chosen.length;
      final dupNote = parsed.importable
          .where((r) => r.suspectedDuplicate && !r.include)
          .length;

      await showAppNotice(
        context,
        title: '导入完成',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('算入 ${chosen.length} 条', style: T.body),
            if (manualExcluded > 0)
              Text('你没勾选 $manualExcluded 条', style: T.caption),
            if (parsed.skippedLines > 0)
              Text('账单里另有 ${parsed.skippedLines} 行不计收支 / 已关闭，未纳入',
                  style: T.caption),
            if (dupNote > 0)
              Text('其中 $dupNote 条标了疑似重复，已按你的选择排除', style: T.caption),
            const SizedBox(height: S.sm),
            Text('账户余额没有变化 —— 这些是历史账，钱早就花出去了。',
                style: T.caption),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showToast(context, '写入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 弹窗标题按原因分类。
  ///
  /// 标题先说「是什么问题」，正文再说「怎么解决」—— 用户扫一眼标题
  /// 就知道该不该继续读下去。
  static String _errorTitle(BillParseError e) {
    switch (e) {
      case BillParseError.notCsv:
        return '这不是 CSV 文件';
      case BillParseError.encodingGbk:
        return '编码不对（GBK）';
      case BillParseError.encodingUtf16:
        return '编码不对（UTF-16）';
      case BillParseError.encoding:
        return '编码不对';
      case BillParseError.header:
        return '认不出这份账单';
      case BillParseError.empty:
        return '没有可导入的记录';
    }
  }

  String _noteFor(BillRow r) {
    final parts = <String>[
      if (r.counterparty.isNotEmpty) r.counterparty,
      if (r.note.isNotEmpty) r.note,
    ];
    return parts.join(' · ');
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('从账单导入'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: LineIcon(
            'arrow_left',
            semanticLabel: '返回',
            size: 22,
            color: C.ink,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : parsed == null
          ? _IntroCard(busy: _busy, onPick: _pick)
          : Column(
              children: [
                _summary(parsed),
                _accountRow(),
                Expanded(child: _list(parsed)),
                _bottomBar(parsed),
              ],
            ),
    );
  }

  Widget _summary(BillParseResult p) {
    final dup = p.importable.where((r) => r.suspectedDuplicate).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.md),
      color: C.cardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.source.label} · $_fileName', style: T.section),
          const SizedBox(height: S.xs),
          // 编码与表头行号常驻显示：对用户是「文件被认出来了」，
          // 不是黑箱；对真机验证是数据来源（到底多少份账单是 GBK）。
          Text(
            '检测到 ${p.encoding.label}  ·  表头在第 ${p.headerLine} 行',
            style: T.caption.copyWith(color: C.ink3),
          ),
          const SizedBox(height: S.xs),
          Text(
            '可导入 ${p.importable.length} 条  ·  支出 ${Fmt.money(p.expenseTotalCents)}'
            '${p.incomeTotalCents > 0 ? '  ·  收入 ${Fmt.money(p.incomeTotalCents)}' : ''}',
            style: T.caption,
          ),
          if (dup > 0) ...[
            const SizedBox(height: S.xs),
            Text('有 $dup 条与已有记录相似，已标黄 —— 要不要算入由你定', style: T.caption.copyWith(color: C.over)),
          ],
          for (final w in p.warnings)
            Padding(
              padding: const EdgeInsets.only(top: S.xs),
              child: Text('· $w', style: T.caption.copyWith(color: C.ink3)),
            ),
        ],
      ),
    );
  }

  Widget _accountRow() {
    if (_accounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(S.lg),
        child: Text('还没有账户，先去「我的 → 账户」建一个再来。', style: T.caption),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.sm),
      decoration: BoxDecoration(
        color: C.bg2,
        border: Border(bottom: BorderSide(color: C.line, width: 1)),
      ),
      child: Row(
        children: [
          Text('算入账户', style: T.body2),
          const Spacer(),
          DropdownButton<int>(
            value: _accountId,
            underline: const SizedBox.shrink(),
            items: [
              for (final a in _accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name, style: T.body2)),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
        ],
      ),
    );
  }

  Widget _list(BillParseResult p) {
    final rows = p.importable;
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: C.line),
      itemBuilder: (context, i) {
        final r = rows[i];
        final selected = r.include;
        return InkWell(
          onTap: () => setState(() => r.include = !r.include),
          child: Container(
            color: r.suspectedDuplicate ? C.over.withValues(alpha: 0.06) : null,
            padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? C.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: selected ? C.ink : C.ink4, width: 1.2),
                  ),
                  child: selected
                      ? LineIcon('check', size: 14, color: C.onAccent)
                      : null,
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.summary,
                        style: T.body2.copyWith(
                          color: selected ? C.ink : C.ink3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${r.date}${r.time.isEmpty ? '' : ' ${r.time}'}'
                        '${r.payMethod.isEmpty ? '' : ' · ${r.payMethod}'}',
                        style: T.caption.copyWith(color: C.ink4),
                      ),
                      if (r.suspectedDuplicate)
                        Text(
                          '疑似与已有记录重复',
                          style: T.caption.copyWith(color: C.over),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: S.sm),
                Text(
                  '${r.type.isIncome ? '+' : '-'}${Fmt.money(r.amountCents)}',
                  style: T.amountSm.copyWith(color: selected ? C.ink : C.ink3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bottomBar(BillParseResult p) {
    final n = p.importable.where((r) => r.include).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.xl),
      decoration: BoxDecoration(
        color: C.cardBg,
        border: Border(top: BorderSide(color: C.line, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '已勾选 $n / ${p.importable.length} 条',
              style: T.caption,
            ),
          ),
          FilledButton(
            onPressed: _busy || n == 0 ? null : _import,
            child: Text(_busy ? '正在写入' : '算入 $n 条'),
          ),
        ],
      ),
    );
  }
}

/// 还没选文件时的说明页。
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.busy, required this.onPick});

  final bool busy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(S.lg),
      children: [
        Container(
          padding: const EdgeInsets.all(S.lg),
          decoration: BoxDecoration(
            color: C.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.line, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导入支付宝 / 微信账单', style: T.section),
              const SizedBox(height: S.sm),
              Text(
                '在支付宝里「我的 → 账单 → 导出账单」，或在微信里'
                '「我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单」，'
                '拿到 CSV 后在这里导入。',
                style: T.body2,
              ),
              const SizedBox(height: S.md),
              Text('导入会发生什么', style: T.body2.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: S.xs),
              Text('· 只补流水，账户余额不变（这些钱早就花出去了）', style: T.caption),
              Text('· 收入行默认不算入，需要你勾', style: T.caption),
              Text('· 相似记录会标黄提示，但不会自动排除', style: T.caption),
              Text('· 分类按对方名称猜，猜不中记为未分类', style: T.caption),
              const SizedBox(height: S.md),
              Text(
                '文件必须是 UTF-8 编码。支付宝导出的 GBK 文件请先用 Excel '
                '另存为「CSV UTF-8」——我们不硬解，乱码写进账本很难挑出来。',
                style: T.caption.copyWith(color: C.ink3),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.xxl),
        FilledButton(
          onPressed: busy ? null : onPick,
          child: Text(busy ? '正在读取' : '选择 CSV 文件'),
        ),
      ],
    );
  }
}
