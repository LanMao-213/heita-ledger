#!/usr/bin/env bash
# 门禁 3：不许留下零调用的公共 widget。
#
# 规则（架构设计 §2.1 第 3 条）：lib/ui/widgets/** 里声明的公共 widget 类
# 必须在 lib/ 内被引用 ≥1 次。原版 `PeriodChip` 零调用点活到 1.4.5 的教训。
#
# 判定方式（粗检）：类名在 lib/ 下的出现次数 >= 2（声明 1 次 + 使用 ≥1 次）。
#
# 用法：bash tools/check_dead_public.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

if [ ! -d lib/ui/widgets ]; then
  echo "lib/ui/widgets 不存在，跳过（阶段 0 早期）"
  exit 0
fi

fail=0
count=0

while IFS= read -r file; do
  # 取 `class Xxx extends|with|implements` 与 `mixin Xxx on` 的公共名字
  names="$(grep -oE '^(abstract |final |sealed )?(class|mixin) ([A-Z][A-Za-z0-9_]*)' "$file" \
    | awk '{print $NF}' || true)"
  [ -n "$names" ] || continue
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    count=$((count + 1))
    n="$(grep -rn --include='*.dart' -w "$name" lib 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$n" -lt 2 ]; then
      echo "[FAIL] $file 里的 $name 在 lib/ 内没有调用点（只出现 $n 次）"
      fail=1
    fi
  done <<< "$names"
done < <(find lib/ui/widgets -name '*.dart' | sort)

if [ "$fail" -ne 0 ]; then
  echo "check_dead_public: 失败"
  exit 1
fi
echo "check_dead_public: OK（$count 个公共 widget 都有调用点）"
exit 0
