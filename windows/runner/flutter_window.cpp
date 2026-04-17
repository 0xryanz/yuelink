#include "flutter_window.h"

#include <optional>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
// Native safety net for Windows shutdown / logoff. Dart's ProcessSignal
// doesn't exist on Windows, so when WM_ENDSESSION arrives the Flutter
// engine is about to be killed mid-await. We flip ProxyEnable=0 inline
// via the Win32 registry API — faster than spawning reg.exe, no subprocess,
// completes in microseconds so the OS never truncates us. Idempotent.
void ClearSystemProxyFromRegistry() {
  HKEY hKey = nullptr;
  const LSTATUS open = RegOpenKeyExW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
      0, KEY_SET_VALUE, &hKey);
  if (open != ERROR_SUCCESS) return;
  DWORD zero = 0;
  RegSetValueExW(hKey, L"ProxyEnable", 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&zero), sizeof(zero));
  RegCloseKey(hKey);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_QUERYENDSESSION:
    case WM_ENDSESSION:
      // System is shutting down / user is logging off — we have a brief
      // window before the OS force-kills the process. The Dart quit handler
      // won't fire (Flutter engine is torn down), so clear the proxy inline.
      ClearSystemProxyFromRegistry();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
