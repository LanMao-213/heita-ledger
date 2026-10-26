#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""改前/改后截图对拍。

    python tools/visual_diff.py build/visual/base build/visual/after
    python tools/visual_diff.py a b --tolerance 2      # 允许每通道 ±2 的抗锯齿抖动
    python tools/visual_diff.py a b --quiet            # 只报差异，不打逐文件 OK

    # 已知唯一会「每次都变」的一张（测试自己写新快照，体积文案随之变）：
    python tools/visual_diff.py a b --exclude shot_24_safety

退出码：0 = 逐像素一致；1 = 有差异（含尺寸不一致、缺文件、多文件）。

## 为什么要有这个脚本

本仓库的 UI 截图（`test/ui_shot_test.dart` → `build/visual/`）**不做
`matchesGoldenFile`**：字体来自 `C:\\Windows\\Fonts\\Deng.ttf`，CI 在 ubuntu 上
没有这个路径，基线在 CI 必然对不上；要一致就得往仓库塞 10MB 字体，违反
「不塞二进制资源」的取舍。而把 golden 只留在本地跑，又等于没有 CI 护栏。

但**重构时确实需要**一个「我只是搬了代码，界面没变」的证据。这个脚本就是
那个证据：改前跑一遍截图到 `base/`，改完跑到 `after/`，对拍差异必须为 0。
它是一次性的验证工具，不是长期护栏 —— 用完把两个目录删掉即可，不占仓库。

## 为什么要自己解 PNG

不想为一次性的比较引入 Pillow。标准库只有 zlib，够用了：
PNG 的像素数据就是 `zlib(每行: 1 字节 filter + 像素字节)`。
Flutter 的 `toByteData(format: png)` 出的是 8 位 RGBA、非隔行，
所以这里只需支持 color type 0/2/6 + bit depth 8，其余情况明确报错而不是猜。
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
import zlib

PNG_SIG = b"\x89PNG\r\n\x1a\n"


def _chunks(data: bytes):
    """产出 (类型, 数据) —— 只读 IHDR / IDAT，其余跳过。"""
    pos = len(PNG_SIG)
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        yield ctype, data[pos + 8:pos + 8 + length]
        pos += 12 + length  # 长度 + 类型 + 数据 + CRC


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path: str):
    """返回 (宽, 高, 每像素字节数, 未过滤的像素行列表)。"""
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(PNG_SIG):
        raise ValueError("不是 PNG")

    width = height = depth = color = None
    idat = bytearray()
    for ctype, payload in _chunks(data):
        if ctype == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(
                ">IIBBBBB", payload)
            if depth != 8 or color not in (0, 2, 6) or interlace != 0:
                raise ValueError(
                    f"{path}: 只支持 8 位非隔行的灰度/RGB/RGBA（实际 depth={depth} "
                    f"color={color} interlace={interlace}）")
        elif ctype == b"IDAT":
            idat += payload
        elif ctype == b"IEND":
            break
    if width is None:
        raise ValueError(f"{path}: 缺 IHDR")

    channels = {0: 1, 2: 3, 6: 4}[color]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    rows = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype == 0:
            pass
        elif ftype == 1:  # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:  # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                upleft = prev[i - channels] if i >= channels else 0
                line[i] = (line[i] + _paeth(left, prev[i], upleft)) & 0xFF
        else:
            raise ValueError(f"{path}: 未知行过滤类型 {ftype}")
        rows.append(bytes(line))
        prev = line
    return width, height, channels, rows


def diff_pair(a_path: str, b_path: str, tolerance: int):
    """返回 (是否一致, 差异像素数, 总像素数, 说明)。"""
    aw, ah, ac, arows = read_png(a_path)
    bw, bh, bc, brows = read_png(b_path)
    if (aw, ah) != (bw, bh):
        return False, f"尺寸不同 {aw}x{ah} vs {bw}x{bh}"
    if ac != bc:
        return False, f"通道数不同 {ac} vs {bc}"

    bad = 0
    # 差异包围盒：光知道「差 45 个像素」没法定位；知道「差在 y=610..624、
    # x=24..180」就能立刻对上是谁。实测里正是靠它认出「差的是一行相对时间文案」。
    x0 = y0 = 10 ** 9
    x1 = y1 = -1
    for r in range(ah):
        ra, rb = arows[r], brows[r]
        if ra == rb:
            continue
        for i in range(0, aw * ac, ac):
            if max(abs(ra[i + c] - rb[i + c]) for c in range(ac)) > tolerance:
                bad += 1
                x = i // ac
                x0, x1 = min(x0, x), max(x1, x)
                y0, y1 = min(y0, r), max(y1, r)
    if bad == 0:
        return True, ""
    return False, (f"{bad}/{aw * ah} 像素不同（{bad / (aw * ah):.2%}），"
                   f"差异区域 x{x0}..{x1}, y{y0}..{y1}")


def main() -> int:
    ap = argparse.ArgumentParser(description="两张/两目录 PNG 逐像素对比")
    ap.add_argument("a", help="基准目录")
    ap.add_argument("b", help="对比目录")
    ap.add_argument("--tolerance", type=int, default=0,
                    help="允许的每通道最大差值（默认 0，严格一致）")
    ap.add_argument("--quiet", action="store_true", help="只输出有差异的文件")
    ap.add_argument("--exclude", default="",
                    help="按文件名子串跳过（逗号分隔）。用于已知「测试自己造数据、"
                         "每次体积/时间都不同」的图，如 shot_24_safety")
    args = ap.parse_args()

    for d in (args.a, args.b):
        if not os.path.isdir(d):
            print(f"目录不存在：{d}", file=sys.stderr)
            return 2

    skip = [x.strip() for x in args.exclude.split(",") if x.strip()]

    def keep(n: str) -> bool:
        return not any(k in n for k in skip)

    names_a = {n for n in os.listdir(args.a) if n.lower().endswith(".png") and keep(n)}
    names_b = {n for n in os.listdir(args.b) if n.lower().endswith(".png") and keep(n)}
    if skip:
        print(f"已跳过：{', '.join(skip)}")
    if not names_a and not names_b:
        print("两个目录里都没有 PNG —— 截图是不是没生成？", file=sys.stderr)
        return 2

    failed = 0
    only_a = sorted(names_a - names_b)
    only_b = sorted(names_b - names_a)
    for n in only_a:
        print(f"[只在基准] {n}")
        failed += 1
    for n in only_b:
        print(f"[只在对比] {n}")
        failed += 1

    same = 0
    for n in sorted(names_a & names_b):
        ok, note = diff_pair(
            os.path.join(args.a, n), os.path.join(args.b, n), args.tolerance)
        if ok:
            same += 1
            if not args.quiet:
                print(f"一致 {n}")
        else:
            failed += 1
            print(f"差异 {n} — {note}")

    print(f"\n合计：{len(names_a & names_b)} 张比对，{same} 张一致，{failed} 项不一致"
          f"（容差 {args.tolerance}）")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
