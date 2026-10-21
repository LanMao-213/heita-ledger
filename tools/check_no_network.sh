#!/usr/bin/env bash
# 门禁 1：不联网。
#
# 单机红线（架构设计 §1.1 末行）：不发起任何 HTTP 请求、不引统计/崩溃/广告 SDK、
# AndroidManifest 不声明 INTERNET 权限。命中任何一条即退出码 1。
#
# 用法：bash tools/check_no_network.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

fail=0

# 只扫 Dart 源码与 Android 清单；tools/ 自己是检查器，不参与。
DART_DIRS=(lib test)
MANIFESTS=(android/app/src/main/AndroidManifest.xml)

# 依赖名与 API 名。命中即网络依赖。
PATTERNS=(
  'package:http/'
  'package:dio/'
  'package:web_socket'
  'url_launcher'
  'HttpClient'
  'WebSocket'
  'Socket\.connect'
  'InternetAddress'
  'RawDatagramSocket'
)

for dir in "${DART_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  for pat in "${PATTERNS[@]}"; do
    hits="$(grep -rn --include='*.dart' -E "$pat" "$dir" 2>/dev/null | grep -v '^\s*//' || true)"
    if [ -n "$hits" ]; then
      echo "[FAIL] 发现网络 API「$pat」："
      echo "$hits"
      fail=1
    fi
  done
done

# AndroidManifest：不允许出现 INTERNET / ACCESS_NETWORK_STATE 权限。
for mf in "${MANIFESTS[@]}"; do
  [ -f "$mf" ] || continue
  # 只认 <uses-permission ...> 声明行，不看注释（注释里为了讲清红线会提到权限名）
  if grep -qE '<uses-permission[^>]*android:name="android\.permission\.(INTERNET|ACCESS_NETWORK_STATE)"' "$mf"; then
    echo "[FAIL] $mf 声明了网络权限（单机红线）："
    grep -nE '<uses-permission[^>]*android\.permission\.(INTERNET|ACCESS_NETWORK_STATE)' "$mf"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "check_no_network: 失败"
  exit 1
fi
echo "check_no_network: OK（无网络 API、无网络权限）"
exit 0
