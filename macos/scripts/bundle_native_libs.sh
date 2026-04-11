#!/bin/bash
# Bundle native binaries (libclash.dylib + service helper + mihomo) into the
# .app at Xcode build time. Self-healing and idempotent — works from a fresh
# checkout, in mock mode, in CI, and in regular production builds.
#
# Called from the "Bundle native libs" Run Script build phase in
# Runner.xcodeproj. Edit THIS file, not the pbxproj inline script.
#
# Contract:
#   - $SRCROOT     → macos/ directory
#   - $TARGET_BUILD_DIR / $FRAMEWORKS_FOLDER_PATH → .app's Contents/Frameworks
#
# Behavior:
#   1. For each binary in NATIVE_BINS, check if it exists in macos/Frameworks.
#   2. If missing AND `dart` + `go` are available, try to build it via
#      setup.dart automatically (so a fresh `flutter build macos` Just Works
#      from a clean checkout).
#   3. If still missing, log it and continue — Dart side has mock-mode
#      fallback for libclash, and the service helper / mihomo are only
#      needed for desktop TUN mode (which is opt-in).
#   4. If present, copy + chmod 755 + ad-hoc codesign.
#
# This replaces the previous inline pbxproj script which hard-failed
# unconditionally on missing libclash.dylib, breaking integration tests
# (which run in mock mode and shouldn't need libclash).

set -eu

# Don't fail the whole Xcode build if individual binaries are missing —
# they're optional and the Dart side handles it gracefully.
set +e

FRAMEWORKS_DST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$FRAMEWORKS_DST"

# List of binaries to try to bundle. Each one is OPTIONAL.
NATIVE_BINS=(
  "libclash.dylib"
  "yuelink-service-helper"
  "yuelink-mihomo"
)

# Try to auto-build missing binaries via setup.dart, but only if the user's
# environment has the toolchain. In CI we explicitly run `dart setup.dart`
# in the build-core job, so this fallback is only for local dev iteration.
auto_build_if_possible() {
  local missing_libclash=0
  if [ ! -f "$SRCROOT/Frameworks/libclash.dylib" ]; then
    missing_libclash=1
  fi
  if [ $missing_libclash -eq 0 ]; then
    return 0
  fi

  # Skip auto-build in CI — the build-core job handles full cross-compile,
  # and the integration job intentionally runs in mock mode (faster + more
  # focused E2E surface). GitHub Actions / GitLab / most CIs set CI=true.
  if [ "${CI:-}" = "true" ]; then
    echo "[bundle_native_libs] CI environment detected — skipping auto-build (mock mode)"
    return 0
  fi

  if ! command -v dart >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v go >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -d "$SRCROOT/../core/mihomo" ] || [ -z "$(ls -A "$SRCROOT/../core/mihomo" 2>/dev/null)" ]; then
    echo "[bundle_native_libs] core/mihomo submodule not initialised — skip auto-build"
    return 0
  fi

  echo "[bundle_native_libs] libclash.dylib missing — attempting auto-build via setup.dart"
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64)  arch=amd64 ;;
    arm64)   arch=arm64 ;;
    aarch64) arch=arm64 ;;
  esac
  (
    cd "$SRCROOT/.."
    dart setup.dart build -p macos -a "$arch" 2>&1 | sed 's/^/[setup.dart build] /' | tail -10
    dart setup.dart install -p macos 2>&1 | sed 's/^/[setup.dart install] /' | tail -5
  ) || true
}

auto_build_if_possible

bundled=0
skipped=0
for bin in "${NATIVE_BINS[@]}"; do
  src="$SRCROOT/Frameworks/$bin"
  dst="$FRAMEWORKS_DST/$bin"
  if [ -f "$src" ]; then
    cp -f "$src" "$dst"
    chmod 755 "$dst"
    codesign --force --sign - "$dst" 2>&1 | sed 's/^/[codesign] /' | tail -3
    bundled=$((bundled + 1))
    echo "[bundle_native_libs] ✓ $bin"
  else
    skipped=$((skipped + 1))
    echo "[bundle_native_libs] · $bin missing — runtime mock mode (or feature disabled)"
  fi
done

echo "[bundle_native_libs] done: $bundled bundled, $skipped skipped"

# Always exit 0 — missing binaries are NOT a build failure, they trigger
# mock mode at runtime. The Dart-side _isNativeAvailable check handles
# the libclash case; service mode UI checks ServiceManager.isInstalled().
exit 0
