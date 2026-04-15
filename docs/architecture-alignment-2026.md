# YueLink 架构对齐准则 2026

## 推荐目录职责

```text
lib/
  domain/<module>/              纯 Entity / Value Object / 业务枚举
  infrastructure/<module>/      Repository / Datasource / Mapper / Transport
  modules/<module>/             Provider / Controller / State / Page / Widget
  core/                         Go core、平台能力、生命周期和底层客户端
  shared/                       跨模块 UI-independent 工具、日志、格式化、通知
```

依赖方向保持单向：

```text
modules -> infrastructure -> domain
modules -> core/shared
infrastructure -> core/shared/domain
domain -> Dart core only
```

## 分层准入规则

### Domain

- 只放纯 Dart 类型：Entity、Value Object、业务 enum、轻量 `fromJson/toJson`。
- 不依赖 Flutter、Riverpod、HTTP、path_provider、platform channel。
- 不保存 UI 状态，例如 loading、selected tab、toast 文案。

### Infrastructure

- Repository 负责 API 调用、Datasource 调用、DTO 到 Entity 的映射、底层异常封装。
- Datasource 负责文件、settings、secure storage、database 等本地持久化。
- 可以依赖 core/shared/domain，但不得 import Riverpod Provider 或 Widget。
- 异常应向上抛出可判断的类型，不能只 `catch (_) {}`；如果为了产品降级必须吞错，
  至少写结构化诊断日志。

### Modules

- Provider/Notifier 负责状态流转、依赖注入、UI state 和副作用边界。
- UI 只 watch/read Provider，不直接拼请求、不直接读写文件、不直接解析底层 REST。
- Notifier 中所有跨 await 后写 state 的路径都要有 dispose guard。
- Timer、StreamSubscription、Controller、WebSocket 订阅必须在 `ref.onDispose` 或
  Widget `dispose` 中释放。

## Provider 边界

- Provider 可以组装 Repository，但不实现 HTTP transport。
- Provider 可以处理认证过期和用户可见副作用，但不要持有大段 mapper。
- 运行时状态按粒度拆分：核心运行状态、页面筛选状态、业务加载状态、后台生命周期状态
  不混成一个全局 Map。
- 对高频流使用 `select`、节流或批量 flush，避免页面整树随每帧 rebuild。

## Repository / Datasource / Mapper 边界

- Repository 方法返回 Entity 或明确的 Result/nullable 降级值，避免把原始
  `Map<String, dynamic>` 泄漏到 UI。
- 原始 JSON 的 `dynamic` 只能在 datasource/mapper 边界出现，进入 domain/modules
  前必须转成强类型。
- 同类 HTTP helper 后续应统一 transport，但不能为了统一破坏现有 host、token、
  fallback 和兼容逻辑。

## 新代码应该怎么写

- 查询展示型模块：参考 `announcements`。
- 有状态和副作用模块：参考 `checkin`，使用 `State + Notifier + Repository +
  LocalDatasource`。
- 新增日志使用 `EventLog.writeTagged(tag, event, context: ...)`，context 不放 token、
  secret、password、完整 URL 查询串。
- 新增异步流程必须写清楚取消点：`ref.onDispose`、`mounted/context.mounted`、Timer
  cancel、StreamSubscription cancel。

## 不再新增的旧写法

- Page/Widget 中直接构造 HTTP client、直接解析远端 JSON、直接持久化 settings。
- Provider 中塞大量请求拼装、异常翻译和模型转换。
- 无上下文 `catch (_) {}`；无 tag 的 `debugPrint`；包含 token/secret 的日志。
- 新模块放进旧式扁平目录，或在 `modules` 下新增不受控的局部基础设施，除非是
  迁移过渡并在审计文档中登记。
