#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""提交前的隐私扫描。

默认扫**工作区里所有被 git 跟踪的文件**（不看 build/、.dart_tool/,它们被
.gitignore 挡住了）。命中即打印并退出码 1；干净则打印汇总。

    python tools/privacy_scan.py                    # 只看工作树
    python tools/privacy_scan.py --history          # 再加上历史
    python tools/privacy_scan.py --history --artifacts ../x.bundle ../y.apk

## 为什么现在多了 --history 和 --artifacts

2026-10-25 复盘发现：这个脚本当时已经存在、也写得不差，但**没能拦住一次真实
的泄漏**，原因是范围写死了「被 git 跟踪的文件」——而泄漏发生在两个它看不见的
地方：

1. **历史**。上一轮脱敏改的是工作树里的文档文本，`git grep` 返回 0，看起来
   完成了；但 `git log -p` 仍能翻到旧提交里的 `C:\\Users\\<用户名>\\...`。
   工作树干净 **不等于** 历史干净，而推到公开仓库后暴露的恰恰是历史。
2. **交付物**。bundle 是压缩 packfile、apk 是 zip，`git grep` 穿不进去。
   一份"重写前备份"就这样带着 166 个提交（其中 3 个含真实路径）躺在仓库
   上一级目录里，差点被当成交付物发出去。

教训不是"脚本写得不好"，而是**扫描范围要靠穷举来定义，不能默认**：
被跟踪的文件只是三种载体之一，另两种是历史与打包产物。

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
import shutil
import subprocess
import sys
import tempfile
import zipfile
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

# 放行名单：这些文件不当作「被检测对象」。
#
# `tools/privacy_scan.py` 必须在这里，原因是**规则的定义文件天然包含规则的文本**：
# 它的规则表里写着证书页眉，注释里举了 `3.6.1.8` 当反例，自测样本里放着
# `/Users/alice/proj` 这类假路径。扫它必然自命中，而且命中数与规则条数一起增长。
#
# 这不是「绕开检测」：检测器不能把自己当输入，就像编译器不编译自己的语法表。
# 我曾试图把这条删掉、改用「页眉后必须跟 base64 密钥体」来消除自命中 ——
# 那条规则本身是对的（已保留，见 false_positive），但它只解决私钥一类，
# 证书页眉、SVG 坐标、自测样本照样命中。删白名单的结论是：**这条必须留**。
SKIP_FILES = {
    'LICENSE',                  # 版权人名本来就要公开
    'tools/privacy_scan.py',    # 规则定义文件，见上
}

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
    if name == '私钥' and _is_mere_reference(matched, line):
        # 只有页眉、后面没有密钥体 —— 那是在「讲」私钥长什么样，不是贴了一把私钥。
        # 区分依据：真实私钥的页眉后面一定跟着 base64 的密钥体（长度几十到几千）。
        # 这条规则替代了原来「把说明文档加进 SKIP_FILES」的权宜做法：
        # 白名单会连真泄漏一起放过，而按形态判断不会。
        return True
    if name in ('银行卡号', '身份证号', '手机号') and _SVG_DATA.search(line):
        return True
    if name == '邮箱' and matched.startswith('git@'):
        return True          # git@github.com:owner/repo 是 SSH 远程地址
    return False


def _is_mere_reference(matched: str, line: str) -> bool:
    """页眉之后没有 base64 密钥体 → 只是引用格式，不是密钥material。"""
    idx = line.find(matched)
    if idx < 0:
        return False
    tail = line[idx + len(matched):]
    # 真实密钥体：连续 16 个以上 base64 字符。`...`、`.`、反引号、空格都不算
    return re.search(r'[A-Za-z0-9+/=]{16,}', tail) is None


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


# 给 git grep 的 ERE 粗筛。必须是合法 POSIX ERE（无 lookahead、无 \d），
# 作用是「快速缩小范围」；是否真的算命中由 _judge 用 Python 正则决定。
# 这里的每一条都要对应 PATTERNS 里至少一条规则，且**只能更宽不能更窄** ——
# 更窄就会漏。
_HISTORY_PREFILTER = [
    r'[A-Za-z]:[\\/](Users|Documents and Settings)[\\/]',
    r'/(Users|home)/',
    r'BEGIN [A-Z ]*PRIVATE KEY',
    r'BEGIN CERTIFICATE',
    r'(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}',
    r'github_pat_',
    r'glpat-',
    r'sk-[A-Za-z0-9]{20,}',
    r'AKIA[0-9A-Z]{16}',
    r'(storePassword|keyPassword|signingPassword|password|passwd|pwd)[[:space:]]*[=:]',
    r'(api[_-]?key|apikey|secret|access[_-]?token|auth[_-]?token)[[:space:]]*[=:]',
    r'1[3-9][0-9]{9}',
    r'[0-9]{6}(19|20)[0-9]{2}(0[1-9]|1[0-2])',
]

# 一次 git grep 传多少个提交：太多会撑爆命令行长度
_REV_CHUNK = 150
# 历史最多回溯多少个提交，防止超大仓库把扫描拖成几分钟
_REV_LIMIT = 800


def scan_history(cwd: Path) -> list[str]:
    """扫全部提交的文件树。

    用 `git grep <pattern> <commit...>` 而不是 `git log -S`：
    -S 统计的是「该字符串出现次数变化」，于是「删除它的那个提交」也会命中，
    脱敏做完之后仍然报警，形成永久误报。按提交树 grep 才等价于
    「历史里现在还有没有」——那正是我们要回答的问题。
    """
    revs = subprocess.run(['git', 'rev-list', '--all'], cwd=cwd,
                          capture_output=True, text=True).stdout.split()
    if not revs:
        return []
    truncated = len(revs) > _REV_LIMIT
    revs = revs[:_REV_LIMIT]
    hits = _grep_commits(cwd, revs, '历史 ')
    if truncated:
        hits.append(f'  （历史只扫了最近 {_REV_LIMIT} 个提交，共超过 {_REV_LIMIT} 个）')
    return hits


def _judge(content: str) -> tuple[str, str] | None:
    """用 Python 正则精判一行内容，返回 (规则名, 命中串)。"""
    for name, pat in PATTERNS:
        m = pat.search(content)
        if not m:
            continue
        if false_positive(name, m.group(0), content):
            continue
        return name, m.group(0)
    return None


def _grep_commits(cwd: Path, revs: list[str], tag: str) -> list[str]:
    """两段式：git grep 用 ERE 粗筛（快），Python 正则精判（准）。

    为什么不直接把 PATTERNS 喂给 `git grep -E`：POSIX ERE **不支持**
    `(?!...)` 这类负向断言，`git grep` 会直接报错退出。而如果把非 0 返回码
    当成「没命中」跳过，结果就是**历史永远显示干净** —— 静默假阴性。
    这个坑真实发生过一次：加了 --history 之后仍然报 clean，实际上 3 个提交
    里躺着真实路径。
    """
    prefilter = '|'.join(_HISTORY_PREFILTER)
    hits: list[str] = []
    for i in range(0, len(revs), _REV_CHUNK):
        chunk = revs[i:i + _REV_CHUNK]
        # 注意：`--` 必须放在 revisions **之后**。放在前面会把提交当成
        # pathspec，于是永远匹配不到、还不报错。
        # `core.quotepath=false` 让中文路径原样输出，否则会被转义成 \344\272 这种
        # 八进制串，既看不懂也匹配不上 SKIP_FILES。
        r = subprocess.run(
            ['git', '-c', 'core.quotepath=false', 'grep', '-I', '-n', '-E',
             '-e', prefilter] + chunk,
            cwd=cwd, capture_output=True, text=True, errors='replace')
        if r.returncode == 1:
            continue                       # 1 = 没有匹配，正常
        if r.returncode != 0:
            # 不能吞掉：宁可让调用方看到「扫不了」，也不能报「干净」
            hits.append(f'  {tag}扫描失败 rc={r.returncode}: {r.stderr.strip()[:160]}')
            return hits
        for line in r.stdout.splitlines():
            parts = line.split(':', 3)     # <commit>:<path>:<lineno>:<content>
            if len(parts) < 4:
                continue
            commit, path, _no, content = parts
            if path in SKIP_FILES:         # 扫描器自身在历史里同样是误报
                continue
            judged = _judge(content)
            if judged is None:
                continue
            name, _m = judged
            hits.append(f'  {tag}{commit[:9]}  {path}  [{name}]  {content.strip()[:120]}')
            if len(hits) >= 40:
                hits.append(f'  {tag}命中过多，已截断')
                return hits
    return hits


def _scan_extracted(root: Path) -> list[str]:
    hits: list[str] = []
    for f in root.rglob('*'):
        if not f.is_file() or f.suffix.lower() in BINARY_SUFFIX:
            continue
        try:
            text = f.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        hits.extend(scan_text(f.relative_to(root).as_posix(), text))
    return hits


def scan_artifact(path: Path) -> list[str]:
    """扫交付物。bundle 与 zip/apk 的处理方式不同：

    - bundle：`git clone --mirror` 出来的仓库，**树和历史都要扫** —— 一份备份
      的价值恰恰在历史里，只扫 HEAD 等于没扫
    - zip/apk：解包后按文本文件扫。apk 里的 dex 是二进制会跳过，但构建路径
      写在 `assets/`、`res/` 的文本资源里能被抓到
    """
    if not path.is_file():
        return [f'  {path}  不存在，跳过']
    tmp = Path(tempfile.mkdtemp(prefix='pscan_'))
    try:
        if path.suffix.lower() == '.bundle':
            r = subprocess.run(['git', 'clone', '-q', '--mirror', str(path), str(tmp / 'chk')],
                               capture_output=True, text=True)
            if r.returncode != 0:
                return [f'  {path}  无法解析为 bundle，跳过']
            repo = tmp / 'chk'
            hits = [f'  {path.name}  {h.strip()}' for h in scan_history(repo)]
            hits += [f'  {path.name}  {h.strip()}'
                     for h in _grep_commits(repo, ['HEAD'], 'HEAD ')]
            return hits
        if path.suffix.lower() in ('.zip', '.apk'):
            with zipfile.ZipFile(path) as z:
                z.extractall(tmp / 'x')
            return [f'  {path.name}  {h}' for h in _scan_extracted(tmp / 'x')]
        return [f'  {path}  未知类型，跳过']
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def selftest() -> int:
    """自测：证明「该红的时候会红、该绿的时候会绿」。

    为什么必须有这一步：2026-10-25 改造这个脚本时连续踩了两次**假阴性**——
    一次是 `git grep` 的 `--` 放错位置（提交被当成 pathspec，永远无匹配），
    一次是把 POSIX ERE 不支持 lookahead 的报错当「没命中」跳过。
    两次的表现都是「扫描通过」，而实际上 3 个提交里躺着真实路径。

    一个永远绿的扫描器比永远红的更危险：红的会被修，绿的会被相信。
    """
    cases: list[tuple[str, str | None, str]] = [
        # (输入, 期望命中的规则名, 说明)；None 表示应当放行
        ('C:' + chr(92) + 'Users' + chr(92) + '12345' + chr(92) + 'proj',
         'Windows 个人路径', '真实 Windows 用户目录'),
        ('C:/Users/<用户名>/proj', None, '已是占位符，应放行'),
        ('/Users/alice/proj', 'macOS/Linux 个人路径', '真实 macOS 用户目录'),
        ('/home/bob/x', 'macOS/Linux 个人路径', '真实 Linux 用户目录'),
        ('password = "hunter2"', '密码被写成字面量', '口令字面量'),
        ('password = "{keystoreProperties}"', None, '变量引用不是字面量'),
        ('ghp_' + 'a' * 24, 'GitHub Token', 'GitHub Token 形态'),
        ('git@github.com:owner/repo', None, 'SSH 地址不是邮箱'),
        ('127.0.0.1', None, '环回地址不是敏感信息'),
        ('1' + '3800138000', '手机号', '手机号形态'),
        # 私钥页眉：只有页眉 = 在讲格式（放行）；页眉 + base64 体 = 真密钥（命中）
        ('-----BEGIN ' + 'PRIVATE KEY-----', None, '只有页眉，属于引用格式'),
        ('-----BEGIN ' + 'PRIVATE KEY-----\nMIIEow' + 'IBAAKCAQEA' + 'x' * 24,
         '私钥', '页眉后有 base64 密钥体'),
    ]
    bad = 0
    for text, expect, why in cases:
        judged = _judge(text)
        got = judged[0] if judged else None
        ok = got == expect
        if not ok:
            bad += 1
        print(f'  {"OK " if ok else "FAIL"}  期望={expect!s:<22} 实得={got!s:<22} {why}')
    print(f'\n自测 {"通过" if bad == 0 else f"{bad} 条不通过"}'
          f'（阳性必须命中、阴性必须放行）')
    return 0 if bad == 0 else 1


def main() -> int:
    argv = sys.argv[1:]
    if '--selftest' in argv:
        return selftest()

    do_history = False
    art_paths: list[str] = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--history':
            do_history = True
        elif a == '--artifacts':
            i += 1
            while i < len(argv) and not argv[i].startswith('--'):
                art_paths.append(argv[i])
                i += 1
            continue
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        else:
            print(f'未知参数：{a}（用 --help 看用法）')
            return 2
        i += 1

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

    print(f'[工作树] 扫描 {scanned} 个被跟踪的文本文件（共 {len(files)} 个跟踪文件）')

    if do_history:
        h = scan_history(ROOT)
        print(f'[历史]   {len(h)} 处' if h else '[历史]   干净（全部提交的文件树）')
        hits.extend(h)

    for p in art_paths:
        ap = Path(p).resolve()
        a = scan_artifact(ap)
        print(f'[交付物] {ap.name}: {"干净" if not a else str(len(a)) + " 处"}')
        hits.extend(a)

    if hits:
        print(f'\n发现 {len(hits)} 处可疑：')
        print('\n'.join(hits))
        print('\n提醒：工作树干净不等于历史干净；文档里出现真实路径也算命中。')
        return 1
    print('未发现密钥 / Token / 密码 / 个人路径 / 个人信息')
    return 0


if __name__ == '__main__':
    sys.exit(main())
