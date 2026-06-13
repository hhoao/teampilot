import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Invokes [action], swallowing [MissingPluginException] (e.g. widget tests).
Future<T?> windowManagerCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on MissingPluginException {
    return null;
  }
}

/// Whether the macOS Option (⌥) modifier is held at click time.
bool isMacOptionKeyPressed() => HardwareKeyboard.instance.isAltPressed;

/// Whether the window fills the display: macOS native fullscreen or zoomed
/// maximize on other desktops.
Future<bool> isDesktopWindowExpanded() async {
  if (Platform.isMacOS) {
    final fullScreen =
        await windowManagerCall(windowManager.isFullScreen) ?? false;
    if (fullScreen) return true;
  }
  return await windowManagerCall(windowManager.isMaximized) ?? false;
}

/// macOS green button: fullscreen by default, zoom-maximize when [optionPressed].
Future<void> handleMacGreenButton({required bool optionPressed}) async {
  if (optionPressed) {
    await toggleDesktopWindowZoom();
  } else {
    await toggleDesktopWindowExpand();
  }
}

/// Toggles expanded window state. On macOS the green control enters native
/// fullscreen (separate Space, menu bar hidden); Windows/Linux use maximize.
Future<void> toggleDesktopWindowExpand() async {
  if (Platform.isMacOS) {
    final fullScreen =
        await windowManagerCall(windowManager.isFullScreen) ?? false;
    if (fullScreen) {
      await windowManagerCall(() => windowManager.setFullScreen(false));
      return;
    }
    await windowManagerCall(() => windowManager.setFullScreen(true));
    return;
  }

  final maximized =
      await windowManagerCall(windowManager.isMaximized) ?? false;
  if (maximized) {
    await windowManagerCall(windowManager.unmaximize);
  } else {
    await windowManagerCall(windowManager.maximize);
  }
}

/// macOS Option (⌥) + green: zoom maximize without native fullscreen.
Future<void> toggleDesktopWindowZoom() async {
  if (!Platform.isMacOS) return;

  final fullScreen =
      await windowManagerCall(windowManager.isFullScreen) ?? false;
  if (fullScreen) {
    await windowManagerCall(() => windowManager.setFullScreen(false));
    await windowManagerCall(windowManager.maximize);
    return;
  }

  final maximized =
      await windowManagerCall(windowManager.isMaximized) ?? false;
  if (maximized) {
    await windowManagerCall(windowManager.unmaximize);
  } else {
    await windowManagerCall(windowManager.maximize);
  }
}
