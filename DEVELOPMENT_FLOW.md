# DEVELOPMENT_FLOW.md

本文件描述 YueLink 仓库的分支规范、版本号规则和发布流程。

---

## 分支结构

| 分支 | 用途 | 保护规则 |
|------|------|---------|
| `master` | 稳定正式版，只接收来自 `release` 的 PR | ✅ 必须 PR + CI 通过 |
| `dev` | 日常开发主线，功能、修 bug、UI 调整都进这里 | — |
| `release` | 预发布收口，从 `dev` 合入，只做 bug fix / 文案 / 打包验证 | ✅ 必须 PR + CI 通过 |
| `next` | 高风险实验、新架构探索，不参与正式发布 | — |

**规则：`master` 和 `release` 禁止直接 push，必须通过 PR，且 CI（Analyze & Test）必须通过。**

---

## 版本号规则

采用 [SemVer](https://semver.org/) + 预发布后缀：

```
v<major>.<minor>.<patch>[-<pre>.<n>]
```

| Tag | 含义 | 从哪个分支打 |
|-----|------|------------|
| `v1.0.0-beta.1` | 公开预发布，功能基本完整，可能有 bug | `release` |
| `v1.0.0-beta.2` | 预发布迭代（修复 beta 期间发现的问题） | `release` |
| `v1.0.0-rc.1` | 发布候选，冻结功能，只修关键 bug | `release` |
| `v1.0.0` | 正式稳定版 | `master` |
| `v1.1.0` | 新功能版本 | `master` |
| `v1.1.1` | 修复版本 | `master` |

CI 自动识别：tag 含 `-beta` 或 `-rc` → GitHub Release 标记为 **Pre-release**；`vX.Y.Z` 纯数字 → 标记为 **Latest**。

---

## 发布流程

### 日常开发

```bash
# 所有日常工作都在 dev
git checkout dev
# ... 开发、提交 ...
git push origin dev
```

### 预发布（beta / rc）

```bash
# 1. 确认 dev 稳定，合入 release
git checkout release
git merge dev
git push origin release   # 触发 CI，必须通过

# 2. 打 beta tag（在 release 分支上）
git tag -a v1.0.0-beta.2 -m "描述这次 beta 的主要内容"
git push origin v1.0.0-beta.2
# CI 自动构建全平台产物并创建 GitHub Pre-release
```

### 正式发布（stable）

```bash
# 1. 从 release 向 master 发 PR，CI 通过后合并
# （GitHub 网页操作，不要直接 push master）

# 2. 在 master 上打正式 tag
git checkout master
git pull
git tag -a v1.0.0 -m "YueLink v1.0.0 正式版"
git push origin v1.0.0
# CI 自动构建并创建 GitHub Latest Release

# 3. 将 master 的 tag commit 同步回 dev（保持版本一致）
git checkout dev
git merge master
git push origin dev
```

### 重大实验 / 高风险重构

```bash
git checkout next
# 在 next 上随意折腾，不影响 dev / release / master
# 确认方案可行后，cherry-pick 或 PR 合回 dev
```

---

## 不允许的操作

- ❌ 直接 `git push origin master`
- ❌ 直接 `git push origin release`
- ❌ 在 `master` 或 `release` 上做日常开发提交
- ❌ 从 `next` 直接发布
- ❌ 使用 `alpha.*` 或 `v0.x.x` 格式的 tag（旧格式，已清理）
- ❌ `--force push` 任何分支

---

## CI 触发规则

| 事件 | 触发的 Job |
|------|-----------|
| push 到 `master` / `dev` / `release` | Analyze & Test（代码分析 + 单元测试） |
| PR 到 `master` / `dev` / `release` | Analyze & Test |
| push `v*` tag（任意分支） | 全平台构建 + GitHub Release |

全平台构建产物：

| 产物 | 平台 |
|------|------|
| `YueLink-<version>-windows-amd64-setup.exe` / `YueLink-<version>-windows-amd64-portable.zip` | Windows x64 |
| `YueLink-<version>-macos-universal.dmg` | macOS Universal（arm64 + x86_64） |
| `YueLink-<version>-android-universal.apk` + 分 ABI APK | Android（arm64 / arm / x86_64） |
| `YueLink-<version>-ios.ipa` | iOS（无签名） |
| `YueLink-<version>-linux-amd64.AppImage` | Linux x86_64 |
