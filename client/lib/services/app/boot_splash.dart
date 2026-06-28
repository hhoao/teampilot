import 'dart:io';

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

/// Pin the splash on top while the main window maps behind it.
///
/// Linux runs the splash as an in-window overlay (always above the Flutter view,
/// nothing to restack); Windows/macOS run the plugin's separate splash window.
Future<void> ensureBootSplashOnTop() async {
  if (Platform.isWindows || Platform.isMacOS) {
    await nss.ensureOnTop();
  }
}

Future<void> dismissBootSplash() async {
  if (Platform.isAndroid) {
    FlutterNativeSplash.remove();
    return;
  }
  // Linux (overlay) and Windows/macOS (separate window) both dismiss via the
  // plugin's close() — it fades whichever splash is active.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await nss.close(animation: nss.CloseAnimation.fade);
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
