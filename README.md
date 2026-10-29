# 黑塔消费日记

一个**不联网**的 Android 记账 App。所有账目存在手机的 SQLite 里,不注册、不上传、没有云同步;
换机靠先导出备份、再在新机导入。卸载会删掉本机数据,但安卓的系统备份可能留一份副本,所以换机前
请先「导出账单」存到电脑。界面默认是「圣地 · 审判白」——冷白底、钢灰字,不引入装饰色;
另外五套皮肤(App 内「我的 → 主题」可切)只换色不改布局,其中两套是深色。

包名 `com.heita.ledger`,Flutter 3.47 / Dart 3.13,Android 7.0(API 24)以上。

---

## 当前状态

| | |
|---|---|
| 默认分支 | **`main`**,版本 **`1.5.1+25`**(已发版,标签 `v1.5.1`) |
| 开发分支 | `feat/*`,合进 `main` 后按版本打标签(旧的 `feat/v2-merge` 已并入 `main` 并删除) |
| 已发版 | **`v1.5.1`**:[Release 页](https://github.com/LanMao-213/heita-ledger/releases/tag/v1.5.1) 带 arm64 APK(19.6 MB);上一版 `v1.5.0` 同样带包 |
| 质量闸门 | `flutter analyze --fatal-infos` 0 issue、**612 条测试**全绿(含界面截图自检)、版本号三处一致性(CI 内)、出包七项校验、隐私扫描四处载体 |
| 规模 | `lib/` 约 2.8 万行、`test/` 约 1.9 万行(91 个测试文件),无第三方状态管理(就是 `ChangeNotifier`) |
| 许可 | [MIT](LICENSE) |
| 待办 | 1.5.0 四项真机验收**已通过**(2026-10-28);**1.5.1 的「分类预算过滤」「趋势卡取消提示」两项仍待有数据态复核**(当时设备离线)。全部待办已转成 [Issues](https://github.com/LanMao-213/heita-ledger/issues) |

> **六套皮肤**在 App 内切换(中性冷灰 / 纸墨暖米 / 露露缇雅·泽金 / 黑塔·永夜 / 血族·深红 / 圣地;
> 出厂默认是**圣地 · 审判白**,1.5.1 起从「永夜」改来 —— 光线更接近原生启动窗口的浅底,默认路径上不再有冷启动跳变),
> 只换色不改布局。1.4.5 曾短暂收成单套配色并把「泽金」连同 `--dart-define=HEITA=1` 编译期开关一起删掉,
> 1.4.21 起改为运行时换肤,不再需要打两个包。
>
> **动过历史的仓库**:提交历史在 2026-10-24 / 10-25 / 10-28 改写过三次(清个人路径与提交信息里的主机名)。
> 旧克隆不要直接提交,重新 `git clone` 或 `git fetch --all && git reset --hard origin/main`。

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
| 图表 | 分类甜甜圈 + 排行(点排行下钻到该分类明细)+ 近 6 期趋势(点卡片在柱状/折线间切换) |
| 预算 | 总预算与分类预算、按期归集、节奏(每天能花多少)、借入计入可用额度 |
| 储蓄目标 | 目标金额与截止日、存钱/取钱记流水、进度环、归档;与预算同在「计划」页 |
| 借贷往来 | 借出/借入、对方与应还日、剩余按流水算、记还款核销、**可整笔删除(连带回滚余额)**;不计入收支 |
| Excel | 导出 **12 列** `.xlsx`(含往来列),支持**按当前筛选**导出;按**表头名**定位导入,兼容旧 6 列文件 |
| 我的 | 备份(明文 JSON,导出前会提示未加密)、恢复、清空、数据安全(自动快照可回滚)、数据体检、主题切换、关于 |

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

出包后必须验两遍,**两条都过才算能发**:

```bash
python tools/verify_apk.py <apk路径>                 # 七项:包名/版本/kAppVersion/签名/权限/图标/ABI
python tools/privacy_scan.py --artifacts <apk路径>   # 应输出「干净」
```

`verify_apk.py` 还会核对 `pubspec.yaml`、`lib/app.dart` 的 `kAppVersion` 与包内真实版本三者一致 ——
改版本时漏改一处,这里会拦住。

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
- 没有这两个文件(新克隆的机器 / CI)→ `flutter build apk --release` **直接失败**。
  构建在 `packageRelease` 之前就被拦下,磁盘上不会留下 APK。报错里写明了原因:
  缺密钥时本来会悄悄签成 debug,产出的包与手机上已有的正式版签名不同 —— 装不上,
  只能卸载,本地账目跟着没。**这里构建失败是安全行为,不是障碍**:一个"看起来是正式包、
  老用户却装不上"的 APK 比没有包危险得多。
- 本地联调 / 出并存测试包 → 显式放行(仍签成 debug):

  ```bash
  flutter build apk --release -PallowDebugSigning=true -PappIdSuffix=.dev
  ```

  这样出来的包与正式签名版本**不能互相覆盖**(签名不同),想两个包共存只能靠
  `appIdSuffix` 换掉包名 —— 这也是 `.dev` 后缀存在的理由。
- CI 不受影响:`.github/workflows/ci.yml` 的 `release-permissions` job 只跑
  `--config-only` 与 `:app:processReleaseManifest`,两步都不打包、也不需要密钥,因此仍然绿。

同理,`flutter build` 出来的包版本号取 `pubspec.yaml` 的 `version`;
改版本要同时改 `lib/app.dart` 的 `kAppVersion`(「我的」页底部显示的就是它)。

---

## 项目结构

```
lib/
  main.dart            入口
  app.dart             主题、启动闸门(**没有启动页**,等待期只铺底色)、版本号常量
  store.dart           全局状态(ChangeNotifier),页面都读它
  data/
    db.dart            建表 / 种子数据 / 版本迁移(schema v9)
    models.dart        数据模型(库入口) + models/ 分部；格式化工具 Fmt
    repo.dart          SQL 门面(页面不直接碰库) + repo/ 12 个分部
    repo_stats.dart    统计聚合(与列表查询分开)
    backup_service.dart 备份 / 恢复 / 自动快照
    bill_csv.dart      支付宝与微信账单 CSV 解析(门面 + bill/ 分部)
    integrity.dart     数据体检：余额自洽、孤儿行
  design/
    tokens.dart        配色、间距、圆角、字号(唯一来源)
    palette.dart       六套皮肤的色值表
    theme_ctrl.dart    当前皮肤(持久化 + 通知重绘)
    icons.dart         线稿图标库
    svg_path.dart      SVG 路径解析器(手写)
    brand_paths.dart   品牌标志路径
  pages/               明细 / 图表 / 计划 / 我的 / 分类 / 周期账单 / 模板 / 账单导入 / 数据安全
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

1. **颜色只用 `design/tokens.dart` 里的 `C`**。每套皮肤只换色、不引入装饰色;除超支砖红 `C.over`(只表示超支)之外,只允许各皮肤自己的 `accent`(如圣地 · 审判白的钢蓝 `#3A7BA1`,用于图表与日历「今天」)。
2. **金额一律 `int` 存"分"**;日期 `TEXT 'YYYY-MM-DD'`;月份 `'YYYY-MM'`。
3. **页面不写 SQL**,一律走 `Repo`;`Store` 只做内存缓存与刷新通知。
4. **改表结构必须升 `Db._version` 并写 `onUpgrade`**,老用户数据不能丢。
5. **新增页面要能通过截图自检**,不允许布局溢出。
6. 涉及数据库的 widget 测试,开库与造数据必须包在 `tester.runAsync` 里(假时钟里 await 真实 I/O 会永久卡死)。
7. **红线**:不加任何联网、统计、广告、崩溃上报 SDK。

## 协作方式

```bash
git clone https://github.com/LanMao-213/heita-ledger.git   # 旧克隆请重新克隆,见下
cd heita-ledger
git checkout -b feat/your-thing
# ……写代码……
flutter analyze && flutter test
git add -A && git commit -m "feat: 做了什么"
git push -u origin feat/your-thing
```

- 分支命名 `feat/` `fix/` `docs/` `chore/`;**`main` 只放已发版**,任何时刻都必须能 analyze + test 全过。
- **提交信息也是公开内容**:`C:/Users/<用户名>`、内网地址、真实邮箱手机号不要写进 message ——
  `filter-repo --replace-text` 改不了它(那只作用于文件内容),漏了就得再改写一次历史。
  CI 会跑 `python tools/privacy_scan.py --history --messages` 拦这一类。
- 界面有改动的,把 `build/visual/` 里的截图贴进 PR。
- 新机器配环境(认证、出网、依赖、已知坑)看 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## 文档

| 文档 | 讲什么 |
|---|---|
| [`docs/交接说明.md`](docs/交接说明.md) | **先读这个**:环境、踩过的坑、代码地图、当前进度与待办 |
| [`docs/交接说明-2026-10-28.md`](docs/交接说明-2026-10-28.md) | **最新一轮(1.5.1 版本收口)**:关键逻辑、运行方式、七个坑、下一步顺序 |
| [`docs/待办清单-2026-10-28.md`](docs/待办清单-2026-10-28.md) | 待办逐项拆解:优先级、预期产出、关键依赖、阻塞点 |
| [`docs/真机验收-2026-10-28.md`](docs/真机验收-2026-10-28.md) | 1.5.0 四项真机验收的实测记录与证据 |
| [`docs/代码地图.md`](docs/代码地图.md) | 代码在哪、为什么这么分;分层方向与三条结构约束(有测试守着) |
| [`docs/写入口清单.md`](docs/写入口清单.md) | 写库走哪个入口;写完谁负责刷新;新增写路径的三步检查 |
| [`docs/交接说明-2026-10-26.md`](docs/交接说明-2026-10-26.md) | 上一轮(结构整理)的交接:改了什么、怎么跑、下一步按什么顺序 |
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
