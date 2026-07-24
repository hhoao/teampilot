import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:native_splash_screen/native_splash_screen.dart' as nss;
import 'package:window_manager/window_manager.dart';

/// Android: [FlutterNativeSplash.preserve] + [FlutterNativeSplash.remove].
/// Desktop: native splash dismissed after bootstrap.
void preserveBootSplash(WidgetsBinding binding) {
  if (Platform.isAndroid) {
    FlutterNativeSplash.preserve(widgetsBinding: binding);
  }
}

Future<void> _nativeSplashCall(Future<void> Function() action) async {
  try {
    await action();
  } on MissingPluginException {
    // Widget tests / incomplete runner builds must not abort boot.
  }
}

/// Pin the splash on top while the main window maps behind it.
///
/// Linux/Windows paint the splash as an in-window overlay (already above the
/// Flutter view — nothing to restack). macOS still uses a separate splash
/// window that must be re-raised when the main window maps.
Future<void> ensureBootSplashOnTop() async {
  if (Platform.isMacOS) {
    await _nativeSplashCall(nss.ensureOnTop);
  }
}

Future<void> dismissBootSplash() async {
  if (Platform.isAndroid) {
    FlutterNativeSplash.remove();
    return;
  }
  // Linux/Windows (overlay) and macOS (separate window) all dismiss via the
  // plugin's close() — it fades whichever splash is active.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await _nativeSplashCall(
      () => nss.close(animation: nss.CloseAnimation.fade),
    );
  }
}

/// Reveal the frameless Flutter shell, then fade the splash away. Callers should
/// have already swapped in the app UI so the cross-fade lands on the real app.
Future<void> completeBootSplashTransition() async {
  if (Platform.isAndroid) {
    await dismissBootSplash();
    return;
  }
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.setOpacity(1);
  await windowManager.focus();
  await dismissBootSplash();
}
