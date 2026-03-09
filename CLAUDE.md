# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YueLink (by Yue.to) is a cross-platform proxy client built with Flutter + mihomo (Clash.Meta) Go core.
Supports: Android, iOS, macOS, Windows, Linux.

## Build Commands

```bash
# Install Flutter dependencies
flutter pub get

# Compile Go core (requires Go >= 1.22)
dart setup.dart build -p <platform> [-a <arch>]  # android|ios|macos|windows|linux
dart setup.dart install -p <platform>              # Copy libs to Flutter dirs
dart setup.dart clean                              # Remove build artifacts

# Run
flutter run

# Analyze
flutter analyze

# Build release
flutter build apk          # Android
flutter build ios           # iOS
flutter build macos         # macOS
flutter build windows       # Windows
```

## Architecture

```
Flutter UI (Dart, Riverpod) → CoreController (dart:ffi) → hub.go (CGO //export) → mihomo engine
                                                                                       ↕
                                                              Platform VPN service (TUN/system proxy)
```

### Key layers:

- **`core/`** — Go wrapper around mihomo. Exports C functions via `//export` (CGO). Compiled to `.so`/`.dylib`/`.dll` (dynamic) or `.a` (static, iOS only) via `setup.dart`.
- **`lib/ffi/`** — Dart FFI bindings. `CoreBindings` is raw FFI, `CoreController` is the high-level Dart API with memory management.
- **`lib/providers/`** — Riverpod state management. `core_provider.dart` (lifecycle, traffic), `proxy_provider.dart` (nodes, groups), `profile_provider.dart` (subscriptions).
- **`lib/pages/`** — UI: home (connect/disconnect), proxy (node selection), profile (subscriptions), log (connections), settings.
- **`lib/services/`** — Platform abstractions. `VpnService` uses MethodChannel to platform-specific implementations.

### Platform VPN implementations:

| Platform | Mechanism | Location |
|----------|-----------|----------|
| Android | `VpnService` + TUN fd → Go core | `android/.../YueLinkVpnService.kt` |
| iOS | `NEPacketTunnelProvider` (separate process, static lib) | `ios/PacketTunnel/` |
| macOS | System proxy via `networksetup` | `macos/Runner/AppDelegate.swift` |
| Windows | System proxy via registry | `lib/services/platform/windows_proxy.dart` |

### Critical conventions:

- iOS: Go core must be `c-archive` (static library), not `c-shared`. Extension runs in separate process with ~15MB memory limit.
- All C strings returned by Go core must be freed via `FreeCString` — handled automatically by `CoreController._callJsonFunction()`.
- Go core state is protected by a single mutex (`state.go`) — all exported functions must acquire the lock.
- MethodChannel name: `com.yueto.yuelink/vpn` (consistent across all platforms).
- Package/Bundle ID: `com.yueto.yuelink`
- App Group (iOS): `group.com.yueto.yuelink`

## Dependencies

- Flutter >= 3.22, Dart >= 3.4
- Go >= 1.22 (for core compilation)
- `flutter_riverpod` for state management
- `ffi` + `path_provider` + `http` as core Dart deps
- Android NDK r26+ for Android builds
- Xcode >= 15 for iOS/macOS builds
