part of '../bill_csv.dart';

// ---------------------------------------------------------------------------
// 重复判定（模糊打分 + 精确指纹幂等）
//
// 库私有（`part of` 与 `bill_csv.dart` 共享私有作用域）；对外只暴露
// `BillCsv.parse` / `parseAmount` / `parseDate` / `markDuplicates` 四个入口，
// 门面在 `bill_csv.dart` 里。
// ---------------------------------------------------------------------------

  /// 给每行和已有记录打分，标出「疑似重复」与「确定性重复」。
  ///
  /// ## 为什么不是「金额相等就算重复」
  ///
  /// 每天一杯 32 元的咖啡、每周一次 50 元的停车费 —— 金额天然会重复。
  /// 单靠金额判重，会把正常消费误判成重复账，而**误判的代价是不对称的**：
  /// 少导入一笔，用户丢的是钱；多导入一笔，用户随手删掉就行。
  ///
  /// ## 两档判据，各管一件事（不要合并成一套）
  ///
  /// | | 判据 | 用途 | 默认动作 |
  /// |---|---|---|---|
  /// | 确定性重复 | **日 + 分 + 对方** 三要素精确相等 | 挡"同一份账单导两次" | 不勾（可手动勾回） |
  /// | 疑似重复 | 多维打分 ≥ 55（金额/日期/方向/对方相似） | 提示"这两笔像不像同一笔" | 勾上（只标黄） |
  ///
  /// ★ 为什么确定性那一档必须**命中即抵扣**：库里有 1 笔「今天 32 元星巴克」，
  ///   文件里出现 2 笔同样的 —— 用户其实是上午下午各喝了一杯，只有 1 笔是旧的。
  ///   若用布尔集合，两行都会被判成"已存在"，第二笔真账就被默认排除了。
  ///   改成计数（命中一次减一），1 笔库记录只够认领 1 行，第 2 行回到正常态。
  ///   这就是"宁可漏报，不要误杀"的落点。
  ///
  /// ★ 指纹只取「日 + 分 + 对方」，**不取备注/商品**：备注常被用户手改，
  ///   同一个商家同一天同一金额才是幂等该认的边界；再放宽一定误杀。
void _markDuplicates(List<BillRow> rows, List<Txn> existing) {
  if (existing.isEmpty) return;

  // 按金额分桶：个人账本几千条，线性扫也够快，但分桶能让「同金额」先聚起来
  final byAmount = <int, List<Txn>>{};
  // 指纹桶：key → 还有几条库记录**没被认领**
  final fingerprint = <String, int>{};
  for (final t in existing) {
    byAmount.putIfAbsent(t.amountCents, () => []).add(t);
    final key = _fingerprintOf(t.date, t.amountCents, _counterpartyOf(t.note));
    if (key != null) fingerprint[key] = (fingerprint[key] ?? 0) + 1;
  }

  for (final r in rows) {
    if (r.skipped) continue;

    // --- 第一档：精确指纹 ---
    final key = _fingerprintOf(r.date, r.amountCents, r.counterparty);
    if (key != null) {
      final left = fingerprint[key] ?? 0;
      if (left > 0) {
        fingerprint[key] = left - 1;
        r.certainDuplicate = true;
        r.suspectedDuplicate = true;
        r.duplicateScore = 80;
        // 确定性重复默认不导入；用户仍可手动勾回来（算入权在他手上）
        r.include = false;
        continue;
      }
    }

    // --- 第二档：模糊打分（只提示，不改默认勾选）---
    var best = 0;
    final candidates = <Txn>[
      ...?byAmount[r.amountCents],
      // 差 1 元以内也算候选（账单四舍五入 / 手续费）
      for (final e in byAmount.entries)
        if ((e.key - r.amountCents).abs() <= 100) ...e.value,
    ];
    for (final t in candidates) {
      var score = 0;
      if (t.amountCents == r.amountCents) {
        score += 40;
      } else if ((t.amountCents - r.amountCents).abs() <= 100) {
        score += 20;
      }
      if (t.date == r.date) {
        score += 30;
      } else if (_dayGap(t.date, r.date) <= 1) {
        score += 20;
      }
      if (t.type == r.type) score += 10;
      if (t.accountId != null) score += 0; // 账户要等用户选定后才有意义
      final noteHit = r.counterparty.isNotEmpty &&
          t.note.isNotEmpty &&
          (t.note.contains(r.counterparty) || r.note.contains(t.note));
      if (noteHit) score += 10;
      if (score > best) best = score;
    }
    r.duplicateScore = best;
    r.suspectedDuplicate = best >= 55;
  }
}

  /// 指纹键：`日期|分值|对方`。对方为空时返回 null ——
  /// 没有对方信息的行（手填账单、部分微信条目）三要素就只剩两样，
  /// 拿它做幂等会误杀「同一天同金额的两笔不同消费」。
String? _fingerprintOf(String date, int amountCents, String party) {
  final p = party.trim();
  if (p.isEmpty) return null;
  return '$date|$amountCents|$p';
}

  /// 从库里的 `note` 反推「对方」。
  ///
  /// 导入时 note 的写法是 `对方 · 商品说明`（见 `import_bill_page._noteFor`），
  /// 所以第一个 ` · ` 之前那一段就是对方；没有分隔符时整串即对方。
  /// ★ 手工记账的行 note 是用户自己写的，反推出的"对方"未必是真对方 ——
  ///   这正是本档只做**默认不勾**、不做硬拦截的原因。
String _counterpartyOf(String note) {
  final i = note.indexOf(' · ');
  return (i < 0 ? note : note.substring(0, i)).trim();
}

int _dayGap(String a, String b) {
  final da = DateTime.tryParse(a);
  final db = DateTime.tryParse(b);
  if (da == null || db == null) return 999;
  return da.difference(db).inDays.abs();
}
