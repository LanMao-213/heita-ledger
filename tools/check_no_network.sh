#!/usr/bin/env bash
#
# 不联网门禁。
#
# 这个应用是**单机应用**：不联网、不接统计/崩溃上报/广告 SDK。这不是洁癖，
# 是华为应用市场的硬口径 —— 「断网后所有核心功能可用」才能勾「单机APP」免备案。
# 一旦悄悄混进一个会发请求的依赖或一行代码，这个资格就没了，而且不会有任何报错。
#
# 所以把这条从「注释里的约定」变成「构建时必须通过的检查」。
#
# 用法：
#   tools/check_no_network.sh                  # 检查依赖、源码、清单
#   tools/check_no_network.sh path/to/app.apk  # 额外检查打出来的 APK
#
# 退出码：0 = 通过，1 = 发现问题（CI 里直接红）

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAIL=0
fail() { printf '  ✗ %s\n' "$1"; FAIL=1; }
ok()   { printf '  ✓ %s\n' "$1"; }

echo "== 1/4 依赖白名单 =="

# 允许的运行时依赖。新增任何一个都要在这里显式登记 —— 想清楚它是否联网，
# 想不清楚就别加。这个列表故意写死，不做「从 pubspec 里读出来再对比」的自动同步：
# 那样等于自己给自己发许可。
ALLOWED_DEPS=(
  flutter
  flutter_localizations
  cupertino_icons
  sqflite
  path
  intl
  path_provider
  share_plus
  file_picker
  excel
)

in_deps=0
while IFS= read -r line; do
  case "$line" in
    "dependencies:") in_deps=1; continue ;;
    "dev_dependencies:") in_deps=0; continue ;;
    "") continue ;;
  esac
  [ "$in_deps" -eq 1 ] || continue
  # 只取顶格两空格的依赖名（`  foo: ^1.0.0`）
  name="$(printf '%s' "$line" | sed -n 's/^  \([a-z_][a-z0-9_]*\):.*/\1/p')"
  [ -n "$name" ] || continue
  hit=0
  for allowed in "${ALLOWED_DEPS[@]}"; do
    [ "$name" = "$allowed" ] && hit=1 && break
  done
  if [ "$hit" -eq 0 ]; then
    fail "未登记的运行时依赖：$name（先确认它不联网，再加进 ALLOWED_DEPS）"
  fi
done < pubspec.yaml
[ "$FAIL" -eq 0 ] && ok "运行时依赖都在白名单内（${#ALLOWED_DEPS[@]} 个）"

echo "== 2/4 源码里的网络调用 =="

# 允许 dart:io（本地文件读写要用），但禁止其中能发请求的那部分。
# 注释行先剔掉再匹配 —— 否则 db.dart 里那句「不发任何 HTTP 请求」的注释会误报。
FORBIDDEN='package:http/|HttpClient\(|HttpOverrides|dio\.|dio/|Socket\.connect|WebSocket|SecureSocket|url_launcher|NetworkImage|InternetAddress|\.getUrl\(|http\.get\(|http\.post\('

src_hits="$(find lib -name '*.dart' -type f -print0 \
  | xargs -0 grep -nE "$FORBIDDEN" 2>/dev/null \
  | grep -vE ':[0-9]+: *//' || true)"

if [ -n "$src_hits" ]; then
  while IFS= read -r line; do
    fail "网络调用：$line"
  done <<< "$src_hits"
else
  ok "lib/ 里没有网络调用"
fi

echo "== 3/4 Android 清单权限 =="

# 正式包（main）**一条权限都不该有**。没有 INTERNET 权限，系统层面就发不出请求，
# 这是比源码扫描更硬的保证 —— 反射拼出来的调用也一样发不出去。
main_manifest="android/app/src/main/AndroidManifest.xml"
if [ -f "$main_manifest" ]; then
  perms="$(grep -o 'uses-permission[^>]*' "$main_manifest" || true)"
  if [ -n "$perms" ]; then
    fail "正式包清单里出现了权限声明（应为 0 条）："
    printf '%s\n' "$perms" | sed 's/^/      /'
  else
    ok "正式包清单没有声明任何权限"
  fi
  if grep -q 'android.permission.INTERNET' "$main_manifest"; then
    fail "正式包清单声明了 INTERNET —— 单机免备案资格没了"
  fi
else
  fail "找不到 $main_manifest"
fi

# debug / profile 清单里有 INTERNET 是 Flutter 的默认行为（hot reload、DevTools 用），
# 只打进调试包，不进 release。这里只提示，不算失败。
for variant in debug profile; do
  m="android/app/src/$variant/AndroidManifest.xml"
  if [ -f "$m" ] && grep -q 'android.permission.INTERNET' "$m"; then
    echo "  · $variant 清单有 INTERNET（Flutter 默认，仅调试包，符合预期）"
  fi
done

echo "== 4/4 产物检查 =="

if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
  apk="$1"
  if [ ! -f "$apk" ]; then
    fail "找不到 APK：$apk"
  else
    AAPT=""
    for cand in "${ANDROID_HOME:-}/build-tools"/*/aapt2 \
                "C:/dev/android-sdk/build-tools"/*/aapt2 \
                "$(command -v aapt2 2>/dev/null)"; do
      [ -x "$cand" ] && AAPT="$cand" && break
    done
    if [ -z "$AAPT" ]; then
      echo "  · 跳过：本机找不到 aapt2（CI 上会跑）"
    else
      badging="$("$AAPT" dump badging "$apk" 2>/dev/null || true)"
      if printf '%s' "$badging" | grep -q "android.permission.INTERNET"; then
        fail "APK 里有 INTERNET 权限：$apk"
      else
        ok "APK 未申请 INTERNET 权限：$(basename "$apk")"
      fi
    fi
  fi
else
  echo "  · 跳过：没传 APK 路径（构建完再跑一次：tools/check_no_network.sh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk）"
fi

echo
if [ "$FAIL" -ne 0 ]; then
  echo "不联网门禁：未通过。"
  echo "这个应用必须保持「断网全功能可用」，否则会失去单机免备案资格。"
  exit 1
fi
echo "不联网门禁：通过。"
