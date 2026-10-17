# 黑塔消费日记

极简黑白灰风格的**本地记账 App**。不联网、不注册、不上传 —— 所有账目保存在设备本地的 SQLite 里，
卸载即清除，靠导出 Excel 做备份。

当前版本 **1.1.0**（包名 `com.heita.ledger`，Android）。

---

## 现在做到哪了

V1.0 的 P0 功能已全部打通，能当一个真正的账本用：

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| 账本管理 | 完成 | 多账本、换图标、归档、切换器 |
| 账户管理 | 完成 | 六种账户类型、初始余额、是否计入总资产 |
| 分类管理 | 完成 | 支出/收入分组、自建分类、线稿图标库 |
| 记一笔 | 完成 | 支出/收入自建数字键盘、账户、日期、备注 |
| 记账模板 | 完成 | 常用一笔存模板，顶部三个一键填充 |
| 周期账单 | 完成 | 每天/周/月/年，启动时自动补记 |
| 明细 | 完成 | 按日分组、月度概览、关键词搜索、左滑删除 |
| 图表 | 完成 | 分类甜甜圈 + 排行 + 近 6 个月趋势 |
| Excel | 完成 | 导出 .xlsx、按同格式导入 |
| 我的/设置 | 完成 | 备份、清空数据、关于 |

未做（PRD V1.1 起）：密码锁与生物识别、多条件筛选、子分类、年视图与日历视图、按账户统计、多币种。

详细需求见 `docs/设计资产/PRD-产品需求文档.html`。
接手前先读 **`docs/交接说明.md`**，环境、坑、代码地图都在里面。

---

## 跑起来

前置：Flutter SDK（本机验证版本 3.47.7 / Dart 3.13.5）、Android Studio（含 SDK 与 JDK）、一台开了 USB 调试的手机或模拟器。

```bash
flutter pub get
flutter run                 # 连上手机或模拟器后直接跑
```

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
  交接说明.md          给协作者的落地文档
  设计资产/            PRD、视觉规范、高保真原型、图标与启动页
```

## 开发约定

1. **颜色只用 `design/tokens.dart` 里的 `C`**。整个应用只有黑白灰 + 两档红，红色只表示「超支」，不做装饰。
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

## 设计资产

`docs/设计资产/` 下：

- `PRD-产品需求文档.html` 需求、表结构、优先级、明确不做的事
- `视觉规范.html` 色彩、字号、图标规范
- `index.html` 高保真可交互原型（改界面前对着看）
- `启动页.html` / `启动页定稿.png` 开屏方案
- `黑塔图标.svg` / `app-icon.svg` / `brand-mark.svg` 标志与图标
