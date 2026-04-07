# YueLink Module Runtime — Architecture

> Version: Phase 2C  
> Last updated: 2026-04-07

## 一、演进历史

```
Phase 0  模块解析 / 持久化 / Rule 注入 / UI
Phase 1  MITM Engine / Root CA / config 导流
Phase 2A TLS 终结 / Leaf Cert / CONNECT 代理
Phase 2B URL Rewrite / Header Rewrite / Rewriter pipeline
Phase 2C Response Script（goja JS runtime）
```

---

## 二、总体分层

```
┌─────────────────────────────────────────────┐
│                 Flutter UI                  │
│  ModulesPage  ModuleDetailPage  CertPage    │
└───────────────────┬─────────────────────────┘
                    │ Riverpod
┌───────────────────▼─────────────────────────┐
│              Dart 业务层                     │
│  moduleProvider   mitmProvider               │
│  MitmNotifier     ModuleDownloader           │
│  ModuleParser     ModuleRuleInjector         │
└───────────────────┬─────────────────────────┘
                    │ FFI (CoreController)
┌───────────────────▼─────────────────────────┐
│              Go hub.go (CGO exports)         │
│  UpdateMITMConfig  StartMITMEngine           │
│  StopMITMEngine    GetMITMEngineStatus       │
│  GenerateRootCA    GetRootCAStatus           │
└───────────────────┬─────────────────────────┘
                    │
┌───────────────────▼─────────────────────────┐
│           Go mitm package                   │
│  engine.go   types.go   module.go           │
│  rewriter.go script.go  cert.go  debug.go   │
└─────────────────────────────────────────────┘
```

---

## 三、Go / Dart 职责分工

### Dart 侧职责
- 模块 `.sgmodule` 文件的下载、解析、持久化
- 模块 enable/disable/delete 状态管理
- 从 ModuleRecord 构建 `MITMConfig` JSON 并通过 FFI 推送给 Go
- 将模块 Rule 和 MITM hostname 注入 mihomo YAML（`ModuleRuleInjector`）
- MITM Engine 启停控制
- Root CA 状态展示与导出引导

### Go 侧职责
- MITM Engine HTTP 代理服务的生命周期
- Root CA 和 Leaf Cert 的生成与缓存
- CONNECT 代理 passthrough / TLS 终结路由
- URL Rewrite / Header Rewrite / Response Script pipeline 执行
- `MITMConfig` 的热更新（运行时 Configure，无需重启）

---

## 四、Config Push 链路

```
用户启用/禁用模块
    │
    ▼
moduleProvider (Dart Riverpod)
    │ ref.listen → pushConfig()
    ▼
MitmNotifier._buildConfigJson(modules)
    │ 构建 {"hostnames":[...],"url_rewrites":[...],"header_rewrites":[...],"scripts":[...]}
    ▼
CoreController.updateMitmConfig(json) [FFI]
    │
    ▼
hub.go: UpdateMitmConfig(json *C.char) *C.char
    │
    ▼
mitm.ConfigureMITMEngine(homeDir, cfg)
    │
    ▼
Engine.Configure()
    │ 更新 mitmHosts / rewriter / scripts（原子性，锁保护）
    │ 对新连接立即生效，已有连接不受影响
    ▼
（完成）
```

mihomo YAML 侧（ModuleRuleInjector）是独立链路：
```
CoreManager.start() → ProfileService.loadConfig() → OverwriteService.apply()
    │
    ▼
ModuleRuleInjector.inject(yaml, mitmPort)
    │ 注入 Rule + _mitm_engine proxy + MITM routing rules
    ▼
ConfigTemplate.process(yaml) → StartCore(yaml)
```

两条链路独立：YAML 注入在核心启动时执行一次；MITMConfig push 在模块变更时随时执行。

---

## 五、MITM Request/Response Pipeline

```
Client (App)
    │ CONNECT host:443
    ▼
Engine.handleConnect()
    ├── host 不在 mitmHosts → passthrough（TCP bridge）
    └── host 在 mitmHosts  → handleConnectMITM()
            │
            ▼ TLS 握手（叶证书）
        ┌──────────────────────────────┐
        │  HTTP/1.1 keep-alive loop    │
        │                              │
        │  1. URL Rewrite              │ ← Rewriter.ApplyURL()
        │     reject → 200 空体 return │
        │     302/307 → 重定向 return  │
        │     (其他 action → 继续)     │
        │                              │
        │  2. Request Header Rewrite   │ ← Rewriter.ApplyRequestHeaders()
        │                              │
        │  3. Forward to Upstream      │ ← tls.Dial + innerReq.Write()
        │                              │
        │  4. Response Script          │ ← RunResponseScriptsOnHTTP()
        │     (仅 text/JSON body)      │
        │                              │
        │  5. Response Header Rewrite  │ ← Rewriter.ApplyResponseHeaders()
        │                              │
        │  6. Write response to client │ ← upstreamResp.Write(tlsConn)
        └──────────────────────────────┘
```

---

## 六、Response Script 执行流程

```
RunResponseScriptsOnHTTP(scripts, req, resp, fullURL)
    │
    ├── isTextContent(Content-Type)? No → return resp unchanged
    │
    ├── readLimitedBody(resp.Body, 1MB) → bodyStr
    │
    ├── for each compiledScript:
    │       pattern.MatchString(fullURL)? No → skip
    │       RunResponseScript(code, ctx)
    │           │
    │           ├── goja.New() → VM
    │           ├── 注入 $request / $response / console / $notification / $persistentStore / done()
    │           ├── time.AfterFunc(10s) → vm.Interrupt("timeout")
    │           ├── vm.RunString(code)
    │           │       │
    │           │       └── script calls done({body, headers})
    │           │               → vm.Interrupt("__done__")
    │           │               → RunString returns InterruptedError("__done__")
    │           │               → 返回 ScriptResult{Modified:true, Body:..., Headers:...}
    │           │
    │           └── 错误 / timeout → ScriptResult{Modified:false, Error:...}
    │
    ├── modified == false → resp.Body = io.NopCloser(original body)
    │
    └── modified == true →
            resp.Header 合并修改
            resp.Body = io.NopCloser(new body)
            resp.ContentLength = len(new body)
            resp.Header["Content-Length"] 更新
            resp.TransferEncoding = nil
```

---

## 七、关键文件索引

### Go (core/mitm/)
| 文件 | 职责 |
|------|------|
| `engine.go` | MITM Engine 生命周期、CONNECT 代理、pipeline 主循环 |
| `types.go` | 所有数据结构（`MITMConfig`、`ModuleRecord`、`MITMScript` 等） |
| `cert.go` | Root CA 生成/加载、Leaf cert 签发、`LeafCertCache` |
| `rewriter.go` | URL Rewrite / Header Rewrite 规则匹配与执行 |
| `script.go` | goja JS 运行时、`RunResponseScript`、`RunResponseScriptsOnHTTP` |
| `module.go` | 从 `[]ModuleRecord` 聚合 hostname rules / rewrites / scripts |
| `debug.go` | 统一日志前缀函数（`logEngine` / `logScript` / `logTLS` 等） |

### Dart (lib/modules/surge_modules/)
| 文件 | 职责 |
|------|------|
| `domain/module_entity.dart` | `ModuleRecord`、`ModuleScript`、`UrlRewriteRule` 等数据类 |
| `infrastructure/module_parser.dart` | `.sgmodule` 文本解析 |
| `infrastructure/module_downloader.dart` | 下载 sgmodule + 下载 http-response script JS |
| `infrastructure/module_repository.dart` | 持久化（文件系统 JSON） |
| `infrastructure/module_rule_injector.dart` | 向 mihomo YAML 注入 Rule / MITM proxy / routing rules |
| `providers/module_provider.dart` | 模块列表 Riverpod state |
| `providers/mitm_provider.dart` | MITM Engine 状态、`_buildConfigJson`、config push |

---

## 八、Android 平台特殊约束

1. **CA 信任**：Android 7+ 默认不信任用户空间 CA。用户必须手动在系统设置中安装 Root CA 证书，且仅对部分 App 生效（`targetSdkVersion < 24` 或 App 配置了 `networkSecurityConfig`）。

2. **Certificate Pinning**：微信、支付宝等主流 App 使用 Certificate Pinning，MITM 拦截会被直接拒绝（TLS 握手后 App 层验证失败）。这是平台行为，无法绕过。

3. **TUN 流量路径**：mihomo TUN 接管全局流量 → mihomo 根据 Rule 将目标 host 导流到 `_mitm_engine` HTTP 代理 → `_mitm_engine` 建立 CONNECT 隧道 → MITM Engine 处理。整个路径在 userspace，不涉及 iptables。

4. **localhost 回环**：`_mitm_engine` 监听 `127.0.0.1:PORT`。Android VPN 模式下 mihomo 与 MITM Engine 通信走 loopback，不经过 TUN，因此 MITM Engine 的上游连接通过 `nativeStartProtect()` socket protect 出口到真实网络。
