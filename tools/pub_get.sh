#!/usr/bin/env bash
# 装依赖的统一入口（替代直接跑 `flutter pub get`）。
#
# 为什么需要它：仓库里的 pubspec.lock 是用国内镜像 pub.flutter-io.cn 解析出来的，
# 而 `flutter pub get` 会按当前的 PUB_HOSTED_URL（不设就是 pub.dev）**重写 lock 里
# 每个包的 url 字段**。版本号和 sha256 一个都不变，但会多出 87 行「脏改动」，
# 提交时很容易被顺手带进 commit。固定源之后 lock 就不会再抖。
#
# 用法：
#   ./tools/pub_get.sh              # 正常装依赖
#   ./tools/pub_get.sh --offline    # 参数原样透传
set -euo pipefail

cd "$(dirname "$0")/.."
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "找不到 flutter，先把 Flutter SDK 的 bin 目录加进 PATH" >&2
  exit 127
fi

echo "PUB_HOSTED_URL=$PUB_HOSTED_URL"
exec flutter pub get "$@"
