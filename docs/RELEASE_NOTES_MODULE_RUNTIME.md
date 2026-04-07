# Module Runtime Release Notes

---

## 内部技术版

### 版本定位
Module Runtime Phase 0 → 2C，Internal Preview。主链路功能完整，存在平台限制（Android CA 信任）。

### 本次做了什么

**Phase 0 — 模块基础**
- `.sgmodule` 文件下载、解析、持久化（含 checksum 去重）
- 模块启用/禁用/删除，实时生效
- 将模块 Rule 注入 mihomo YAML（prepend，YAML 缩进自适应）
- MITM hostname 转换为 `DOMAIN`/`DOMAIN-SUFFIX` 规则，导流到 `_mitm_engine`
- 幂等更新：重复注入只更新端口，不重复插入

**Phase 1 — MITM Engine**
- Go 侧 HTTP 代理服务，动态端口，健康检查 `/ping`
- Root CA 生成（RSA 4096，10 年），复用，导出到设备
- Dart 侧 `MitmNotifier`，引擎启停，状态展示
- CertGuidePage：引导用户安装 Root CA

**Phase 2A — TLS 终结**
- CONNECT passthrough（非命中 host 透明转发）
- 命中 host：TLS 终结，叶证书动态签发（RSA 2048，LRU 缓存）
- HTTP/1.1 keep-alive 循环，上游 TLS 重建

**Phase 2B — Rewrite**
- URL Rewrite：`reject` / `302` / `307`
- Request Header Rewrite：add / replace / del
- Response Header Rewrite：add / replace / del
- 正则 pattern 匹配完整 URL

**Phase 2C — Response Script**
- goja JS 运行时（无需额外 build tag，常规构建即包含）
- `http-response` 脚本：`$request` / `$response` / `done({body,headers})`
- 10 秒超时，1MB body 限制，错误隔离，panic recovery
- `console.log` / `$notification`(stub) / `$persistentStore`(stub)
- Script 在响应链路位置：upstream response → **response script** → response header rewrite → client
- Dart 侧：`ModuleDownloader` 自动下载 JS 源文件并存入 `ModuleScript.scriptContent`
- Dart 侧：`MitmNotifier._buildConfigJson` 将 scripts 推送给 Go engine

**同期修复**
- Android WiFi 感叹号：`YueLinkVpnService` 加 `availableNetworks` set，三个 NetworkCallback 方法全部维护，`setUnderlyingNetworks` 传完整集合
- YAML 注入缩进 bug：`ModuleRuleInjector.injectRules` 从已有规则检测实际缩进宽度，修复 4-space 订阅被解析器合并成单条规则的 P0 问题

### 涉及核心文件

**Go**
- `core/mitm/script.go` — 完全重写（移除 build tag）
- `core/mitm/types.go` — 新增 `MITMScript`、`Scripts []MITMScript`、`ModuleScript.ScriptContent`
- `core/mitm/module.go` — 新增 `CollectResponseScripts`，`BuildMITMConfig` 含 scripts
- `core/mitm/engine.go` — 加 `scripts` 字段，pipeline 插入 script 步骤
- `core/mitm/debug.go` — 新增 `logScript`

**Dart**
- `lib/modules/surge_modules/domain/module_entity.dart` — `ModuleScript.scriptContent`
- `lib/modules/surge_modules/infrastructure/module_downloader.dart` — `_fetchScriptContents`
- `lib/modules/surge_modules/providers/mitm_provider.dart` — scripts 推送

**Android**
- `android/app/src/main/kotlin/com/yueto/yuelink/YueLinkVpnService.kt` — WiFi 修复

**YAML 修复**
- `lib/modules/surge_modules/infrastructure/module_rule_injector.dart` — 缩进检测

### 当前能力边界
- 支持：Rule / MITM / TLS / URL Rewrite / Header Rewrite / Response Script（text/JSON）
- 不支持：Request Script / `$httpClient` / `$persistentStore`（持久化）/ Map Local / HTTP/2 / WebSocket

### 已知限制
- Android 7+ 用户空间 CA 信任限制，大多数 App 无法被 MITM
- Certificate Pinning 导致部分 App 不可拦截
- Response Script 仅支持文本/JSON，1MB 上限
- 不支持异步脚本（Promise/async-await）
- 详见 `MODULE_RUNTIME_KNOWN_LIMITATIONS.md`

### 测试
- Go：72 tests，全部通过
- Flutter：239 tests，全部通过
- 新增测试：`core/mitm/mitm_script_test.go`（18 项）

### 下一步建议
- Phase 3：考虑 `http-request` 脚本最小支持
- 后续评估 `$persistentStore` 真实持久化（SQLite KV）
- 持续观察 Android CA 信任兼容性

---

## 用户版

### YueLink 模块运行时（Module Runtime）正式上线

**新增功能**

YueLink 现已支持 Surge 兼容模块（`.sgmodule`），可以：

- 加载自定义规则模块，直接扩展代理规则集
- 启用 HTTPS 流量改写（需安装 Root CA 证书）
- 支持 URL 跳转/屏蔽改写
- 支持请求/响应 Header 改写
- 支持基础响应脚本（可用于简单的 JSON 数据处理）

**使用方式**

1. 进入「模块」页面，粘贴模块 URL 并添加
2. 如需 MITM 功能，在证书页面生成并安装 Root CA
3. 启用所需模块，改写功能即时生效

**注意事项**

- HTTPS 拦截需要在设备上手动安装 Root CA 证书
- 部分 App（如微信、支付宝）因系统安全限制无法被拦截，这是正常现象
- 当前脚本功能仅支持响应端基础处理，不支持网络请求等高级 API
- 功能处于 Internal Preview 阶段，建议在测试设备上先行验证

**已知不支持**
- 脚本中使用 `$httpClient` 发起网络请求
- 依赖跨请求状态存储的脚本
- Map Local 本地映射
