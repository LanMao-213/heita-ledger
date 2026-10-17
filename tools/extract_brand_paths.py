#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从原型 index.html 中抽取品牌标志路径，生成 Dart 源码。

绝不手抄路径数据 —— 手工复制极易出错（本次就发生过），
必须由脚本原样提取，保证图形与设计稿一致。
"""
import re
import sys
from pathlib import Path

SRC = Path(r"C:/Users/<用户名>/WorkBuddy/2026-10-16-09-53-46/记账App/index.html")
OUT = Path(r"C:/Users/<用户名>/WorkBuddy/2026-10-16-09-53-46/heita_ledger/lib/design/brand_paths.dart")

html = SRC.read_text(encoding="utf-8")


def grab(name: str) -> str:
    m = re.search(r'const\s+' + name + r'\s*=\s*"([^"]*)"', html)
    if not m:
        sys.exit(f"未找到 {name}")
    return m.group(1)


def dart_str(s: str, chunk: int = 900) -> str:
    """拆成多段相邻字面量，避免单行过长。原始字符串不能含单引号。"""
    assert "'" not in s, "路径含单引号，需要改用其他转义方式"
    parts = [s[i:i + chunk] for i in range(0, len(s), chunk)]
    if len(parts) == 1:
        return "r'" + parts[0] + "'"
    return "\n".join("    r'" + p + "'" for p in parts)


mark = grab("MARK_PATH")
flame = grab("FLAME_PATH")

dart = f"""// ⚠️ 本文件由 tools/extract_brand_paths.py 自动生成，请勿手工编辑。
// 数据来源：原型 记账App/index.html 中的 MARK_PATH / FLAME_PATH。
//
// 这两个常量是对用户参考图的矢量化描摹结果（455×944 视图框），
// 像素不一致率 1.83%（残差全部来自边缘抗锯齿）。
// 用户明确要求「不要去动外形」，因此任何情况下都不要手工调整这里的数值。

/// 标志主体（黑塔徽记）。眼睛处嵌套 4 层轮廓，必须用 evenOdd 填充。
const String kMarkPath =
{dart_str(mark)};

/// 标志中的火焰（源自烛台），单独描摹以便叠加红色。
const String kFlamePath =
{dart_str(flame)};

/// 描摹源视图框（含 9,5 的边距偏移）
const double kMarkViewBoxW = 455;
const double kMarkViewBoxH = 944;
const double kMarkViewBoxX = 9;
const double kMarkViewBoxY = 5;

/// 主体路径字符数 / 火焰路径字符数（用于自检）
const int kMarkPathLength = {len(mark)};
const int kFlamePathLength = {len(flame)};
"""

OUT.write_text(dart, encoding="utf-8")
print(f"MARK_PATH  {len(mark)} 字符")
print(f"FLAME_PATH {len(flame)} 字符")
print(f"已写入 {OUT}")
print(f"文件大小 {OUT.stat().st_size} 字节")
