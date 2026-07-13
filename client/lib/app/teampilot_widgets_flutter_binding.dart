import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/app/desktop_text_input_probe_bypass.dart';

/// [WidgetsFlutterBinding] that short-circuits slow EditableText mount probes
/// on desktop (Clipboard.hasStrings / LiveText / ProcessText).
class TeampilotWidgetsFlutterBinding extends WidgetsFlutterBinding {
  /// Creates the binding if needed. Call instead of
  /// [WidgetsFlutterBinding.ensureInitialized] from [main].
  static WidgetsBinding ensureInitialized() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      TeampilotWidgetsFlutterBinding();
      return WidgetsBinding.instance;
    }
  }

  @override
  BinaryMessenger createBinaryMessenger() {
    final base = super.createBinaryMessenger();
    if (!shouldInstallDesktopTextInputProbeBypass(
      isWeb: kIsWeb,
      isAndroid: !kIsWeb && Platform.isAndroid,
      isIOS: !kIsWeb && Platform.isIOS,
      isLinux: !kIsWeb && Platform.isLinux,
      isWindows: !kIsWeb && Platform.isWindows,
      isMacOS: !kIsWeb && Platform.isMacOS,
    )) {
      return base;
    }
    return DesktopTextInputProbeBypassMessenger(base);
  }
}
