# YueLink Module Runtime — Known Limitations

> Version: Phase 2C  
> Last updated: 2026-04-07

本文档列出 Module Runtime 当前版本的已知限制、根因和建议处理方式。

---

## L-01 Android 用户 CA 信任限制

**现象**：安装 Root CA 后，部分 App 仍然 TLS 握手失败或报证书错误。

**根因**：Android 7.0（API 24）起，应用默认只信任系统 CA（`system` store），不信任用户安装的 CA（`user` store）。只有以下情况例外：
- App 的 `targetSdkVersion < 24`（几乎没有现代 App）
- App 在 `res/xml/network_security_config.xml` 中显式允许用户 CA
- 设备已 Root，CA 推入系统 store

**影响**：绝大多数现代 App（微信、支付宝、抖音等）在未 Root 设备上无法被 MITM 拦截。

**当前处理**：cert guide 页面引导用户安装 CA，但不解决 App 层信任问题。

**无计划绕过**：此限制是 Android 安全架构设计，不可在 userspace 绕过。

---

## L-02 Certificate Pinning 导致 TLS 拦截失败

**现象**：CA 已安装、hostname 已命中，但特定 App 请求报证书错误或直接断连。

**根因**：App 在代码层对特定证书/公钥进行 pinning（如微信、支付宝、国内主流 App）。即使 CA 受信，App 也会拒绝非 pinned 证书。

**影响**：这类 App 的 HTTPS 流量无法被 MITM 拦截。

**当前处理**：无法处理。MITM Engine 会尝试建立连接，App 侧会主动断开。

---

## L-03 只支持 HTTP/1.1，不支持 HTTP/2

**现象**：对支持 HTTP/2 的 App，MITM 代理只能以 HTTP/1.1 进行通信，可能触发协议降级或连接失败。

**根因**：当前 Engine 使用 `net/http` + `bufio.Reader` 手动解析 HTTP/1.1，没有实现 HTTP/2 的 ALPN 协商和帧解析。

**影响**：部分严格要求 HTTP/2 的 API 可能行为异常（极少见）。大多数 App 可以透明降级到 HTTP/1.1。

**计划**：Phase 3+ 可考虑引入 `golang.org/x/net/http2`。

---

## L-04 只支持 Response Script，不支持 Request Script

**现象**：`.sgmodule` 中 `type = http-request` 的脚本被解析但不执行。

**根因**：本版本仅实现了响应侧脚本（pipeline 在拿到 upstream response 后执行）。请求侧注入需要在 `innerReq.Write()` 前加钩子，属于下一阶段工作。

**影响**：依赖 request script 的模块（如修改请求 body、添加鉴权 header 通过脚本逻辑）不生效。

**当前替代**：Request Header Rewrite 可覆盖大多数 "修改请求 header" 场景。

---

## L-05 Response Script 仅支持文本 / JSON body

**现象**：脚本对 `Content-Type: image/*`、`audio/*`、`application/octet-stream` 等二进制响应不执行。

**根因**：二进制内容无法安全转换为 JS 字符串；传入脚本会导致内容损坏。

**影响**：只有 `text/*`、`application/json`、`application/javascript`、`application/xml` 等文本类型进入脚本。

**当前处理**：非文本类型直接跳过脚本步骤，响应原样返回。

---

## L-06 Response Body 1MB 限制

**现象**：脚本看到的 `$response.body` 超过 1MB 时被截断。

**根因**：为防止大 body 导致内存暴涨，`readLimitedBody` 限制读取 1MB。

**影响**：对于超过 1MB 的响应，脚本修改后的 body 可能不完整。

**当前处理**：截断后继续执行，日志输出 `body truncated at 1MB`。

---

## L-07 `$persistentStore` 不持久化

**现象**：脚本调用 `$persistentStore.write(k, v)` 后，下次脚本执行 `$persistentStore.read(k)` 返回 `""`。

**根因**：`$persistentStore` 当前为存根实现，仅记录日志，不实际存储。

**影响**：依赖跨请求状态的脚本（如计数器、Token 缓存）无法正常工作。

**计划**：Phase 3+ 可用 SQLite 或文件 KV 实现。

---

## L-08 `$httpClient` 不支持

**现象**：脚本调用 `$httpClient.get(...)` 等方法报 `TypeError: $httpClient is undefined`。

**根因**：未实现。`$httpClient` 需要在 Go 侧 bridge 一个 HTTP 客户端到 JS VM，并且需要处理异步回调模式（callback 或 Promise），复杂度高。

**影响**：依赖 `$httpClient` 的脚本（如签名计算、Token 获取）无法运行。

---

## L-09 不支持异步脚本（Promise / async-await）

**现象**：脚本中使用 `async function` 或 `Promise` 时，`done()` 可能永远不被调用，脚本超时后原样返回。

**根因**：goja 有基本的 Promise 支持，但没有内置的 EventLoop / microtask pump。`async` 函数返回 Promise，但 Promise 的 resolve 回调不会被自动调度。

**影响**：需要异步操作的脚本（如 fetch-then-modify 模式）无法使用。

**当前处理**：超时机制确保不阻塞主链路（10 秒后原样返回），但性能会受影响。

---

## L-10 WebSocket 流量不拦截

**现象**：WebSocket（`Upgrade: websocket`）流量透明转发，不经过 URL/Header Rewrite 和 Script。

**根因**：WebSocket upgrade 后流量格式不是标准 HTTP，需要单独实现帧解析。

**影响**：WebSocket 相关脚本不生效。

---

## L-11 Map Local 不支持

**现象**：`.sgmodule` 中 `[Map Local]` 段被解析但标记为 unsupported，不执行。

**根因**：Map Local 需要在响应阶段返回本地文件内容，涉及文件系统访问和 MIME 类型处理，未实现。

---

## L-12 模块脚本 JS 下载失败后静默跳过

**现象**：如果模块中 `[Script]` 段引用的 JS 文件 URL 下载失败，该脚本被跳过但模块其他能力（Rule、MITM、Rewrite）仍然生效。

**根因**：`ModuleDownloader._fetchScriptContents` 对下载失败的脚本保留 `scriptContent = null`，`CollectResponseScripts` 会过滤掉 `ScriptContent` 为空的条目。

**影响**：用户不会看到明确的脚本加载失败提示（仅有调试日志）。

**计划**：可在 ModuleDetail 页面展示脚本加载状态。
