# YueLink Module Runtime — Capabilities

> Version: Phase 2C (Response Script)  
> Last updated: 2026-04-07

## 一、当前支持的能力

### 1. 模块管理
| 能力 | 说明 |
|------|------|
| 模块下载 | 从 HTTP/HTTPS URL 下载 `.sgmodule` 文件 |
| 模块解析 | 解析 `[General]` `[Rule]` `[MITM]` `[URL Rewrite]` `[Header Rewrite]` `[Script]` `[Map Local]` 段 |
| 模块持久化 | JSON 存储到 Application Support，含 checksum 去重 |
| 启用 / 禁用 / 删除 | 实时生效，config 立即重新下发 |
| 模块详情展示 | 能力标签、规则列表、解析警告 |
| 自动刷新 | 重新获取模块源文件并更新 |

### 2. 规则注入（Phase 0）
| 能力 | 说明 |
|------|------|
| `[Rule]` 注入 | 将模块 Rule 段注入 mihomo YAML，prepend 到已有规则前 |
| MITM hostname 导流 | 将 MITM 主机名转换为 `DOMAIN` / `DOMAIN-SUFFIX` 规则，指向 `_mitm_engine` 代理 |
| `_mitm_engine` proxy 注入 | 在 `proxies:` 段自动注入/更新 HTTP 代理条目 |
| 缩进自适应 | 检测订阅 YAML 的实际缩进宽度，注入规则与其一致（防止 YAML 解析合并） |
| 幂等更新 | 重复注入只更新端口，不重复插入条目 |

### 3. MITM Engine（Phase 1）
| 能力 | 说明 |
|------|------|
| 引擎启停 | Go 侧 HTTP 代理服务，动态绑定端口（默认 9091，冲突自动回退） |
| 健康检查 | `/ping` 端点 + TCP dial 探活 |
| Root CA 生成 | 4096-bit RSA CA，有效期 10 年，写入 `homeDir/mitm_ca.pem` |
| Root CA 导出 | 导出路径返回给 Dart 侧，支持用户安装到设备 |
| CA 复用 | 已有 CA 不重新生成，重启后自动加载 |
| Leaf cert 动态签发 | 每个 MITM 主机名独立签发叶证书，RSA 2048，有效期 1 年 |
| Leaf cert 缓存 | LRU 缓存避免重复签发，缓存时间 1 年 |

### 4. TLS 终结与 CONNECT 代理（Phase 2A）
| 能力 | 说明 |
|------|------|
| CONNECT passthrough | 非命中主机名的 CONNECT 请求透明转发，不修改流量 |
| TLS 终结 | 命中 MITM 主机名时终结 TLS，向客户端呈现叶证书 |
| HTTP keep-alive 循环 | 每个 TLS 连接上的多个 HTTP/1.1 请求复用同一连接 |
| 上游 TLS 重建 | 向真实服务器重新建立 TLS，SNI 正确设置 |

### 5. URL Rewrite（Phase 2B）
| Action | 说明 |
|--------|------|
| `reject` | 返回 200 空体（不返回 4xx，避免 App 特殊处理） |
| `302` | 302 重定向到指定 URL |
| `307` | 307 临时重定向，保留请求方法 |
| `header`（URL 改写） | 目标 URL 改写为新 URL 后继续转发 |

Pattern 使用正则表达式，匹配完整 URL（`https://host/path?query`）。

### 6. Header Rewrite（Phase 2B）
| Action | 适用 | 说明 |
|--------|------|------|
| `header-add` | 请求 | 添加 header（不覆盖已有值） |
| `header-replace` | 请求 | 替换/新增 header |
| `header-del` | 请求 | 删除 header |
| `response-header-add` | 响应 | 添加响应 header |
| `response-header-replace` | 响应 | 替换/新增响应 header |
| `response-header-del` | 响应 | 删除响应 header |

### 7. Response Script（Phase 2C）
| 能力 | 说明 |
|------|------|
| `http-response` 脚本 | 脚本在响应到达客户端前执行 |
| `$request` 全局对象 | `{method, url, headers}` |
| `$response` 全局对象 | `{status, body, headers}` |
| `done({body, headers})` | 终止脚本并应用修改结果 |
| `console.log(...)` | 日志输出到 `[MITM][Script]` 前缀 |
| `$notification.post(t,s,b)` | 存根，仅记录日志 |
| `$persistentStore.read/write` | 存根，read 永远返回 `""` |
| 文本/JSON body | 仅文本类型（`text/*`、`application/json` 等）进入脚本 |
| 超时控制 | 10 秒硬超时，超时后原样返回响应 |
| 错误隔离 | 脚本错误/panic 不影响主链路，记录日志后原样返回 |
| 1MB body 限制 | 超过 1MB 的 body 截断，脚本看到部分内容 |
| Body 修改 | 脚本返回的 body 替换原响应体，`Content-Length` 自动修正 |
| Header 修改 | 脚本返回的 headers 合并写入响应 Header |

---

## 二、当前不支持的能力

### 脚本相关
| 不支持 | 说明 |
|--------|------|
| `http-request` 脚本 | 请求脚本，不在本版本计划内 |
| `cron` / `generic` 脚本 | 定时任务和通用脚本，超出本版范围 |
| `$httpClient` | Surge 的 HTTP 请求 API，不支持 |
| `$persistentStore`（真实存储） | 当前为存根，不持久化 |
| `$notification`（真实通知） | 当前为存根，不弹系统通知 |
| `arguments` | 脚本参数传递，不支持 |
| 完整 Surge Script 兼容性 | 不保证与 Surge 生态脚本 100% 兼容 |
| 复杂异步脚本 | 不支持 Promise / async-await 模式 |
| `require()` / ES modules | 不支持模块导入 |

### 模块能力
| 不支持 | 说明 |
|--------|------|
| Map Local | 本地映射，不支持 |
| Panel | Surge Dashboard Panel，不支持 |
| `http-request` URL Rewrite（`header` action） | URL 改写后继续转发，不支持 |

### 协议与传输
| 不支持 | 说明 |
|--------|------|
| HTTP/2 MITM | 目前仅支持 HTTP/1.1 |
| WebSocket 拦截 | WebSocket upgrade 不拦截，透明转发 |
| 非 TLS 明文 HTTP 拦截 | 仅拦截 CONNECT 隧道内的 HTTPS 流量 |
| UDP 流量 | 不拦截 UDP |

---

## 三、产品边界

### 本功能定位
YueLink Module Runtime 是 Surge 模块兼容层的**最小可用实现**，目标是让常见的轻量模块（规则注入、简单改写、基础 JSON 响应改写）在 YueLink 中可用，**不是完整的 Surge Script 运行时**。

### 对用户的说明
- 适合：规则模块、简单 reject/redirect、基础 header 操控、轻量 JSON 响应改写
- 不适合：依赖 `$httpClient` 的复杂脚本、依赖 `$persistentStore` 的有状态脚本、依赖 `$notification` 的脚本
- Android 额外限制：用户空间 CA 信任需手动安装，部分 App 因 certificate pinning 不可 MITM
