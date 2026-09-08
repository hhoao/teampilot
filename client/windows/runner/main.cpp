#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// True when |msg| is an Alt+<key> system key-down from the plain (left) Alt,
// i.e. an app shortcut chord. Alt+Space (system menu), AltGr (right Alt, used
// by European layouts for character input) and Alt+numpad (Windows Alt-codes)
// must keep the default translation.
bool IsPlainAltChordSysKeyDown(const MSG &msg) {
  if (msg.message != WM_SYSKEYDOWN || msg.wParam == VK_SPACE) {
    return false;
  }
  if (msg.wParam >= VK_NUMPAD0 && msg.wParam <= VK_NUMPAD9) {
    return false;
  }
  const bool left_alt = (::GetKeyState(VK_LMENU) & 0x8000) != 0;
  const bool right_alt = (::GetKeyState(VK_RMENU) & 0x8000) != 0;
  return left_alt && !right_alt;
}

}  // namespace

// The boot splash is painted as an in-window overlay (see flutter_window.cpp),
// not the native_splash_screen plugin's separate top-level window.
int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line,
                      _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Keep in sync with kDefaultDesktopWindowSize in lib/main.dart.
  Win32Window::Size size(1380, 960);
  if (!window.Create(L"TeamPilot", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    // Do not translate plain Alt chords into WM_SYSCHAR. The Flutter engine
    // always leaves sys-char messages to DefWindowProc, which plays the
    // Windows "Default Beep" for characters without a matching menu mnemonic
    // (flutter/flutter#111554, #119251). Without the char message the engine
    // dispatches the key-down event directly, so Dart shortcuts (and terminal
    // input, which encodes from the logical key) keep working - only the
    // beep disappears.
    if (!IsPlainAltChordSysKeyDown(msg)) {
      ::TranslateMessage(&msg);
    }
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
