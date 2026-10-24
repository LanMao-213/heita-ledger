#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""提交前的隐私扫描。

扫的是**工作区里所有被 git 跟踪的文件**（不看 build/、.dart_tool/,它们被
.gitignore 挡住了）。命中即打印并退出码 1；干净则打印汇总。

    python tools/privacy_scan.py

## 为什么按「形态」而不是「关键词」扫

`token` / `password` / `secret` 这类词在代码里到处都是（本项目的 `C.xxx` 就
是从 token 里取色），按词扫会撞出上百条噪声 —— 噪声越多越没人看。所以这里
只认**长得像凭证的字符串**（ghp_ 开头、-----BEGIN PRIVATE KEY-----、
`password="字面量"` 这种赋值形态）和**长得像个人信息的串**（个人路径、手机号、
身份证、银行卡号、非 noreply 邮箱）。

## 为什么要有误报过滤

第一版上线就撞了 18 条假阳性：`git@github.com:owner/repo`（SSH 地址不是邮箱）、
`127.0.0.1`（环回地址不是 IP）、`C:/Users/<用户名>/`（**已经是占位符**，正说明
脱敏做过了）、图标路径里的 `1.1.5 1.7`（SVG 坐标不是版本号也不是 IP）。
一个天天喊狼来了的扫描器等于没有 —— 所以下面 `FALSE_POSITIVE` 逐条写明放行理由，
以后要加规则也得同时写理由。
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PATTERNS: list[tuple[str, re.Pattern]] = [
    ('GitHub Token', re.compile(r'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b')),
    ('GitHub PAT(新版)', re.compile(r'\bgithub_pat_[A-Za-z0-9_]{20,}\b')),
    ('GitLab Token', re.compile(r'\bglpat-[A-Za-z0-9_\-]{20,}\b')),
    ('Slack Token', re.compile(r'\bxox[abprs]-[A-Za-z0-9\-]{10,}\b')),
    ('OpenAI Key', re.compile(r'\bsk-[A-Za-z0-9]{20,}\b')),
    ('AWS Access Key', re.compile(r'\bAKIA[0-9A-Z]{16}\b')),
    ('私钥', re.compile(r'-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----')),
    ('证书', re.compile(r'-----BEGIN CERTIFICATE-----')),
    ('密码被写成字面量', re.compile(
        r'(?:storePassword|keyPassword|signingPassword|password|passwd|pwd)\s*[=:]\s*'
        r'["\'](?!\{|\$|%|<|\*)[^"\'\s]{4,}["\']', re.IGNORECASE)),
    ('密钥被写成字面量', re.compile(
        r'(?:api[_-]?key|apikey|secret|access[_-]?token|auth[_-]?token)\s*[=:]\s*'
        r'["\'](?!\{|\$|%|<|\*)[^"\'\s]{8,}["\']', re.IGNORECASE)),
    # `<用户名>` / `<用户>`（HTML 里会转义成 `&lt;用户名&gt;`）已经是占位符 ——
    # 那正说明脱敏做过了，不算命中
    ('Windows 个人路径', re.compile(
        r'[A-Za-z]:[\\/](?:Users|Documents and Settings)[\\/](?!<|&lt;)[^\\/\s"\'<>]+[\\/]',
        re.IGNORECASE)),
    ('macOS/Linux 个人路径', re.compile(
        r'/(?:Users|home)/(?!<|&lt;)[a-z0-9._\-]{2,}/', re.IGNORECASE)),
    ('邮箱', re.compile(
        r'(?<![\w@./\-])[A-Za-z0-9._%+\-]+@'
        r'(?!users\.noreply\.github\.com|example\.com|flutter\.dev|google\.com|github\.com)'
        r'[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b')),
    ('内网/公网 IP', re.compile(
        r'\b(?:(?:10|172|192)\.(?:\d{1,3}\.){2}\d{1,3}'
        r'|(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})\b')),
    ('手机号', re.compile(r'(?<!\d)1[3-9]\d{9}(?!\d)')),
    ('身份证号', re.compile(
        r'(?<!\d)\d{6}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx](?!\d)')),
    ('银行卡号', re.compile(r'(?<!\d)\d{4}[ -]?\d{4}[ -]?\d{4}[ -]?\d{4}(?!\d)')),
]

# 放行：这些文件里出现的是「教人怎么配」的说明，不是真的凭证
SKIP_FILES = {'LICENSE'}          # 版权人名本来就要公开

BINARY_SUFFIX = {'.png', '.jpg', '.jpeg', '.gif', '.ico', '.bmp', '.webp',
                 '.ttf', '.otf', '.woff', '.woff2', '.mp3', '.wav', '.mp4',
                 '.jar', '.jks', '.keystore', '.db', '.sqlite', '.pdf', '.zip'}

_LOOPBACK = re.compile(r'^(?:127\.|0\.0\.0\.0|255\.255\.255\.255|localhost)')
# SVG / 图标路径数据：一堆数字挤在一起，会被 IP / 银行卡 / 身份证 的正则误吃
_SVG_DATA = re.compile(r'(?:\sd="|r\'<|d=r\'|<path|<rect|<circle)', re.IGNORECASE)


def false_positive(name: str, matched: str, line: str) -> bool:
    """逐条写明放行理由 —— 加规则时必须同时写理由，否则这函数会变成垃圾桶。"""
    if name == '内网/公网 IP':
        # 文档里讲「跑测试要剥代理」必然写 127.0.0.1，环回地址不是敏感信息
        if _LOOPBACK.match(matched):
            return True
        # SVG 路径里的 `3.6.1.8` 这类坐标串
        if _SVG_DATA.search(line):
            return True
    if name in ('银行卡号', '身份证号', '手机号') and _SVG_DATA.search(line):
        return True
    if name == '邮箱' and matched.startswith('git@'):
        return True          # git@github.com:owner/repo 是 SSH 远程地址
    return False


def scan_text(rel: str, text: str) -> list[str]:
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        for name, pat in PATTERNS:
            m = pat.search(line)
            if not m:
                continue
            if false_positive(name, m.group(0), line):
                continue
            hits.append(f'  {rel}:{i}  [{name}]  {line.strip()[:140]}')
            break
    return hits


def main() -> int:
    out = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT,
                         capture_output=True, text=True)
    files = [ROOT / p for p in out.stdout.split('\0') if p]

    hits: list[str] = []
    scanned = 0
    for f in files:
        rel = f.relative_to(ROOT).as_posix()
        if rel in SKIP_FILES or f.suffix.lower() in BINARY_SUFFIX:
            continue
        try:
            text = f.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        scanned += 1
        hits.extend(scan_text(rel, text))

    print(f'扫描 {scanned} 个被跟踪的文本文件（共 {len(files)} 个跟踪文件）')
    if hits:
        print(f'\n发现 {len(hits)} 处可疑：')
        print('\n'.join(hits))
        return 1
    print('未发现密钥 / Token / 密码 / 个人路径 / 个人信息')
    return 0


if __name__ == '__main__':
    sys.exit(main())
