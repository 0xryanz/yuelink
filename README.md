# YueLink

**by [Yue.to](https://yue.to)**

跨平台代理客户端，基于 Flutter + [mihomo](https://github.com/MetaCubeX/mihomo) 内核。

支持平台：Android / iOS / macOS / Windows / Linux

## 环境要求

| 工具 | 版本 | 说明 |
|------|------|------|
| Flutter | >= 3.22 | UI 框架 |
| Dart | >= 3.4 | 随 Flutter 附带 |
| Go | >= 1.22 | 编译 mihomo 核心 |
| Android SDK + NDK | NDK r26+ | Android 构建 |
| Xcode | >= 15 | iOS / macOS 构建 |
| MinGW-w64 | — | macOS/Linux 上交叉编译 Windows |

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/user/yuelink.git
cd yuelink
git submodule update --init --recursive
```

### 2. 编译 mihomo 核心

```bash
# 构建当前平台（以 macOS arm64 为例）
dart setup.dart build -p macos -a arm64

# 构建 Android 全架构（arm64 + arm + x86_64）
dart setup.dart build -p android

# 构建 iOS
dart setup.dart build -p ios

# 将编译产物复制到 Flutter 工程目录
dart setup.dart install -p android
```

查看所有选项：

```bash
dart setup.dart
```

### 3. 运行 Flutter 应用

```bash
flutter pub get
flutter run
```

## 项目结构

```
yuelink/
├── core/                        # Go 核心层
│   ├── hub.go                   # CGO 导出函数入口
│   ├── state.go                 # 核心状态管理
│   ├── go.mod
│   └── mihomo/                  # mihomo 源码 (git submodule)
├── lib/                         # Flutter/Dart 代码
│   ├── main.dart
│   ├── ffi/                     # dart:ffi 绑定
│   │   ├── core_bindings.dart   # C 函数绑定
│   │   └── core_controller.dart # Dart 侧核心控制器
│   ├── models/                  # 数据模型
│   ├── providers/               # Riverpod 状态管理
│   ├── pages/                   # UI 页面
│   └── services/                # 平台服务抽象
├── android/                     # Android 平台代码 (VpnService)
├── ios/                         # iOS 平台代码 (NetworkExtension)
├── macos/                       # macOS 平台代码
├── windows/                     # Windows 平台代码
├── linux/                       # Linux 平台代码
├── plugins/                     # 自定义 Flutter 插件
├── setup.dart                   # 核心编译脚本
└── pubspec.yaml
```

## 架构

```
┌──────────────────────────────────┐
│          Flutter UI (Dart)       │
│      Riverpod 状态管理            │
├──────────────────────────────────┤
│       CoreController (Dart)      │
│        dart:ffi 桥接层            │
├──────────────────────────────────┤
│        hub.go (CGO //export)     │
│          Go 薄封装层              │
├──────────────────────────────────┤
│         mihomo 代理引擎           │
│   tunnel / listener / resolver   │
└──────────────────────────────────┘
         ↕ TUN / 系统代理
┌──────────────────────────────────┐
│       平台原生 VPN 服务           │
│  Android: VpnService             │
│  iOS/macOS: NEPacketTunnelProvider│
│  Windows: wintun                 │
│  Linux: TUN device               │
└──────────────────────────────────┘
```

### 核心编译方式

- **Android / macOS / Windows / Linux：** `go build -buildmode=c-shared` → 动态库 (`.so` / `.dylib` / `.dll`)
- **iOS：** `go build -buildmode=c-archive` → 静态库 (`.a`)，因为 iOS 禁止加载第三方动态库

### Go → Dart 通信

- **Dart → Go：** 通过 `dart:ffi` 同步调用 CGO 导出的 C 函数
- **Go → Dart：** 通过 `NativePort` + `ReceivePort` 异步事件推送（流量统计、日志、延迟测试结果）

## 构建命令

| 命令 | 说明 |
|------|------|
| `dart setup.dart build -p <platform>` | 编译指定平台的 mihomo 核心 |
| `dart setup.dart build -p <platform> -a <arch>` | 编译指定平台和架构 |
| `dart setup.dart install -p <platform>` | 复制编译产物到 Flutter 工程 |
| `dart setup.dart clean` | 清理所有编译产物 |
| `flutter pub get` | 安装 Dart 依赖 |
| `flutter run` | 运行调试版本 |
| `flutter build apk` | 构建 Android APK |
| `flutter build ios` | 构建 iOS |
| `flutter build macos` | 构建 macOS |
| `flutter build windows` | 构建 Windows |

## 配置文件

YueLink 使用 `yuelink.yaml` 作为配置文件，兼容 mihomo/Clash 配置格式。

## 包名信息

| 项目 | 值 |
|------|-----|
| Flutter 包名 | `com.yueto.yuelink` |
| iOS Bundle ID | `com.yueto.yuelink` |
| App 显示名称 | YueLink |
| 配置文件 | `yuelink.yaml` |

## License

MIT
