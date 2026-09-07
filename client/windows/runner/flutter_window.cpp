#include "flutter_window.h"

#include <optional>

#include <native_splash_screen_windows/native_splash_screen_windows_plugin_c_api.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

WNDPROC FlutterWindow::original_child_proc_ = nullptr;

LRESULT CALLBACK FlutterWindow::ChildContentProc(HWND window,
                                                 UINT const message,
                                                 WPARAM const wparam,
                                                 LPARAM const lparam) noexcept {
  // Windows translates Alt+<letter> into WM_SYSCHAR (keyboard focus lives on
  // this child window, so the runner's own WndProc never sees it). The Flutter
  // engine passes sys-chars it does not consider handled to DefWindowProc,
  // which plays the "Default Beep" for characters without a matching menu
  // mnemonic - even when a Dart shortcut already fired on the chord
  // (flutter/flutter#111554, #119251). Swallow the sys-char instead: shortcuts
  // and terminal input are driven by WM_SYSKEYDOWN, which still flows through.
  //
  // Exceptions kept on the default path:
  // - Alt+Space (system menu).
  // - AltGr input (right Alt without left Alt, optionally with Ctrl): European
  //   layouts deliver those characters through the sys-char message.
  if (message == WM_SYSCHAR && wparam != VK_SPACE) {
    const bool left_alt = (GetKeyState(VK_LMENU) & 0x8000) != 0;
    const bool right_alt = (GetKeyState(VK_RMENU) & 0x8000) != 0;
    if (left_alt && !right_alt) {
      return 0;
    }
  }
  return CallWindowProc(original_child_proc_, window, message, wparam,
                        lparam);
}

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

  // Intercept Alt+<letter> sys-chars on the Flutter view (see
  // ChildContentProc) so app shortcuts like the floating-workspace toggle do
  // not ring the Windows "Default Beep" on every press.
  original_child_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      flutter_controller_->view()->GetNativeWindow(), GWLP_WNDPROC,
      reinterpret_cast<LONG_PTR>(ChildContentProc)));

  // Overlay-mode boot splash: stack the splash over the Flutter view in THIS
  // window (instead of a separate top-level splash window). Dart fades it out
  // via close() once the app has painted. Matches the Linux runner.
  AttachSplashOverlay(GetHandle());

  // Drop the native caption so the first Show paints full-client white+logo
  // (Linux starts undecorated). Dart/window_manager then owns the chrome.
  HWND hwnd = GetHandle();
  DWORD style = GetWindowLong(hwnd, GWL_STYLE);
  SetWindowLong(hwnd, GWL_STYLE, style & ~WS_CAPTION);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  ResizeSplashOverlay(hwnd);

  // TeamPilot shows before window_manager.setTitleBarStyle(hidden). Mark the
  // HWND now so Shell never treats the caption-less window as rude fullscreen
  // (auto-hide taskbar still pops when maximized). Cleared only for true
  // fullscreen by the vendored window_manager.
  SetProp(hwnd, L"NonRudeHWND", reinterpret_cast<HANDLE>(TRUE));

  // Show immediately so the overlay is visible during Dart bootstrap - do not
  // wait for the first Flutter frame (that would flash a blank window).
  Show();

  // Flutter can complete the first frame before plugins finish wiring. Keep a
  // pending frame so the engine stays warm under the splash.
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
    if (message == WM_SIZE) {
      // Keep the splash overlay covering the client when chrome/DPI changes,
      // even if Flutter/window_manager already handled the size message.
      ResizeSplashOverlay(hwnd);
    }
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SIZE: {
      const LRESULT result =
          Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      ResizeSplashOverlay(hwnd);
      return result;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
