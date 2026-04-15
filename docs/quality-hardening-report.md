# YueLink 质量加固报告

日期：2026-04-15

## 本轮改动

- 日志与诊断：`EventLog` 新增 `writeTagged/formatTagged`，统一 tag/event/context
  格式，并对 token、secret、password、authorization 等字段脱敏。
- WebSocket：`MihomoStream` 支持取消重试 delay，非字符串帧、JSON 解析失败、重连
  失败写结构化事件，避免完全吞错。
- Logs：`LogEntriesNotifier` 在 provider 创建时若 core 已运行会立即启动监听；流错误
  进入结构化日志。
- Connections/Traffic：provider 内部增加 dispose guard，避免 microtask、Timer、
  Stream 回调在 provider 释放后继续写状态。
- Checkin/Auth：跨 await 后写 state 的关键路径增加 dispose guard，降低切后台、登出、
  页面释放后的状态写入风险。
- Nodes：单节点测速改为 `try/finally` 清理 testing 状态，失败不再卡住节点。
- Emby：代理端口变化导致图片 cache manager 重建时释放旧 manager。
- Account：保持 `null/[]` 降级行为不变，同时记录结构化失败事件。
- Engineering：应用 analyzer 可自动修复的 const/import/string interpolation 等低风险
  lint 修复，`flutter analyze` 从 55 个 info 降为 0 issues。

## 为什么改

- 本轮优先处理长期运行风险：WebSocket 重连、provider dispose、Timer/Stream 回调、
  日志上下文和弱诊断。
- 不拆 UI、不调样式、不改变页面结构，避免把质量治理和视觉回归混在一起。
- 对冻结区只做审计，不做重排。

## 风险点

- `MihomoStream` 日志增加了少量本地 event.log 写入；已限制重连日志频率，只记录首
  次和每 5 次失败。
- 日志 provider 修复会让“进入日志页时 core 已运行”的场景开始显示日志，这是 bug fix，
  不改变已有 UI 结构。
- analyzer 自动修复只涉及 const、import、doc comment、集合字面量等静态质量项。

## 测试覆盖

- `test/shared/event_log_test.dart`：覆盖结构化日志格式、敏感字段脱敏、长字段截断。
- `test/providers/log_entries_provider_test.dart`：覆盖日志 provider 在 core 已运行后创建
  也能启动监听。
- 既有核心测试继续覆盖 config template、module runtime、core manager、purchase、
  model mapper、XBoard API 等路径。

## 验收结果

- `flutter analyze`：No issues found。
- `flutter test test/shared/event_log_test.dart`：通过。
- `flutter test test/providers/log_entries_provider_test.dart`：通过。
- `flutter test`：全量通过。测试输出中仍有既有 Google Fonts 测试 asset 提示，但
  结果为通过。
- `sh scripts/check_imports.sh`：通过。
- `flutter build macos --debug`：第一次因本机 CocoaPods 非 UTF-8 shell 环境失败；
  使用 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter build macos --debug` 重跑通过，
  产物为 `build/macos/Build/Products/Debug/YueLink.app`。构建输出仅剩依赖包 warning。

## 剩余债务

- 超长 UI 文件需要按页面内部职责拆分，但应单独排期做视觉回归确认。
- Emby 本地 DTO、dashboard REST helper、account/checkin transport 可继续下沉和复用。
- WebSocket fake server/harness 可补充，用于精确验证重连、取消和 malformed frame。
