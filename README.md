# 黑塔消费日记

「纸墨」配色的**本地记账 App**（纸白底 + 暖灰墨字，不引入装饰色）。不联网、不注册、不上传 —— 所有账目保存在设备本地的 SQLite 里，
卸载即清除，靠导出 Excel 做备份。

当前版本 **1.4.4+12**（包名 `com.heita.ledger`，Android）。

## 接手先看这里

第一次进这个仓库，按下面顺序读，**别从代码开始翻**：

| 文档 | 讲什么 | 什么时候看 |
| --- | --- | --- |
| **[`docs/交接说明.md`](docs/交接说明.md)** | 环境搭建、踩过的坑、代码地图、**当前进度与待办** | **先读这个**，半小时能把工程跑起来 |
| [`CHANGELOG.md`](CHANGELOG.md) | 每个版本改了什么；顶部有「版本 → 标签 → 签名方式」索引 | 想知道某版为什么不能覆盖安装 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | 新机器配环境（认证、出网、依赖、已知坑） | 换电脑第一次拉代码 |

**当前状态**：**1.4.4 已发版**（[Releases](https://github.com/LanMao-213/heita-ledger/releases/latest)）。
1.4.2 → 1.4.4 这一轮修的全是「界面不说、数据已经不对」的地方：清空点了没反应、
记完在明细里看不见、点备注像重开面板、周期账单只在冷启动补记、明细超 500 条静默丢弃、
搜索搜不到分类名/账户名/金额；并补上「清空/恢复前自动留快照」「数据安全」回滚页
与「本期全览」页。
**代码是绿的，真机还没验**：1.4.2 ~ 1.4.4 的十二条行为 + 1.4.1 遗留的六项都在
`CHANGELOG.md` 的「待验证」「待测试」两个小节里，逐条打勾。
要开始干活，直接跳到交接说明[第 11 节](docs/交接说明.md#11-当前状态从这里接2026-10-20-1935)。

---

## 现在做到哪了

V1.0 的 P0 功能已全部打通，能当一个真正的账本用：

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| 账本管理 | 完成 | 多账本、换图标、归档、切换器 |
| 账户管理 | 完成 | 六种账户类型、初始余额、是否计入总资产 |
| 分类管理 | 完成 | 支出 9 类 49 子分类、收入 6 类 24 子分类，两级、可自建；可停用/恢复、可拖拽排序 |
| 记一笔 | 完成 | 自建数字键盘、账户、日期、备注；部分子分类带详情（出发地/目的地、对象、名称） |
| 记账模板 | 完成 | 常用一笔存模板，顶部三个一键填充 |
| 周期账单 | 完成 | 每天/周/月/年，启动时自动补记 |
| 明细 | 完成 | 按日分组、月度概览、多条件筛选、关键词搜索、左滑删除；周期条左右轻扫翻页、双击回本期 |
| 图表 | 完成 | 分类甜甜圈 + 排行（点排行下钻到该分类的明细）+ 近 6 个月趋势 |
| 预算 | 完成 | 总预算/分类预算、按周期归集、节奏（每天能花多少）、借入计入可用额度 |
| Excel | 完成 | 导出 .xlsx（11 列）、按表头名导入，兼容旧 6 列文件 |
| 借贷往来 | 完成 | 借出/借入、对方与应还日、剩余按流水算、记还款核销；不计入收支与预算 |
| 我的/设置 | 完成 | 备份、清空数据、数据安全（自动快照可回滚）、关于 |

未做（PRD V1.1 起）：密码锁与生物识别、年视图、按账户统计、多币种、还款到期提醒。

详细需求见 `docs/设计资产/PRD-产品需求文档.html`。
接手前先读 **`docs/交接说明.md`**，环境、坑、代码地图都在里面。

---

## 跑起来

前置：Flutter SDK（本机验证版本 3.47.7 / Dart 3.13.5）、Android Studio（含 SDK 与 JDK）、一台开了 USB 调试的手机或模拟器。

```bash
./tools/pub_get.sh          # 装依赖（固定国内源，见下）
flutter run                 # 连上手机或模拟器后直接跑
```

> **别直接跑 `flutter pub get`**：`pubspec.lock` 是用镜像 `pub.flutter-io.cn` 解析的，
> 而 pub 会按当前源的地址重写 lock 里每个包的 `url` 字段 —— 版本一个不变，却多出
> 87 行脏改动。`tools/pub_get.sh` 只是替你设了 `PUB_HOSTED_URL` 再调 pub，
> 想手工跑就自己带上这个变量。约定：lock 的**版本**变化要提交，纯 `url` 变化不提交。

第一次跑 Android 要下载 Gradle 与依赖，几分钟到十几分钟不等。国内网络建议挂镜像，具体见交接说明。

> `android/local.properties` 是每台机器自己生成的（记录 SDK 路径），**不进版本库**。
> 用 Android Studio 打开工程会自动生成；直接 `flutter build apk` 也会生成。

## 常用命令

```bash
flutter analyze                               # 静态检查，提交前必须 0 issue
flutter test                                  # 全部测试
flutter test test/ui_shot_test.dart           # 只跑界面截图自检
flutter build apk --release --split-per-abi   # 出包（分 ABI，体积更小）
```

测试会真的把界面渲染成 PNG，输出在 `build/visual/`，可以直接核对视觉效果；
布局溢出（文字撑破卡片一类）会在测试里抛异常，比肉眼可靠。

## 真机走查

```bash
adb devices                  # 设备在列表里才算通了；显示 unauthorized 是手机上没点「允许」
flutter run --release        # 直接装到手机上跑（首次编译慢，之后改代码热重载）
```

不想插线就出包再拷到手机：

```bash
flutter build apk --release --split-per-abi
# 产物：build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

> release 用**仓库外**的正式密钥签名：`android/app/release.jks` + `android/key.properties`，
> 两者都被 git 忽略（签名文件泄露等于别人能以你的名义发版）。
> **新克隆的机器没有这两个文件，会自动退回 debug 签名** —— 构建照样成功，但签出来的包
> 和手机上已有的正式包签名不同，装不上、只能卸载（本地账目会跟着没）。
> 要覆盖升级，先找维护者要这两个文件。拿不到密钥时只能装 `com.heita.ledger.dev` 测试包做临时
> 诊断（见交接说明第 4 节）——**它不能当正式包用**：包名不同，而且库里没有流水时会灌 23 条演示数据。

> 沙箱 / CI 里跑不了 `flutter devices`（它要调 `reg query` 读浏览器版本，可能被安全策略拦），
> 但 `adb devices` 不受影响，排查设备以它为准。

## 目录结构

```
lib/
  main.dart            入口
  app.dart             主题、启动闸门、开屏、版本号常量
  store.dart           全局状态（ChangeNotifier），页面都读它
  data/
    db.dart            SQLite 建表 / 种子数据 / 版本迁移
    models.dart        数据模型 + 格式化工具 Fmt
    repo.dart          所有 SQL 都在这里，页面不直接碰库
    excel_service.dart 导入导出 xlsx
  design/
    tokens.dart        配色、间距、圆角、字号（唯一来源）
    icons.dart         线稿图标库
    svg_path.dart      SVG 路径解析器（手写）
    brand_paths.dart   品牌标志路径
  pages/               明细 / 图表 / 计划 / 我的 / 分类 / 周期账单 / 记账模板
  widgets/             公共组件、图表、记一笔面板
docs/
  交接说明.md          给协作者的落地文档（环境、坑、代码地图、当前进度）
  设计资产/            PRD、视觉规范、高保真原型、图标与启动页
```

## 开发约定

1. **颜色只用 `design/tokens.dart` 里的 `C`**。整套只有一个色相：红，且红色只表示「超支」，不做装饰。
2. **金额一律用 `int` 存「分」**，日期一律 `TEXT 'YYYY-MM-DD'`，月份 `'YYYY-MM'`。
3. **页面不写 SQL**，一律走 `Repo`；`Store` 只做内存缓存与刷新通知。
4. **改表结构必须升 `Db._version` 并写 `onUpgrade`**，老用户数据不能丢（1→2 加模板统计列就是样例）。
5. **新增页面要能通过截图自检**，不能有布局溢出。
6. 涉及数据库的 widget 测试，开库与造数据必须包在 `tester.runAsync` 里
   （假时钟里 await 真实 I/O 会永久卡死，超时都不触发）。
7. 红线：不加任何联网、统计、广告、崩溃上报 SDK。这是「单机应用免备案」的前提。

## 协作方式

```bash
git pull                                      # 开工前先拉
git checkout -b feat/budget-by-category
# ……写代码……
flutter analyze && flutter test
git add -A && git commit -m "feat: 分类预算"
git push -u origin feat/budget-by-category
```

- 分支用 `feat/xxx`、`fix/xxx`，`main` 始终保持可运行。
- 合并前必须 analyze 干净 + 测试全过；界面有改动的，把 `build/visual/` 的截图贴进 PR。

**第一次在新机器上配环境**（认证、出网、依赖、已知坑）看 [`CONTRIBUTING.md`](CONTRIBUTING.md)：
五六分钟能把「能拉、能跑、能推」全部搞定，第 8 节列了每一条踩过的坑。

## 设计资产

`docs/设计资产/` 下：

- `PRD-产品需求文档.html` 需求、表结构、优先级、明确不做的事
- `视觉规范.html` 色彩、字号、图标规范
- `index.html` 高保真可交互原型（改界面前对着看）
- `启动页.html` / `启动页定稿.png` 开屏方案
- `黑塔图标.svg` / `app-icon.svg` / `brand-mark.svg` 标志与图标
