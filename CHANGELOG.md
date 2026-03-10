# Changelog

## 1.0.0 (Unreleased)

### Features
- Cross-platform proxy client (Android, iOS, macOS, Windows, Linux)
- mihomo (Clash.Meta) Go core integration via dart:ffi
- Subscription management with traffic usage and expiry tracking
- Proxy node selection with search, filter, and sort-by-delay
- Connection monitor with search and detail view
- Speed test for individual nodes (long-press) or entire groups
- Settings persistence (theme, active profile, auto-connect)
- Mock mode for UI development without Go core
- Responsive layout (NavigationBar on mobile, NavigationRail on tablet/desktop)
- Pull-to-refresh on profile and proxy pages
- Clipboard import for subscription URLs
- Profile edit (rename, change URL) and copy URL
- Stale subscription warning
- System proxy support (macOS via networksetup, Windows via registry)
- TUN mode support (Android VpnService, iOS NetworkExtension)
- Material 3 design with light/dark theme
- Haptic feedback on connect/disconnect

### Infrastructure
- CI/CD pipeline with multi-platform builds
- Automated testing (49 unit tests)
- Go core build orchestrator (`setup.dart`)
- Custom app icon generation script
