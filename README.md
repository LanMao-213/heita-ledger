# 黑塔消费日记

一个**不联网**的 Android 记账 App。所有账目存在手机的 SQLite 里,不注册、不上传、没有云同步;
换机靠先导出备份、再在新机导入。卸载会删掉本机数据,但安卓的系统备份可能留一份副本,所以换机前
请先「导出账单」存到电脑。界面是「纸墨」——纸白底、暖灰墨字,不引入装饰色。

包名 `com.heita.ledger`,Flutter 3.47 / Dart 3.13,Android 7.0(API 24)以上。

---

## 当前状态

| | |
|---|---|
| 默认分支 | **`feat/v2-merge`**,版本 **`1.4.6+14`**(未发版) |
| 已发版 | **`1.4.4+12`**,在 `main`(是 `feat/v2-merge` 的祖先,可 `--ff-only` 快进) |
| 质量闸门 | `flutter analyze` 0 issue、**310 条测试**全绿(含 24 张界面截图自检) |
| 规模 | `lib/` 约 1.9 万行、`test/` 约 1.1 万行,无第三方状态管理(就是 `ChangeNotifier`) |
| 许可 | [MIT](LICENSE) |
| 待办 | 视觉五项(圆角描边 → 字号 → 间距 → 图标 → 动效)已在 **1.4.6** 全部收口;1.4.2 以来十二条行为的**真机验证**未逐条打勾 |

> 1.4.5 起**只出一套配色**。原先那套「露露缇雅·泽金」和它的编译期开关 `--dart-define=HEITA=1`
> 已删除,不再需要打两个包 —— 详见 [`CHANGELOG.md`](CHANGELOG.md) 的「未发版」一节。

---

## 三条设计取舍

1. **离线优先,不是"暂时没做云同步"。** 没有 INTERNET 权限,发不出去就是发不出去
   —— 这是单机应用免备案的前提,也是"账目不会被谁看到"的唯一保证。
2. **金额全程用 `int` 存"分"。** 没有 `double`,不靠四舍五入维持平衡,求和永远精确。
3. **数据必须能带走。** 导出 `.xlsx` 与 JSON 备份是核心功能,不是附属品;
   换 App 或换手机都不该丢账。

---

## 功能

| 模块 | 说明 |
|---|---|
| 账本 | 多账本、换图标、归档、切换 |
| 账户 | 六种类型、期初余额、是否计入总资产 |
| 分类 | 两级:支出 9 类 49 子、收入 6 类 24 子;可自建、停用/恢复、拖拽排序 |
| 记一笔 | 自建数字键盘(支持算式)、账户、日期、备注;部分子分类带专属字段(出发地/目的地、对象、名称) |
| 模板 | 常用一笔存成模板,面板顶部三个一键填充 |
| 周期账单 | 每天/周/月/年,启动与回前台自动补记,重复插入有物理约束兜底 |
| 明细 | 按日分组、月度概览、多条件筛选、关键词搜索;长按弹出「编辑 / 多选 / 删除」菜单;周期条横扫翻期、双击回本期;keyset 分页 |
| 多选 | 顶栏「多选」按钮或长按菜单进入;全选(仅当前可见)、批量改分类、批量删除(一次事务、余额逐笔回滚) |
| 账单导入 | 支付宝 / 微信账单 **CSV**:四步过目、逐行可切换「算入」、收入行默认不勾、相似记录标黄;**不改余额**(历史账,按账户反向调期初) |
| 图表 | 分类甜甜圈 + 排行(点排行下钻到该分类明细)+ 近 6 期趋势 |
| 预算 | 总预算与分类预算、按期归集、节奏(每天能花多少)、借入计入可用额度 |
| 借贷往来 | 借出/借入、对方与应还日、剩余按流水算、记还款核销、**可整笔删除(连带回滚余额)**;不计入收支 |
| Excel | 导出 **12 列** `.xlsx`(含往来列),支持**按当前筛选**导出;按**表头名**定位导入,兼容旧 6 列文件 |
| 我的 | 备份、恢复、清空、数据安全(自动快照可回滚)、数据体检、关于 |

**明确不做**:云同步、多端、密码锁与生物识别、多币种、年视图、按账户统计、还款提醒(见 PRD 的「不做清单」)。

---

## 跑起来

前置:Flutter SDK(验证于 3.47.7 / Dart 3.13.5)、Android SDK + JDK、一台开了 USB 调试的手机或模拟器。

```bash
git clone https://github.com/LanMao-213/heita-ledger.git
cd heita-ledger
./tools/pub_get.sh     # 装依赖(固定国内源)
flutter run
```

> **别直接 `flutter pub get`。** 仓库里的 `pubspec.lock` 是按镜像 `pub.flutter-io.cn` 解析的,
> 直接跑会按当前源重写每个包的 `url` 字段 —— 版本一个不变,却多出 87 行脏改动。
> `tools/pub_get.sh` 只是替你设了 `PUB_HOSTED_URL` 再调 pub。约定:lock 的**版本**变化要提交,纯 `url` 变化不提交。
>
> `android/local.properties`(SDK 路径)由每台机器自己生成,不进版本库。

首次构建 Android 要下 Gradle 与依赖,几分钟到十几分钟;国内网络建议挂镜像,见交接说明。

## 常用命令

```bash
flutter analyze                                                # 提交前必须 0 issue
flutter test                                                   # 全部测试
flutter test test/ui_shot_test.dart                            # 只跑界面截图自检
flutter build apk --release --target-platform android-arm64    # 发版:只出 arm64,约 20 MB
```

`--target-platform` 只管 `libapp.so`,管不住插件自带的 `.so` —— 不加约束时包里会混进
`lib/armeabi-v7a/libdartjni.so`,32 位设备能装上但一启动就闪退。现在
`android/app/build.gradle.kts` 的 `packaging.jniLibs.excludes` 已排除非 arm64,
使 32 位设备在**安装阶段**就被拒(`INSTALL_FAILED_NO_MATCHING_ABIS`)。

**不要用 `--split-per-abi` 发版**:它给 versionCode 加 `1000×ABI` 偏移(23 变 2023),
之后正常打包的版本号反而更小,升级会卡死。`tools/verify_apk.py` 的版本号校验会拦住。

### ⚠️ 发版包要在「路径不含用户名」的目录下构建

`libapp.so` 会嵌入构建期的绝对路径 —— 实测形如
`file:///C:/Users/<用户名>/.../.dart_tool/flutter_build/dart_plugin_registrant.dart`。
这是 Dart AOT 的行为,没有配置项能关掉。**在带用户名的目录里打出来的包,
等于把本机路径随 APK 一起发出去**(2026-10-25 开工前所有历史 APK 都带着它)。

做法是先导出到中性路径再构建:

```bash
git archive HEAD | tar -x -C /c/hb/hl          # 只导出被跟踪文件
cp android/key.properties /c/hb/hl/android/     # 签名文件未被跟踪,要手动补
cp android/app/release.jks /c/hb/hl/android/app/
cd /c/hb/hl && flutter pub get
flutter build apk --release --target-platform android-arm64
```

出包后必须验一遍,**没有这条扫描就别发**:

```bash
python tools/privacy_scan.py --artifacts <apk路径>   # 应输出「干净」
```

`flutter test` 会真的把界面渲染成 PNG 到 `build/visual/`,可直接核对观感;
布局溢出(文字撑破卡片一类)会让测试失败,比肉眼可靠。

> **代理环境下跑测试必须剥掉代理变量**,否则会报
> `Unable to connect to flutter_tester process: Invalid WebSocket upgrade request`
> —— 那是 flutter_tester 的本地 WebSocket 被代理拦了,不是代码坏了:
>
> ```bash
> env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
>     NO_PROXY=localhost,127.0.0.1 flutter test
> ```

---

## 打包与签名(「装不上」九成是这里)

正式包用**仓库外**的密钥签:见 `android/app/release.jks` + `android/key.properties`,
两者都被 `.gitignore` 挡住,**从未进入过提交历史**(签名文件泄露等于别人能以你的名义发版)。

- 有这两个文件 → release 自动用正式密钥签,**可直接覆盖安装**。
- 新克隆的机器没有 → 自动回落 **debug 签名**,构建照样成功,但签出来的包与手机上已有版本
  签名不同,装不上、只能卸载(本地账目会跟着没)。

同理,`flutter build` 出来的包版本号取 `pubspec.yaml` 的 `version`;
改版本要同时改 `lib/app.dart` 的 `kAppVersion`(「我的」页底部显示的就是它)。

---

## 项目结构

```
lib/
  main.dart            入口
  app.dart             主题、启动闸门、开屏、版本号常量
  store.dart           全局状态(ChangeNotifier),页面都读它
  data/
    db.dart            建表 / 种子数据 / 版本迁移(schema v9)
    models.dart        数据模型 + 格式化工具 Fmt
    repo.dart          所有 SQL 都在这里,页面不直接碰库
    excel_service.dart 导入导出 xlsx
  design/
    tokens.dart        配色、间距、圆角、字号(唯一来源)
    icons.dart         线稿图标库
    svg_path.dart      SVG 路径解析器(手写)
    brand_paths.dart   品牌标志路径
  pages/               明细 / 图表 / 计划 / 我的 / 分类 / 周期账单 / 模板
  widgets/             公共组件、图表、记一笔面板
    record_sheet.dart      记一笔面板：状态机 + 布局
    record_sheet/          行为方法(actions) / 展示型组件(rows)，part 分部
docs/
  交接说明.md          落地文档:环境、坑、代码地图、当前进度
  版本对比.md          原版 vs 一次「从零重写」的逐项对比与决策记录
  开源准备.md          公开前的安全自查 + 每次发版前的检查命令
  设计资产/            PRD、视觉规范、高保真原型、图标与启动页
```

## 开发约定

1. **颜色只用 `design/tokens.dart` 里的 `C`**。整套「纸墨」不引入装饰色,唯一的彩色是超支砖红 `C.over`,它只表示超支。
2. **金额一律 `int` 存"分"**;日期 `TEXT 'YYYY-MM-DD'`;月份 `'YYYY-MM'`。
3. **页面不写 SQL**,一律走 `Repo`;`Store` 只做内存缓存与刷新通知。
4. **改表结构必须升 `Db._version` 并写 `onUpgrade`**,老用户数据不能丢。
5. **新增页面要能通过截图自检**,不允许布局溢出。
6. 涉及数据库的 widget 测试,开库与造数据必须包在 `tester.runAsync` 里(假时钟里 await 真实 I/O 会永久卡死)。
7. **红线**:不加任何联网、统计、广告、崩溃上报 SDK。

## 协作方式

```bash
git checkout feat/v2-merge      # 日常开发都在这一条线上
git pull --ff-only
git checkout -b feat/your-thing
# ……写代码……
flutter analyze && flutter test
git add -A && git commit -m "feat: 做了什么"
git push -u origin feat/your-thing
```

- 分支命名 `feat/` `fix/` `docs/` `chore/`;**`main` 只放已发版**,任何时刻都必须能 analyze + test 全过。
- 界面有改动的,把 `build/visual/` 里的截图贴进 PR。
- 新机器配环境(认证、出网、依赖、已知坑)看 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## 文档

| 文档 | 讲什么 |
|---|---|
| [`docs/交接说明.md`](docs/交接说明.md) | **先读这个**:环境、踩过的坑、代码地图、当前进度与待办 |
| [`docs/代码地图.md`](docs/代码地图.md) | 代码在哪、为什么这么分;分层方向与三条结构约束(有测试守着) |
| [`docs/写入口清单.md`](docs/写入口清单.md) | 写库走哪个入口;写完谁负责刷新;新增写路径的三步检查 |
| [`docs/交接说明-2026-10-26.md`](docs/交接说明-2026-10-26.md) | 最近一轮(结构整理)的交接:改了什么、怎么跑、下一步按什么顺序 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | 从零配一台能拉能跑能推的机器;每一条踩过的坑 |
| [`CHANGELOG.md`](CHANGELOG.md) | 每版改了什么;顶部有「版本 → 标签 → 签名方式」索引 |
| [`docs/版本对比.md`](docs/版本对比.md) | 原版 vs 重写版的逐项对比与**决策记录**(为什么没有直接换代) |
| [`docs/开源准备.md`](docs/开源准备.md) | 公开前的安全自查结论 + 每次发版前的检查命令 |

产品边界与「明确不做的事」在 `docs/设计资产/PRD-产品需求文档.html`;
界面原型是 `docs/设计资产/index.html`,改界面之前对着看。

---

## 许可

[MIT](LICENSE)。可以随便用、改、再发布,保留版权声明即可。

仓库里**不含**任何签名密钥、也没有任何联网权限 —— 这两件事都是有意为之,不是遗漏。
