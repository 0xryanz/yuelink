# YueLink

**by [Yue.to](https://yue.to)** · 跨平台代理客户端

[![Build](https://github.com/onesyue/yuelink/actions/workflows/build.yml/badge.svg)](https://github.com/onesyue/yuelink/actions/workflows/build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.27-blue)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

基于 Flutter + [mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta) 内核，支持 Android / iOS / macOS / Windows / Linux。

## 功能特性

- **多平台支持** — Android (VpnService TUN)、iOS (NetworkExtension)、macOS/Windows (系统代理)、Linux
- **订阅管理** — 添加/编辑/删除/更新订阅，自动解析流量和到期信息，过期提醒
- **代理节点** — 分组展示、搜索筛选、按延迟排序、单节点/批量测速
- **连接监控** — 实时连接列表、搜索过滤、详情查看、一键关闭
- **个性化** — Material 3 设计、亮色/暗色主题、响应式布局
- **Mock 模式** — 无需 Go 核心即可完整运行 UI，适合开发调试

## 截图

> 安装 Xcode 后运行 `flutter run -d macos` 可查看实际效果。Mock 模式下所有页面均可完整交互。

## 环境要求

| 工具 | 版本 | 说明 |
|------|------|------|
| Flutter | >= 3.22 | UI 框架 |
| Dart | >= 3.4 | 随 Flutter 附带 |
| Go | >= 1.22 | 编译 mihomo 核心（可选，有 Mock 模式） |
| Android SDK + NDK | NDK r26+ | Android 构建 |
| Xcode | >= 15 | iOS / macOS 构建 |

## 快速开始

```bash
# 克隆
git clone https://github.com/onesyue/yuelink.git
cd yuelink
git submodule update --init --recursive

# 安装依赖
flutter pub get

# 运行（Mock 模式，无需 Go）
flutter run

# 编译 Go 核心（可选）
dart setup.dart build -p macos -a arm64
dart setup.dart install -p macos
flutter run -d macos
```

## 测试

```bash
flutter test          # 运行全部 49 个测试
flutter analyze       # 静态分析
```

## 项目结构

```
yuelink/
├── core/                        # Go 核心层 (CGO → mihomo)
├── lib/
│   ├── ffi/                     # dart:ffi 绑定 + Mock
│   ├── models/                  # 数据模型 (Profile, Proxy, Traffic)
│   ├── providers/               # Riverpod 状态管理
│   ├── pages/                   # 5 个页面 (首页/代理/配置/日志/设置)
│   └── services/                # 平台服务 + 订阅解析
├── android/                     # VpnService 实现
├── ios/                         # NetworkExtension 实现
├── macos/                       # 系统代理 (networksetup)
├── scripts/                     # 工具脚本
├── setup.dart                   # Go 核心编译脚本
└── test/                        # 单元测试
```

## 架构

```
Flutter UI (Riverpod) → CoreController (dart:ffi) → hub.go (CGO) → mihomo engine
                                                                        ↕
                                                     Platform VPN (TUN / 系统代理)
```

- **iOS**: 静态库 (`c-archive`)，NetworkExtension 独立进程
- **其他平台**: 动态库 (`c-shared`)
- **Mock 模式**: Go 库不存在时自动降级为模拟数据

## 构建命令

| 命令 | 说明 |
|------|------|
| `dart setup.dart build -p <platform> [-a <arch>]` | 编译 Go 核心 |
| `dart setup.dart install -p <platform>` | 复制到 Flutter 工程 |
| `dart setup.dart clean` | 清理编译产物 |
| `flutter build apk` | Android APK |
| `flutter build ios` | iOS |
| `flutter build macos` | macOS |
| `flutter build windows` | Windows |

## 包名

| 项目 | 值 |
|------|-----|
| Package | `com.yueto.yuelink` |
| 配置文件 | `yuelink.yaml` |
| App Group (iOS) | `group.com.yueto.yuelink` |

## License

MIT
