#!/usr/bin/env bash
# 门禁 2：主题不许写死颜色。
#
# 规则（架构设计 §2.1 第 2 条）：
#   - lib/ui/ 下禁止 `Color(0x`、`Colors.`、`const TextStyle(color:`
#     —— 颜色只能来自 context.pal.*，否则切配色时那块不变（R4 的成因）
#   - lib/theme/ 之外禁止 `static const Color`
#
# 用法：bash tools/check_theme_hardcode.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

fail=0

if [ -d lib/ui ]; then
  for pat in 'Color\(0x' 'Colors\.' 'const TextStyle\(color:'; do
    hits="$(grep -rn --include='*.dart' -E "$pat" lib/ui 2>/dev/null | grep -vE '^\s*//' || true)"
    if [ -n "$hits" ]; then
      echo "[FAIL] lib/ui 下出现写死颜色「$pat」（必须走 context.pal.*）："
      echo "$hits"
      fail=1
    fi
  done
else
  echo "lib/ui 不存在，跳过（阶段 0 早期）"
fi

# lib/theme 之外禁止 static const Color。
hits="$(grep -rn --include='*.dart' -E 'static const Color ' lib 2>/dev/null \
  | grep -v '^lib/theme/' | grep -vE '^\s*//' || true)"
if [ -n "$hits" ]; then
  echo "[FAIL] lib/theme 之外出现 static const Color："
  echo "$hits"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "check_theme_hardcode: 失败"
  exit 1
fi
echo "check_theme_hardcode: OK（颜色全部来自 AppPalette）"
exit 0
