# 协作配置 · 从拿到地址到能稳定 push

> **仓库已公开（MIT）**，所以分两种情况：
> - **只想看 / 想拿走用**：不用看这份文档，`git clone` 或者网页上 Download ZIP 即可，不需要任何权限。
> - **想往仓库里推代码**：需要仓库主人给你 **Write 权限**（Settings → Collaborators），
>   然后按本文配置。目标：**5 分钟内**把一台新机器配到「能拉、能跑、能推」，不踩已知的坑。
>
> 代码地图、表结构、测试说明不在这里 —— 那些看 [`docs/交接说明.md`](docs/交接说明.md)。

---

## 0. 先看验收标准

配完应该能做到这四件事，做不到就按对应小节回去查：

- [ ] `git push` 成功，远端能看到自己的分支
- [ ] `flutter analyze` 输出 `No issues found!`
- [ ] `flutter test` 全过（条数以 `CHANGELOG.md` 最新一条为准，别在这里写死）
- [ ] 知道哪些文件**绝对不能**提交（见第 7 节），也知道**提交信息本身也是公开的**（见 6.1）

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
git checkout feat/v2-merge  # 默认分支就是它，这条只是确认一下
./tools/pub_get.sh          # 装依赖，见下方注意
```

**已有旧副本：**

```bash
git fetch origin
git checkout feat/v2-merge && git pull --ff-only origin feat/v2-merge
```

> 分支关系：`feat/v2-merge`（最新，默认分支）→ `main`（1.4.4 已发版，是它的祖先）。
> 想跟最新代码就待在 `feat/v2-merge`；`main` 只放已经发出去的版本。

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

### 3.1 报 `schannel: CRYPT_E_NO_REVOCATION_CHECK`（Windows 实测会遇到）

现象：

```
fatal: unable to access 'https://github.com/...': schannel: next InitializeSecurityContext
failed: CRYPT_E_NO_REVOCATION_CHECK (0x80092012)
```

**不是权限问题，也不是仓库问题**，是 Windows 的 schannel（走系统代理时常见）无法完成证书吊销检查。
实测有效的做法是换成 OpenSSL 后端并临时关掉证书校验（只对当前这条命令生效，不改全局配置）：

```bash
env GIT_SSL_NO_VERIFY=1 git -c http.sslBackend=openssl push
```

- `-c http.schannelCheckRevoke=false` **实测无效**，别在上面浪费时间。
- 单独 `http.sslBackend=openssl` 会改报 `unable to get local issuer certificate`，所以两者要一起用。
- 网络抖动时还会遇到 `send-pack: unexpected disconnect` 或 `502`——**重试 2~3 次**通常就过，
  成功后用 `git ls-remote origin refs/heads/<分支>` 核对一下远端 SHA 与本地一致。

### 3.2 推不上去的另一类原因：提交里含 `.github/workflows/`

```
refusing to allow an OAuth App to create or update workflow `.github/workflows/ci.yml` without `workflow` scope
```

GitHub 检查的是**被推送的所有提交**，不是只有最新那个 —— 只要这一段历史里有提交动过
workflow 文件，就需要 token 带 `workflow` 权限。两个解法：

```bash
# ① 给 token 补权限（推荐）
gh auth refresh -h github.com -s workflow

# ② 或者把那次改 workflow 的提交先摘出去再推（分支未被别人拉过时才安全）
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
git checkout feat/v2-merge              # 1. 站在最新线上
git pull --ff-only origin feat/v2-merge # 2. 先拉
git checkout -b feat/your-thing         # 3. 开分支
# ……写代码……
flutter analyze && flutter test         # 4. 两道闸门
git add -A && git commit -m "feat: 做了什么"
git push -u origin feat/your-thing      # 5. 推分支
```

- 分支命名：`feat/xxx`、`fix/xxx`、`docs/xxx`、`chore/xxx`
- 界面有改动的，`build/visual/` 里的截图一起贴出来（截图是测试生成的，见第 6 节）
- **`main` 只放已发版**；日常开发都基于 `feat/v2-merge`。想直接推也可以，但那条线上任何时刻都必须能 analyze + test 全过
- 推上去之后建议开 PR：别人能看 diff，也方便回滚

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

### 6.1 提交信息也算公开内容

仓库是 public，**commit message 一推上去就永久可见**，而且它比文件更难清：

- `git filter-repo --replace-text` 只改**文件内容**，对 message **无效** ——
  必须用 `--replace-message`。2026-10-24 那次脱敏就是漏在这里：文件树清干净了，
  三条提交信息里还留着 `C:/Users/<本机用户名>/...`，全程没人发现。
- 扫描器已经能查：`python tools/privacy_scan.py --messages`（CI 里是
  `--history --messages`，每次 push 与 PR 都跑）。

写提交信息时的红线，和写代码一样：

| 别写 | 改成 |
| --- | --- |
| 本机绝对路径（含真实用户名；反斜杠、双斜杠、结尾无分隔符都算） | `C:/Users/<用户名>/...` 或直接写「本机路径」 |
| 内网地址、真实 IP | `127.0.0.1` / 「内网地址」 |
| 手机号、邮箱、真实姓名 | 「用户反馈」「协作者」 |
| 令牌、口令（哪怕只是举例） | `ghp_xxx` 这种明显占位 |

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
| push 报 `schannel: CRYPT_E_NO_REVOCATION_CHECK` | Windows 证书吊销检查失败，见 3.1（换 openssl 后端 + 临时关校验） |
| push 被拒 `without workflow scope` | 提交历史里动过 `.github/workflows/`，见 3.2（`gh auth refresh -s workflow`） |
| `flutter test` 全部 `Invalid WebSocket upgrade request` | 代理变量没去掉，见第 6 节 |
| 覆盖安装提示「应用未安装」 | 装的是**别的机器签的**包（比如别人打的 debug 包）。正式包用仓库主人的密钥签，可直接覆盖 |
| `pubspec.lock` 莫名多 87 行改动 | 直接跑了 `flutter pub get`，改用 `./tools/pub_get.sh` |
| 截图里中文是方块 | 测试环境没中文字形，`ui_shot_test.dart` 已加载 `Deng.ttf`；换 macOS 要改 `PingFang.ttc` |
| 截图里图标是方块 | 图标字体不自动加载，测试里按 `FLUTTER_ROOT` 找 `MaterialIcons-Regular.otf`，SDK 装在别处就设这个环境变量 |
| 多个测试并行报「另一个程序正在使用此文件」 | 各测试文件用各自的 `Db.fileName`，别共用一个库文件 |
| 测试卡住不结束 | `testWidgets` 里直接 `await` 数据库会永久挂住，必须包在 `tester.runAsync` 里 |

---

## 9. 发版

1. **版本号两处要一致**：`pubspec.yaml` 的 `version` + `lib/app.dart` 的 `kAppVersion`
   （当前 `1.4.5+13`，`+` 后面是构建号，每次发版 +1）
2. `flutter analyze` + `flutter test`
3. 出包（**只出一套配色**，1.4.5 起不再有第二个包）：

   ```bash
   flutter build apk --release --target-platform android-arm64
   # 产物：build/app/outputs/flutter-apk/app-release.apk，约 20 MB
   ```

   要兼顾老机型就换成 `--split-per-abi`，会额外产出 `app-armeabi-v7a-release.apk`。
4. 签名：`android/key.properties` + `*.jks` 由仓库主人持有（**不入库**）。
   有这两个文件时 release 自动用正式密钥签，可以直接覆盖安装；没有则回落到 debug 签名，
   那种包换台机器就装不上，别对外发。
5. 发完在 `CHANGELOG.md` 顶部索引表补一行（版本 / 日期 / 标签 / 签名方式 / 关键变化）。

---

## 10. 配好后的一分钟自检

```bash
git pull --ff-only origin feat/v2-merge                          # 1. 能拉
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
6. 想要图文版的环境搭建步骤 → `docs/设计资产/环境搭建指南.html`（浏览器直接打开）
