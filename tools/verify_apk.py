#!/usr/bin/env python3
"""出包产物五项校验 —— 卡住「代码对、包不对」。

## 为什么需要它

`flutter analyze` + `flutter test` 证明的是「源码是对的」，证明不了
「手里这个 .apk 是对的」。实际出过的问题都在这条缝里：

- 版本号只改了 `pubspec.yaml`，忘了改 `lib/app.dart` 的 `kAppVersion`，
  于是「我的」页底部显示 1.4.20、安装包是 1.4.21；
- 新机器上没有 `android/key.properties`，release 自动回落 debug 签名，
  装不上手机上已有的版本（本地账目会跟着丢）；
- 某次引入依赖顺手带了 INTERNET 权限，「不联网」的承诺就没了 ——
  这件事在代码里完全看不出来。

五项检查覆盖的就是这三类事故。

## 用法

    python tools/verify_apk.py build/app/outputs/flutter-apk/app-release.apk

需要 Android SDK 的 `aapt`（或 `aapt2`）与 `apksigner`：
优先用 `$ANDROID_HOME` / `$ANDROID_SDK_ROOT`，其次 `C:/src/android-sdk`，
再其次 `PATH`。找不到工具时**报警告并降级**（不静默通过）。
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPECT_PACKAGE = "com.heita.ledger"
# 只出 arm64，见 README「打包与签名」
EXPECT_ABI = "arm64-v8a"

ok_all = True
warnings: list[str] = []


def ok(name: str, detail: str = "") -> None:
    print(f"  [OK]   {name}{('  —  ' + detail) if detail else ''}")


def fail(name: str, detail: str) -> None:
    global ok_all
    ok_all = False
    print(f"  [FAIL] {name}  —  {detail}")


def warn(name: str, detail: str) -> None:
    warnings.append(name)
    print(f"  [WARN] {name}  —  {detail}")


# --------------------------------------------------------------- 工具定位


def _sdk_candidates() -> list[Path]:
    out: list[Path] = []
    for env in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        v = os.environ.get(env)
        if v:
            out.append(Path(v))
    out += [Path("C:/src/android-sdk"), Path.home() / "AppData/Local/Android/Sdk"]
    return out


def find_tool(name: str) -> str | None:
    """在 SDK 的 build-tools 里找最新版本下的工具，找不到再看 PATH。

    Windows 上 apksigner 是 `.bat`（不是 .exe），要一并认。
    """
    if os.name == "nt":
        names = [f"{name}.exe", f"{name}.bat", name]
    else:
        names = [name]
    for sdk in _sdk_candidates():
        bt = sdk / "build-tools"
        if not bt.is_dir():
            continue
        for v in sorted(bt.iterdir(), reverse=True):
            for n in names:
                for cand in (v / n, v / "lib" / n):
                    if cand.exists():
                        return str(cand)
    return shutil.which(name)


# ------------------------------------------------------------------ 读取


def read_pubspec_version() -> tuple[str, str] | None:
    """返回 (versionName, versionCode)。"""
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)", text, re.M)
    if not m:
        return None
    return m.group(1), m.group(2)


def read_kapp_version() -> str | None:
    p = ROOT / "lib" / "app.dart"
    if not p.exists():
        return None
    m = re.search(r"kAppVersion\s*=\s*'([^']+)'", p.read_text(encoding="utf-8"))
    return m.group(1) if m else None


def badging(apk: Path) -> str | None:
    """跑 aapt dump badging。

    ★ 必须先把包复制到一个**纯 ASCII 路径**：aapt（Windows 版）打不开
    带中文的文件名，会报 `Unable to open ...: Illegal byte sequence`，
    看起来像「文件坏了」，其实是编码问题。本项目的 APK 全是中文名
    （「黑塔消费日记-1.4.21+22-arm64.apk」），所以这个绕法不是可选优化。
    """
    aapt = find_tool("aapt")
    if aapt is None:
        return None

    import tempfile

    tmp = Path(tempfile.gettempdir()) / "_verify_apk_probe.apk"
    shutil.copyfile(apk, tmp)
    try:
        r = subprocess.run(
            [aapt, "dump", "badging", str(tmp)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="ignore",
        )
        if r.returncode != 0:
            print(f"  aapt 执行失败（returncode={r.returncode}）")
            for line in (r.stderr or "").splitlines()[:3]:
                print(f"    {line}")
            return None
        return r.stdout
    finally:
        tmp.unlink(missing_ok=True)


# ------------------------------------------------------------------ 五项


def check_package(info: str) -> None:
    m = re.search(r"package: name='([^']+)'", info)
    if not m:
        fail("包名", "aapt 输出里没有 package 行")
        return
    got = m.group(1)
    if got == EXPECT_PACKAGE:
        ok("包名", got)
    else:
        fail("包名", f"应为 {EXPECT_PACKAGE}，实际 {got}（换了包名＝老用户升级不了）")


def check_version(info: str) -> None:
    pub = read_pubspec_version()
    if pub is None:
        fail("版本号", "pubspec.yaml 里读不到 version:")
        return
    name, code = pub
    m_name = re.search(r"versionName='([^']+)'", info)
    m_code = re.search(r"versionCode='([^']+)'", info)
    if not m_name or not m_code:
        fail("版本号", "aapt 输出里没有 versionName / versionCode")
        return
    got_name, got_code = m_name.group(1), m_code.group(1)

    if (got_name, got_code) != (name, code):
        fail("版本号", f"包内 {got_name}+{got_code}，pubspec 是 {name}+{code}")
    else:
        ok("版本号", f"{got_name}+{got_code}（与 pubspec 一致）")

    # 「我的」页底部显示的是 kAppVersion，漏改它就会出现「包里 1.4.21、
    # 界面上 1.4.20」这种对不上的情况 —— 这是本项目真实踩过的坑。
    kapp = read_kapp_version()
    if kapp is None:
        warn("kAppVersion", "lib/app.dart 里找不到 kAppVersion")
    elif kapp != name:
        fail("kAppVersion", f"lib/app.dart 是 {kapp}，pubspec 是 {name}")
    else:
        ok("kAppVersion", f"{kapp}（与 pubspec 一致）")


def check_signature(apk: Path) -> None:
    signer = find_tool("apksigner")
    if signer is None:
        warn("签名", "找不到 apksigner，跳过（装到真机前请自己确认不是 debug 签名）")
        return
    r = subprocess.run(
        [signer, "verify", "--print-certs", str(apk)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="ignore",
    )
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode != 0:
        fail("签名", "apksigner 校验未通过（包可能被改动或未签名）")
        return
    if "Android Debug" in out:
        fail(
            "签名",
            "这是 debug 签名 —— 装不上手机上已有的正式版（只能卸载重装，本地账目会丢）",
        )
        return
    m = re.search(r"SHA-256 digest:\s*([0-9a-f]+)", out)
    ok("签名", f"非 debug{f'，SHA-256 {m.group(1)[:16]}…' if m else ''}")


def check_permissions(info: str) -> None:
    perms = re.findall(r"uses-permission: name='([^']+)'", info)
    net = [p for p in perms if p in ("android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE")]
    if net:
        fail("权限", f"出现联网权限 {net} —— 「不联网」的承诺被破了")
    else:
        ok("权限", f"零联网权限（共 {len(perms)} 条，均为系统自动项）")


def check_icon(apk: Path, info: str) -> None:
    """图标要按 aapt 给的路径找。

    ★ 不能按文件名猜。AGP 会把资源名混淆成 `res/BW.xml` / `res/9w.png`，
    而且 Flutter 模板用的是 **adaptive icon 的 XML**，不是 png ——
    第一版按 `res/mipmap*/ic_launcher*.png` 找，在真实包上必定误报。
    """
    icons = set(re.findall(r"application-icon-[0-9]+:'([^']+)'", info))
    if not icons:
        fail("图标", "aapt 没报出 application-icon（清单里没声明 android:icon）")
        return
    try:
        with zipfile.ZipFile(apk) as z:
            names = set(z.namelist())
    except zipfile.BadZipFile:
        fail("图标", "不是合法的 APK（zip 解析失败）")
        return
    missing = [i for i in icons if i not in names]
    if missing:
        fail("图标", f"清单指向的图标在包里不存在：{missing[:3]}")
        return
    ok("图标", f"{len(icons)} 个图标资源（{', '.join(sorted(icons)[:2])}）")


def check_abi(apk: Path) -> None:
    """臂架构只是提示，不阻断：出通用包是合法选择。"""
    try:
        with zipfile.ZipFile(apk) as z:
            libs = {n.split("/")[1] for n in z.namelist() if n.startswith("lib/")}
    except zipfile.BadZipFile:
        return
    if not libs:
        warn("ABI", "包内没有 lib/ —— 若是纯 Dart 包可忽略")
        return
    if libs == {EXPECT_ABI}:
        ok("ABI", EXPECT_ABI)
    else:
        warn("ABI", f"包含 {sorted(libs)}；发版约定只出 {EXPECT_ABI}")


# ------------------------------------------------------------------ 主流程


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        print("用法：python tools/verify_apk.py <path-to.apk>")
        return 2

    apk = Path(argv[1])
    if not apk.exists():
        print(f"找不到文件：{apk}")
        return 2

    print(f"校验 {apk.name}")
    print(f"大小 {apk.stat().st_size / 1024 / 1024:.1f} MB\n")

    info = badging(apk)
    if info is None:
        print("找不到 aapt，无法读取包信息。")
        print("请装 Android SDK build-tools，或设 ANDROID_HOME 后重试。")
        return 2

    check_package(info)
    check_version(info)
    check_signature(apk)
    check_permissions(info)
    check_icon(apk, info)
    check_abi(apk)

    print()
    if ok_all:
        print(f"五项全过{f'（{len(warnings)} 条警告）' if warnings else ''}")
        return 0
    print("有检查未通过 —— 这个包不要发。")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
