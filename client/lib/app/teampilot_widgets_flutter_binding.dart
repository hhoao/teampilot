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
  ///
  /// Must construct [TeampilotWidgetsFlutterBinding] when no binding exists yet.
  /// Returning a pre-existing [WidgetsFlutterBinding] leaves the probe bypass
  /// inactive (seen in test27: Clipboard/LiveText/ProcessText still ~650 ms).
  static WidgetsBinding ensureInitialized() {
    WidgetsBinding? existing;
    try {
      existing = WidgetsBinding.instance;
    } catch (_) {
      existing = null;
    }

    if (existing is TeampilotWidgetsFlutterBinding) {
      _logBypassStatus(existing);
      return existing;
    }
    if (existing != null) {
      assert(() {
        debugPrint(
          'TeampilotWidgetsFlutterBinding: probe bypass inactive — '
          'another binding already installed (${existing.runtimeType}). '
          'Fully restart the app (not hot reload).',
        );
        return true;
      }());
      return existing;
    }

    final created = TeampilotWidgetsFlutterBinding();
    _logBypassStatus(created);
    return created;
  }

  static void _logBypassStatus(WidgetsBinding binding) {
    assert(() {
      final messenger = ServicesBinding.instance.defaultBinaryMessenger;
      final ok = messenger is DesktopTextInputProbeBypassMessenger;
      debugPrint(
        ok
            ? 'Teampilot: DesktopTextInputProbeBypassMessenger active'
            : 'Teampilot: probe bypass MISSING '
                  '(binding=${binding.runtimeType}, '
                  'messenger=${messenger.runtimeType})',
      );
      return true;
    }());
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
