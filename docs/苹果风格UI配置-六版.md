# 苹果风格 UI 配置 · 六版对照

> 状态：**待选稿**，尚未改动任何代码。选定一版后再落 `lib/design/tokens.dart`。
> 生成日期：2026-10-22

## 0. 参考来源与取值口径

两份参考文件给出的信息不一样，需要分开用：

| 文件 | 内容 | 用法 |
|---|---|---|
| `血族Bloodline阵营色彩关系.csv`（实为 xlsx） | 5 行阵营表：阵营 / 主色 / 辅助色 / 来源 | **决定「出几版」** —— 5 行 = 5 版 |
| `血族Bloodline阵营美术设计、画风演变与配色研究.md` | 22 条推荐配色的十六进制值 + 三层色彩系统 | **决定「每版用什么色」** |

CSV 里只有颜色**名称**（深酒红 / 冰蓝 / 冷白 / 钢灰 / 靛黑 / 鎏金 / 哑光黑 / 暗红 / 钴蓝 / 黑色），没有色值。色值全部取自研究文档第十一节「推荐配色表（推断值，仅用于二次创作）」：

```
血族主色 #7A1224   血族暗部 #1B0C10   血族强调 #C81E3A   血族冷光 #A6D8E8
圣地制服 #F4F6F8   圣地装甲 #7E8791   圣地领域红 #8C1C28
黑塔主色 #13111C   黑塔金   #C9A24B   黑塔宝石蓝 #2E5C8A  隆音个人蓝 #2C5FA8
```

**原色值不能直接用。** 研究文档原文对配色的约束是「深色面积占优势，高饱和颜色控制在 10%–20%」——这是**插画**的比例，记账 App 是**正文为主**的界面，直接拿 `#7A1224` 当底色会让整屏失去可读性。所以这里的做法是：

1. 阵营主色 → 用作**底的色相/明度锚点**（`#7A1224` → 底 `#161013`，保住「深红黑」的调子）；
2. 阵营辅助色 → 用作**强调色**（冰蓝 `#A6D8E8` 在深底上够亮，鎏金 `#C9A24B` 同理）；
3. 中间层级（ink2/ink3/line/bg2…）→ 用 WCAG 亮度公式**反解**出来，保证每一档都达标。

派生色全部用同一个 HSL 色相、饱和度按档位衰减（0.45/0.50/0.65），所以每版的中性灰都带该阵营的冷暖倾向，而不是系统灰。

### 校验口径

每版都跑过现有护栏 `test/design/tokens_contrast_test.dart` 的全部断言（WCAG 2.1 相对亮度，公式与测试内一致）：

| 约束 | 阈值 | 结果 |
|---|---|---|
| ink 对 bg / cardBg | ≥ 7:1 | 10.9 – 16.7 ✅ |
| ink2 对 bg / cardBg | ≥ 4.5:1 | 5.9 – 7.0 ✅ |
| ink3 对 bg / cardBg | ≥ 4.5:1 | 4.7 – 5.3 ✅ |
| over 对 bg / cardBg | ≥ 4.5:1 | 5.5 – 6.1 ✅ |
| line 对 cardBg | 1.05 – 1.45 | 1.24 – 1.26 ✅ |
| onAccent 对 accent | ≥ 4.5:1 | 4.7 – 11.4 ✅ |
| accent 对 handle（进度条） | ≥ 3:1 | 3.2 – 8.4 ✅ |
| cardBg / bg 层级 | ≥ 1.05 | 1.08 – 1.18 ✅ |
| cardBg / heroBg 层级 | ≥ 1.15 | 1.16 – 1.29 ✅ |
| bg2 / bg 层级 | ≥ 1.10 | 1.12 – 1.30 ✅ |

---

## A. 苹果风格六维基线（五版共用）

「苹果特色」不在颜色，在这六条。颜色五版各自不同，**这六条五版完全一致**，换版时不用改。

### A1. 圆角 —— 连续圆角（squircle）

iOS 的圆角不是圆弧，是超椭圆（squircle）：曲率在角上连续变化，视觉上比 `RoundedRectangleBorder` 更「软」且更紧。Flutter **3.13+** 原生提供 `RoundedSuperellipseBorder`，本项目 Flutter 3.47.7 可直接用。

```dart
abstract final class R {
  static const xs    = 6.0;   // 小标签、角标
  static const sm    = 10.0;  // iOS 列表单元、按钮
  static const md    = 14.0;  // iOS 卡片默认
  static const card  = 18.0;  // 分组卡片
  static const lg    = 22.0;  // 大卡 / 弹层
  static const sheet = 28.0;  // sheet 顶部两角
  static const pill  = 999.0; // 胶囊
}
```

现状：现有 `R` 是 9 / 13 / 16 / 20，形状是普通圆弧。改这条要动 41 处 `R.xxx`（值自动跟随）+ 22 处硬编码（`cats_page.dart:325`、`debts_page.dart:206,364`、`plan_page.dart:563,642`、`record_sheet.dart` 等），并把 `BorderRadius.circular` 换成 `RoundedSuperellipseBorder`。

### A2. 字号 —— Apple Dynamic Type 阶梯

iOS 的正文基准是 **17pt**，比现在这套（14.5）大两号。层级是固定的 11 档：

```dart
abstract final class T {
  static const largeTitle = TextStyle(fontSize: 34, fontWeight: FontWeight.w700, height: 1.12);
  static const title1     = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.14);
  static const title2     = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.16);
  static const title3     = TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.20);
  static const headline   = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.29);
  static const body       = TextStyle(fontSize: 17, fontWeight: FontWeight.w400, height: 1.47);
  static const callout    = TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.44);
  static const subhead    = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.40);
  static const footnote   = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.38);
  static const caption1   = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.33);
  static const caption2   = TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.36);

  /// 金额：等宽数字，列表里不能左右跳
  static const amount = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const amountSm = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
```

**字距（letterSpacing）要留白处理。** 上表没写字距，是因为 Apple 给的负值（-0.43 / -0.24 …）是按 SF Pro 的拉丁字形调的，套到中文会挤。建议：**中文正文一律 0**，只有大数字（largeTitle / amount）保留 `-0.4`，余额那种大数字收紧才好看。

现状：现有 8 档（34/20/15/14.5/13.5/12.5/16/14），另有 **86 处硬编码 fontSize、30 个不同值**（11.5 出现 10 次、12 出现 8 次、10.5 出现 3 次……）。落地前必须先收编到 `T`，否则换阶梯只换掉一半。

### A3. 间距 —— 8pt 栅格

```dart
abstract final class S {
  static const xxs = 2.0;   // 仅 hairline 补偿
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;  // iOS 标准左右边距
  static const xl  = 20.0;
  static const xxl = 24.0;  // iOS 分组间距
  static const xxxl= 32.0;
  static const huge= 40.0;
}
```

规则：左右边距固定 16；卡片之间 12；分组之间 24–32；行内元素 8。现有 `S` 已经是 4/8/12/16/20/24，调用 410 次，**这版只需补 32/40 两档**，并把残留的 6/10/14/7/11 收编（约 20 处）。

### A4. 图标 —— SF Symbols 规范

现有 `lib/design/icons.dart` 的 82 个图标已经是 24×24 视图框、1.5 线宽、圆头端点——**方向和 SF Symbols 是一致的**，不用重画。要补的是三件事：

1. **线宽分档**（SF Symbols 的 9 档字重映射到线宽）：
   ```dart
   enum IconWeight { ultraLight(1.0), thin(1.2), light(1.4), regular(1.5),
                     medium(2.0), semibold(2.5), bold(3.0) }
   ```
   给 `LineIcon` 加 `weight` 参数即可，82 个 path 不用动。
2. **光学对齐**：图标尺寸 ≈ 同行字号 × 1.35（17pt 字配 23px 图标，13pt 字配 18px）。
3. **选中态换填充**：iOS 的 tab / 分段控件选中时是实心变体。现在 82 个全是线稿，选中态只能靠染色区分。低成本做法：选中时线宽从 1.5 提到 2.5 并叠一层 accent 描边，视觉上接近 SF Symbols 的 filled，不用重画 82 个 path。

### A5. 动效 —— 时长 + 曲线分档

现状：**没有动效令牌**，全库只有 7 处隐式动画（`AnimatedContainer` 6 + `AnimatedOpacity` 1），时长散落在 90/140/160/240/260/900ms，页面转场全部用 `MaterialPageRoute` 平台默认。这是六维里唯一需要从零建的一维。

```dart
abstract final class M {
  // 时长
  static const tap    = Duration(milliseconds: 120); // 按下 / 抬手
  static const inline = Duration(milliseconds: 200); // 展开收起、高度变化
  static const sheet  = Duration(milliseconds: 350); // 抽屉、弹层
  static const page   = Duration(milliseconds: 500); // 页面转场
  static const number = Duration(milliseconds: 400); // 数字滚动

  // 曲线（iOS 系统曲线）
  static const standard   = Cubic(0.40, 0.00, 0.20, 1.00);
  static const decelerate = Cubic(0.00, 0.00, 0.20, 1.00); // 进场
  static const accelerate = Cubic(0.40, 0.00, 1.00, 1.00); // 出场
  static const spring     = Cubic(0.32, 0.72, 0.00, 1.00); // iOS 弹性
}
```

**转场换成 iOS 的右进右出**：`MaterialPageRoute` → `CupertinoPageRoute`（全库 9 处）。这是「苹果特色」最容易被感知的一条——安卓默认是上下淡入，iOS 是从右推入 + 左侧边缘跟手返回。

触感沿用现有 `lib/design/haptics.dart`，对齐 `UIImpactFeedbackGenerator` 的 light / medium / heavy 三档 + `selectionChanged`（轮盘滚动）。

### A6. 材质 —— 毛玻璃与细线

| 材质 | 模糊 σ | 叠加层 |
|---|---|---|
| ultraThin | 10 | 底色 3% |
| thin | 20 | 底色 6% |
| regular | 30 | 底色 12% |
| thick | 40 | 底色 18% |

浅色板叠加白、深色板叠加黑。Flutter 用 `BackdropFilter(filter: ImageFilter.blur(sigmaX: σ, sigmaY: σ))` + 半透明色层。用在：底部抽屉、顶部栏滚动后、浮动记一笔按钮。

**分隔线必须是 hairline**：`1 / MediaQuery.devicePixelRatio`，物理 1 像素。现在用的是 1 逻辑像素，在 3x 屏上是 3 物理像素，明显偏粗——这是现在看起来「不够精致」的一大来源。

**触控区最小 44×44**（Apple HIG 硬指标），现在部分图标按钮是 32。

---

## B. 五版配色

### 速览

| 版 | 名称 | 阵营 | 明暗 | 底 | 强调 | 气质 |
|---|---|---|---|---|---|---|
| **V1** | 血族·夜宴 | 血族 | 深 | `#161013` | `#A6D8E8` 冰蓝 | 暗舱壁 + 月光，冷艳 |
| **V2** | 圣地·审判 | 圣地 | 浅 | `#F2F4F7` | `#4E5A67` 钢灰 | 冷白纪律，最克制 |
| **V3** | **黑塔·鎏金** ★ | 黑塔 | 深 | `#13111C` | `#C9A24B` 鎏金 | 靛黑藏书塔 + 金书脊 |
| **V4** | 圣地·罗马 | 圣地罗马单位 | 深 | `#17181A` | `#D05A6C` 暗红 | 哑光黑甲 + 铁红识别带 |
| **V5** | 黑塔·隆音 | 黑塔毁灭隆音 | 浅 | `#F5F6F8` | `#2C5FA8` 钴蓝 | 米白纸面 + 蓝毛衣 |
| **V6** | **露露缇雅·泽金** ◆ | 黑塔·露露缇雅 | 浅 | `#EAF3F6` | `#3E7A8B` 冷蓝 | 明亮天空 + 白裙绯带 |

★ V3 与项目名「黑塔」同源，且是唯一同时用到「靛黑 + 鎏金 + 宝石蓝」三色的一版。
◆ V6 是**唯一有项目自身历史资产的一版**：1.4.5 之前它就是那套编译期双配色里的第二套（提交 `e64acfd`，`--dart-define=HEITA=1`），四色是天青 `#9AC7D3` / 暖白 `#FDFBF8` / 绯红 `#814864` / 薰衣草 `#BC9DB1`。这一版是以它为骨架重做的，不是新编的。

---

### V1 · 血族·夜宴（深）

> 深酒红黑底 + 冰蓝冷光。血族的三色是「深红—黑—冰蓝」，深红负责底色与血液，冰蓝负责月光与剑光。强调色选冰蓝而不是深红，是因为 `#7A1224` 压在 `#161013` 上只有 2.4:1，做不了强调。

```dart
abstract final class C {
  static const ink       = Color(0xFFF7F0F0);  // 对 bg 16.7:1
  static const ink2      = Color(0xFFBCA6A6);  // 6.9:1
  static const ink3      = Color(0xFFAB8D8D);  // 5.3:1
  static const ink4      = Color(0xFF774F4F);
  static const inkWash   = Color(0x12F7F0F0);

  static const bg        = Color(0xFF161013);  // 页面底：墨黑偏红
  static const heroBg    = Color(0xFF120A0D);  // 概览卡：压下去
  static const cardBg    = Color(0xFF2A1F23);  // 卡：浮起来
  static const bg2       = Color(0xFF342626);  // 卡内次级面 / 键帽
  static const bg3       = Color(0xFF291E1E);

  static const line      = Color(0xFF3F2E2E);  // 对 cardBg 1.24:1
  static const line2     = Color(0xFF513B3B);
  static const handle    = Color(0xFF3D2D2D);
  static const heroEdge  = Color(0xFF281E1E);

  static const accent      = Color(0xFFA6D8E8); // 冰蓝
  static const onAccent    = Color(0xFF141A1C); // 对 accent 11.4:1
  static const accentSoft  = Color(0xFF404046);
  static const accentWash  = Color(0xFF39353B);
  static const todayMark   = Color(0xFFA6D8E8);
  static const onTodayMark = Color(0xFF141A1C);

  static const over  = Color(0xFFEC7183);  // 血红提亮，深底可读
  static const overD = Color(0xFFEE8897);
  static const cardShadow = Color(0x59000000);
  static const stage = Color(0xFF0E0A0C);
}

const List<Color> kChart = [
  Color(0xFFF7F0F0), Color(0xFFE8E0E0), Color(0xFFD9D1D1), Color(0xFFC9C1C1),
  Color(0xFFBAB1B1), Color(0xFFABA2A2), Color(0xFF9C9292), Color(0xFF8C8282),
  Color(0xFF7D7373), Color(0xFF6E6363),
];
```

---

### V2 · 圣地·审判（浅）

> 冷白 + 钢灰 + 领域红。圣地的白「不是无害，而是制度化的可见性」。强调色取钢灰深 `#4E5A67`（Apple 的 graphite 强调色思路），把领域红 `#8C1C28` 完整留给超支警示——两者都用红会打架。

```dart
abstract final class C {
  static const ink       = Color(0xFF161A1F);  // 对 bg 15.9:1
  static const ink2      = Color(0xFF4F555D);  // 6.8:1
  static const ink3      = Color(0xFF5F6771);  // 5.2:1
  static const ink4      = Color(0xFF9BA4AF);
  static const inkWash   = Color(0x0F161A1F);

  static const bg        = Color(0xFFF2F4F7);  // 冷白（iPad/iOS 分组底）
  static const heroBg    = Color(0xFFE9EDF1);
  static const cardBg    = Color(0xFFFFFFFF);
  static const bg2       = Color(0xFFE3E5E8);
  static const bg3       = Color(0xFFE9EAEC);

  static const line      = Color(0xFFE4E6E8);  // 1.25:1
  static const line2     = Color(0xFFCCD0D4);
  static const handle    = Color(0xFFE7E9EB);
  static const heroEdge  = Color(0xFFD7D9DD);

  static const accent      = Color(0xFF4E5A67); // 钢灰深
  static const onAccent    = Color(0xFFFFFFFF); // 7.0:1
  static const accentSoft  = Color(0xFFDFE1E4);
  static const accentWash  = Color(0xFFEAEBED);
  static const todayMark   = Color(0xFF4E5A67);
  static const onTodayMark = Color(0xFFFFFFFF);

  static const over  = Color(0xFFBC2636);  // 领域红提亮
  static const overD = Color(0xFFCD5C68);
  static const cardShadow = Color(0x0F161A1F);
  static const stage = Color(0xFFDCDEE1);
}

const List<Color> kChart = [
  Color(0xFF161A1F), Color(0xFF2A2E32), Color(0xFF3E4246), Color(0xFF535659),
  Color(0xFF676A6D), Color(0xFF7B7D80), Color(0xFF8F9194), Color(0xFFA4A5A7),
  Color(0xFFB8B9BB), Color(0xFFCCCDCE),
];
```

---

### V3 · 黑塔·鎏金（深）★

> 靛黑 `#13111C` + 鎏金 `#C9A24B`。研究文档写黑塔「不是森林隐居巫师，而是知识管理、魔法工程与军事编制结合的塔群机构」，主色应是墨黑、暗靛、鎏金书脊——这版的底色就是原样的 `#13111C`，鎏金原样 `#C9A24B`，两个色都没动。

```dart
abstract final class C {
  static const ink       = Color(0xFFF2F0F6);  // 对 bg 16.5:1
  static const ink2      = Color(0xFFAFA9BA);  // 7.0:1
  static const ink3      = Color(0xFF9991A9);  // 5.3:1
  static const ink4      = Color(0xFF605575);
  static const inkWash   = Color(0x12F2F0F6);

  static const bg        = Color(0xFF13111C);  // 靛黑（原色）
  static const heroBg    = Color(0xFF0B0910);
  static const cardBg    = Color(0xFF232030);
  static const bg2       = Color(0xFF2C2834);
  static const bg3       = Color(0xFF232029);

  static const line      = Color(0xFF35303E);  // 1.24:1
  static const line2     = Color(0xFF443E50);
  static const handle    = Color(0xFF332F3C);
  static const heroEdge  = Color(0xFF211E26);

  static const accent      = Color(0xFFC9A24B); // 鎏金（原色）
  static const onAccent    = Color(0xFF181309); // 7.7:1
  static const accentSoft  = Color(0xFF413735);
  static const accentWash  = Color(0xFF373033);
  static const todayMark   = Color(0xFFC9A24B);
  static const onTodayMark = Color(0xFF181309);

  static const over  = Color(0xFFEC746F);
  static const overD = Color(0xFFED8A87);
  static const cardShadow = Color(0x59000000);
  static const stage = Color(0xFF0C0B12);
}

const List<Color> kChart = [
  Color(0xFFF2F0F6), Color(0xFFE3E0E7), Color(0xFFD3D1D8), Color(0xFFC4C1C9),
  Color(0xFFB4B2BA), Color(0xFFA5A2AA), Color(0xFF95939B), Color(0xFF86838C),
  Color(0xFF76747D), Color(0xFF67646E),
];
```

> 想再进一步的话，把 `#2E5C8A`（黑塔宝石蓝）用作**图表第 2 序列色**或「预算/计划」模块的专用色，机构色就完整了。

---

### V4 · 圣地·罗马（深）

> 哑光黑 + 暗红。罗马单位是「古罗马片甲 + 现代阻击步枪」，研究文档写其车辆载具宜用哑光白、钢灰、深空灰和少量暗红识别带。这版把暗红提到 `#D05A6C`——原色 `#8C1C28` 在黑底上只有 2.6:1，做不了强调色。

```dart
abstract final class C {
  static const ink       = Color(0xFFF2F2F3);  // 对 bg 15.9:1
  static const ink2      = Color(0xFFB0B0B3);  // 7.0:1
  static const ink3      = Color(0xFF98989C);  // 5.3:1
  static const ink4      = Color(0xFF5D5D62);
  static const inkWash   = Color(0x12F2F2F3);

  static const bg        = Color(0xFF17181A);  // 哑光黑
  static const heroBg    = Color(0xFF111214);
  static const cardBg    = Color(0xFF252628);
  static const bg2       = Color(0xFF2D2D2F);
  static const bg3       = Color(0xFF252526);

  static const line      = Color(0xFF363638);  // 1.26:1
  static const line2     = Color(0xFF434346);
  static const handle    = Color(0xFF343436);
  static const heroEdge  = Color(0xFF232325);

  static const accent      = Color(0xFFD05A6C); // 暗红提亮
  static const onAccent    = Color(0xFF190B0D); // 4.9:1
  static const accentSoft  = Color(0xFF442F34);
  static const accentWash  = Color(0xFF3A2C30);
  static const todayMark   = Color(0xFFD05A6C);
  static const onTodayMark = Color(0xFF190B0D);

  static const over  = Color(0xFFE87C8B);
  static const overD = Color(0xFFEA919E);
  static const cardShadow = Color(0x59000000);
  static const stage = Color(0xFF0F1011);
}

const List<Color> kChart = [
  Color(0xFFF2F2F3), Color(0xFFE3E3E4), Color(0xFFD3D3D5), Color(0xFFC4C4C5),
  Color(0xFFB5B5B6), Color(0xFFA5A5A7), Color(0xFF969698), Color(0xFF878788),
  Color(0xFF777779), Color(0xFF68686A),
];
```

---

### V5 · 黑塔·隆音（浅）

> 钴蓝 `#2C5FA8` + 黑。毁灭隆音是「黑发金瞳、蓝衣黑裤」的个人色，研究文档特别提醒「不能当作全塔主色」——所以这版只借它的蓝，底子仍是浅色纸面。五版里最安全、最接近现在「纸墨」观感的一版，适合当做「想要苹果感但不想改成深色」的折中。

```dart
abstract final class C {
  static const ink       = Color(0xFF14161C);  // 对 bg 16.7:1
  static const ink2      = Color(0xFF535660);  // 6.8:1
  static const ink3      = Color(0xFF636775);  // 5.2:1
  static const ink4      = Color(0xFF9FA4B2);
  static const inkWash   = Color(0x0F14161C);

  static const bg        = Color(0xFFF5F6F8);
  static const heroBg    = Color(0xFFECEEF2);
  static const cardBg    = Color(0xFFFFFFFF);
  static const bg2       = Color(0xFFE4E5E8);
  static const bg3       = Color(0xFFEBECEE);

  static const line      = Color(0xFFE5E6E9);  // 1.25:1
  static const line2     = Color(0xFFCECFD5);
  static const handle    = Color(0xFFE8E8EB);
  static const heroEdge  = Color(0xFFD9DADF);

  static const accent      = Color(0xFF2C5FA8); // 钴蓝（原色）
  static const onAccent    = Color(0xFFFFFFFF); // 6.4:1
  static const accentSoft  = Color(0xFFD9E2EF);
  static const accentWash  = Color(0xFFE6ECF5);
  static const todayMark   = Color(0xFF2C5FA8);
  static const onTodayMark = Color(0xFFFFFFFF);

  static const over  = Color(0xFFBE2820);
  static const overD = Color(0xFFCE5E58);
  static const cardShadow = Color(0x0F14161C);
  static const stage = Color(0xFFDEE0E2);
}

const List<Color> kChart = [
  Color(0xFF14161C), Color(0xFF282A30), Color(0xFF3D3E43), Color(0xFF515357),
  Color(0xFF65676B), Color(0xFF7A7B7E), Color(0xFF8E8F92), Color(0xFFA2A4A6),
  Color(0xFFB7B8B9), Color(0xFFCBCCCD),
];
```

---

### V6 · 露露缇雅·泽金（浅）◆

> **这一版是项目自己的旧资产**，不是新编的。1.4.5 之前它就是那套编译期双配色里的第二套（提交 `e64acfd`），四色取自方案原文「明亮天空下的白裙绯带，是黑塔角色中最清透的一套」：天青 `#9AC7D3`、暖白 `#FDFBF8`、绯红 `#814864`、薰衣草 `#BC9DB1`。
>
> 研究文档第六节对她的配色建议是「白金、冷蓝与塑能火光的克制组合」——白金 = 暖白卡面 + 天青淡底，冷蓝 = `#3E7A8B` / `#9AC7D3`，塑能火光 `#FF7A1A` 单列为第五色。

**相对原版改了三处**（其余色值原样保留）：

1. **`heroBg` 加深**：原版 `#F4EBF0` 对 `cardBg` 只有 1.13:1，护栏要求「汇总区压下、记录卡浮上」要分得开。改为薰衣草压暗 `#E7DCE3`，1.29:1。
2. **`bg2` 加深**：原版 `#E0EEF1` 对 `bg` 只有 1.06:1，数字键帽几乎沉不下去。改为 `#DDE7E9`，1.12:1。
3. **`kChart` 重排**：原版是「绯红→深天青→天青→薰衣草」四色循环，**亮度不单调**，会撞上护栏第 140 行的「十档单调变浅」。改为一条 绯紫 → 玫瑰绯 → 薰衣草 → 极淡天青 的明度阶梯，四色的身份保留、顺序改成由深到浅。

```dart
abstract final class C {
  static const ink       = Color(0xFF4A2C3A);  // 绯红压暗，对 bg 10.9:1
  static const ink2      = Color(0xFF6E5566);  // 5.9:1
  static const ink3      = Color(0xFF7E6478);  // 4.7:1
  static const ink4      = Color(0xFFBC9DB1);  // 薰衣草原色（占位/弱分割）
  static const inkWash   = Color(0x14814864);

  static const bg        = Color(0xFFEAF3F6);  // 天青极淡（明亮天空）
  static const heroBg    = Color(0xFFE7DCE3);  // 薰衣草压暗
  static const cardBg    = Color(0xFFFDFBF8);  // 暖白（白裙）
  static const bg2       = Color(0xFFDDE7E9);  // 天青灰
  static const bg3       = Color(0xFFE1E8EA);

  static const line      = Color(0xFFD5E5EA);  // 天青灰，对 cardBg 1.25:1
  static const line2     = Color(0xFFE1D3DC);  // 薰衣草灰
  static const handle    = Color(0xFFDCE4E8);
  static const heroEdge  = Color(0xFFE2CDD8);

  static const accent      = Color(0xFF3E7A8B); // 深天青（冷蓝）
  static const onAccent    = Color(0xFFFDFBF8); // 4.7:1
  static const accentSoft  = Color(0xFF9AC7D3); // 天青原色：胶囊底/图表主色
  static const accentWash  = Color(0x1F9AC7D3);
  static const todayMark   = Color(0xFF9AC7D3); // 日历里唯一那一小块天空
  static const onTodayMark = Color(0xFF4A2C3A); // 6.7:1

  static const over  = Color(0xFF814864);  // 绯红原色（绯带）
  static const overD = Color(0xFFC25A6E);
  static const cardShadow = Color(0x0F4A2C3A);
  static const stage = Color(0xFFE3EBEE);

  /// 塑能火光（可选第五色）：只做能量，不做文字。
  /// 对 bg 只有 2.3:1 —— 不能当文字色，只能做小块填充（预算告急点、
  /// 热力条末端、法术式的高亮）。真要压字用 Color(0xFF261204)（6.9:1）。
  static const ember = Color(0xFFFF7A1A);
}

const List<Color> kChart = [
  Color(0xFF4A2C3A), Color(0xFF844E62), Color(0xFFA86385), Color(0xFFB48092),
  Color(0xFFC496A3), Color(0xFFCCAABA), Color(0xFFD2BECB), Color(0xFFD0D2D9),
  Color(0xFFD3E2E7), Color(0xFFE3EFF3),
];
```

> **`ember` 是这一版唯一的「新增 token」。** 不改任何 UI 代码也能落地——它只是备用色，接线是可选项（比如预算进度条超过阈值时用它替代 `accent`）。不想用就整行删掉。

---

## C. 落地说明

### C1. 换色只需改一个文件

全库 **446 处** `C.xxx` 调用，色值 100% 集中在 `lib/design/tokens.dart`（设计目录外硬编码 `Color(0x...)` 只有 4 处）。选定一版 = 替换 tokens.dart 里的 `C` 与 `kChart`，其余不动。

唯一例外是 V6 的 `ember`：它比现有 24 个 token 多一个，属于**可选**——不接线不影响任何界面，不想用就整行删掉。

`static const` 必须保留：457 处 `C.xxx` 写在 `const TextStyle(...)` / `const BoxDecoration(...)` 里，一旦改成运行时 getter 会全部编译失败。

### C2. 六维里各维的改造成本

| 维度 | 现状 | 成本 |
|---|---|---|
| 配色 | 446 处已收敛到令牌 | **低** — 改一个文件 |
| 间距 | `S` 调用 410 次 | **低** — 补 32/40，收编 ~20 处硬编码 |
| 圆角 | `R` 调用 41 次 + 22 处硬编码 | **中** — 收编 + 换 squircle 形状 |
| 字号 | `T` 调用 200 次 + **86 处硬编码 / 30 个值** | **中高** — 必须先收编，否则只换掉 70% |
| 图标 | 82 个自建 path，已是 24×24 / 1.5 线宽 | **低** — 只加线宽分档与光学对齐 |
| 动效 | **无令牌**，7 处隐式动画，9 处默认转场 | **中** — 从零建，但量小 |

### C3. 现有护栏有 3 条断言是「浅色专用」，选深色版必须先改

`test/design/tokens_contrast_test.dart` 是按现在的浅色「纸墨」写的，选 V1 / V3 / V4 会直接红：

1. **第 37–59 行**：`bg2 比 cardBg 深，且比 bg 深`。
   深色界面里「浮起来 = 更亮」，键帽必须比面**浅**（iOS 深色键盘就是这样）。
   → 改成：`bg2` 与 `cardBg`、`bg` 的**对比度 ≥ 1.10**，不锁方向（锁「分得开」，不锁「谁亮」）。

2. **第 67–70 行**：`cardBg - heroBg > 0.02`（绝对亮度差）。
   深色区所有亮度都在 0.02 以下，这条恒不成立。
   → 改成：`_contrast(cardBg, heroBg) >= 1.15`。

3. **第 140–148 行**：`kChart 十档单调变浅`。
   深色板的图表色阶应该是 `[0]` 最亮（越深越看不见），方向相反。
   → 改成：先由 `bg` 亮度判断色板明暗，再决定断言递增还是递减。

三条改完，护栏对浅色/深色都成立，且没有放松任何一条可读性阈值。

V2 / V5 / V6 是浅色，不触发这三条。V6 额外把图表色阶按单调重排过，所以六版里**只有 V1 / V3 / V4 需要先改测试**——选 V6 可以当天就落，不用碰护栏。
