# 协作配置 · 从拿到地址到能稳定 push

> 适用对象：已经拿到本仓库 **Write 权限** 的协作者。
> 目标：**5 分钟内**把一台新机器配到「能拉、能跑、能推」，不踩已知的坑。
> 代码地图、表结构、测试说明不在这里 —— 那些看 [`docs/交接说明.md`](docs/交接说明.md)。

---

## 0. 先看验收标准

配完应该能做到这四件事，做不到就按对应小节回去查：

- [ ] `git push` 成功，远端能看到自己的分支
- [ ] `flutter analyze` 输出 `No issues found!`
- [ ] `flutter test` 全过（当前 80 条）
- [ ] 知道哪些文件**绝对不能**提交（见第 7 节）

---

## 1. 认证（二选一，GitHub 早就不让用账号密码推代码了）

### 方案 A：Fine-grained Token（推荐，5 分钟）

1. 打开 <https://github.com/settings/tokens?type=beta> → **Generate new token**
2. 填写：
   - **Repository access** → `Only select repositories` → 只勾 `LanMao-213/heita-ledger`
   - **Permissions** → `Contents` 设为 **Read and write**
3. 生成后**立刻复制**（页面一关就再也看不到）
4. 第一次 `git push` 会弹登录框：
   - Username：你的 GitHub 用户名
   - Password：**刚才那个 token**（不是账号密码）
5. Windows 的 Git Credential Manager 会记住，之后不再问

> 只给这一个仓库的读写权，比给账号全权限安全；过期了重发一个即可。

### 方案 B：SSH Key（长期最省心）

```bash
ssh-keygen -t ed25519 -C "你的邮箱"     # 一路回车
cat ~/.ssh/id_ed25519.pub               # 复制输出
```

把公钥粘到 <https://github.com/settings/keys> → **New SSH key**，然后改远端：

```bash
git remote set-url origin git@github.com:LanMao-213/heita-ledger.git
ssh -T git@github.com                   # 应回 Hi <用户名>! You've successfully authenticated
```

22 端口被网络封的话，在 `~/.ssh/config` 里加：

```
Host github.com
  HostName ssh.github.com
  Port 443
```

---

## 2. 拿代码

**新机器：**

```bash
git clone https://github.com/LanMao-213/heita-ledger.git
cd heita-ledger
./tools/pub_get.sh          # 装依赖，见下方注意
```

**已有旧副本**（比如你上次那份基于 `4c009fe` 的）：

```bash
git pull --ff-only origin main
```

> ⚠️ **先 pull 再动手**。`main` 已经比你上次的基线新了 3 个提交
> （`1e79476` → `7730a73` → `b094f99`），不拉就会分叉，之后每轮合并都要处理冲突。

> ⚠️ **装依赖用 `./tools/pub_get.sh`，别直接 `flutter pub get`**。
> 仓库里的 `pubspec.lock` 是按国内镜像解析的，直接跑会按当前源重写 url 字段，
> 版本和 sha256 都不变，但会多出 **87 行脏改动**，很容易被顺手提交进去。

---

## 3. 出网自查（这是你上次真正卡住的地方）

上次 push 报的是 `CONNECT tunnel failed, response 502` —— **不是权限问题，是出网被代理拦了**。
先花 10 秒确认：

```bash
curl -I https://github.com
```

| 结果 | 处理 |
| --- | --- |
| `200` / `301` | 网络没问题，跳过本节 |
| 超时 / `502` / CONNECT failed | 见下面三步 |

1. **在系统终端里推**（独立开一个 PowerShell / Git Bash），不要在 WorkBuddy 沙箱里推 ——
   沙箱有代理层，上次就是这里返回 502。
2. 确实需要代理时再配（Clash 常见端口 7890）：

   ```bash
   git config --global http.proxy  http://127.0.0.1:7890
   git config --global https.proxy http://127.0.0.1:7890
   git config --global --unset http.proxy   # 不用了要取消，否则同样报 502
   ```

   **代理配了但代理软件没开，比不配更糟**，记得成对使用。
3. 还是不通就走 bundle 绕开 git：

   ```bash
   git bundle create heita-$(date +%m%d).bundle --all
   ```

---

## 4. 跑起来

```bash
flutter doctor          # 全绿为准（Flutter 3.47.x / Dart 3.13.x）
flutter devices         # 确认手机或模拟器被识别
flutter run             # 首次编译几分钟
```

真机第一次跑之前先看第 8 节的「覆盖安装装不上」，这是签名问题，不是代码问题。

---

## 5. 每天的开工流程

```bash
git pull --ff-only origin main          # 1. 先拉
git checkout -b feat/your-thing         # 2. 开分支，main 永远可运行
# ……写代码……
flutter analyze && flutter test         # 3. 两道闸门
git add -A && git commit -m "feat: 做了什么"
git push -u origin feat/your-thing      # 4. 推分支
```

- 分支命名：`feat/xxx`、`fix/xxx`、`docs/xxx`、`chore/xxx`
- 界面有改动的，`build/visual/` 里的截图一起贴出来（截图是测试生成的，见第 6 节）
- 想直接推 `main` 也可以，但 `main` 上任何时刻都必须能 analyze + test 全过

---

## 6. 闸门与自检

```bash
flutter analyze                              # 必须 0 issue
flutter test                                 # 必须全过
flutter test test/ui_shot_test.dart          # 只跑界面截图自检
```

`flutter test` 会真的把界面渲染成 PNG 放到 `build/visual/`，可以直接看效果；
布局溢出（文字撑破卡片一类）会直接让测试失败，比肉眼可靠。

> ⚠️ **跑测试前必须去掉代理环境变量**，否则 14 个测试文件会全部报
> `Unable to connect to flutter_tester process: Invalid WebSocket upgrade request`
> —— 这是 flutter_tester 的本地 WebSocket 被代理拦了，不是代码坏了。

```bash
# Git Bash / macOS / Linux
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY \
    NO_PROXY=127.0.0.1,localhost,::1 flutter test
```

```powershell
# PowerShell
$env:HTTP_PROXY=""; $env:HTTPS_PROXY=""; $env:NO_PROXY="127.0.0.1,localhost"
flutter test
```

---

## 7. 这些不要提交

已在 `.gitignore` 里，别手动加回来：

| 路径 | 原因 |
| --- | --- |
| `build/`、`.dart_tool/` | 构建产物，几百 MB 到几 GB |
| `android/local.properties` | SDK 路径，每台机器不同 |
| `android/.gradle/`、`*.iml`、`.idea/` | 本机 IDE 状态 |
| `*.jks` / `*.keystore` / `key.properties` | 签名文件，泄露等于别人能给你的 App 签名 |
| 数据库文件、导出的 xlsx、你自己的账目 | 隐私 |

---

## 8. 已知坑（每一条都踩过）

| 现象 | 原因 / 处理 |
| --- | --- |
| push 报 502 / CONNECT failed | 出网被代理拦，见第 3 节 |
| `flutter test` 全部 `Invalid WebSocket upgrade request` | 代理变量没去掉，见第 6 节 |
| 覆盖安装提示「应用未安装」 | release 用 **debug 签名**，每台机器 keystore 不同 → **先卸载旧版** |
| `pubspec.lock` 莫名多 87 行改动 | 直接跑了 `flutter pub get`，改用 `./tools/pub_get.sh` |
| 截图里中文是方块 | 测试环境没中文字形，`ui_shot_test.dart` 已加载 `Deng.ttf`；换 macOS 要改 `PingFang.ttc` |
| 截图里图标是方块 | 图标字体不自动加载，测试里按 `FLUTTER_ROOT` 找 `MaterialIcons-Regular.otf`，SDK 装在别处就设这个环境变量 |
| 多个测试并行报「另一个程序正在使用此文件」 | 各测试文件用各自的 `Db.fileName`，别共用一个库文件 |
| 测试卡住不结束 | `testWidgets` 里直接 `await` 数据库会永久挂住，必须包在 `tester.runAsync` 里 |

---

## 9. 发版

1. **版本号两处要一致**：`pubspec.yaml` 的 `version` + `lib/app.dart` 的 `kAppVersion`
   （当前 `1.1.1+3`，`+` 后面是构建号，每次发版 +1）
2. `flutter analyze` + `flutter test`
3. `flutter build apk --release --split-per-abi`
   产物在 `build/app/outputs/flutter-apk/`：`app-arm64-v8a-release.apk`（多数手机）、
   `app-armeabi-v7a-release.apk`（老机型）、`app-x86_64-release.apk`（模拟器）
4. 装机前先卸载旧版（签名不同）

---

## 10. 配好后的一分钟自检

```bash
git pull --ff-only origin main                                  # 1. 能拉
./tools/pub_get.sh                                              # 2. 依赖能装
flutter analyze                                                 # 3. 应为 No issues found
env -u HTTP_PROXY -u HTTPS_PROXY flutter test                   # 4. 应为 All tests passed
git checkout -b test/push-check
git commit --allow-empty -m "chore: 推送连通性验证"
git push -u origin test/push-check                              # 5. 远端出现该分支 = 全通
git push origin --delete test/push-check                        # 6. 删掉验证分支
```

六步全过，这台机器就算配好了。

---

## 遇到问题先看哪里

1. 出网/push → 第 3 节
2. 测试红 → 第 6 节 + 第 8 节
3. 装机 → 第 8 节「覆盖安装」
4. 代码结构、表结构、某个功能怎么改 → [`docs/交接说明.md`](docs/交接说明.md)
5. 产品边界与「明确不做的事」 → `docs/设计资产/PRD-产品需求文档.html`
