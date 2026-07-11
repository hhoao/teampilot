import 'package:flutter/foundation.dart';
import 'package:system_fonts/system_fonts.dart';

/// Discovers installed desktop font family keys via [SystemFonts].
///
/// Returns an empty list on Android / iOS / web or when scanning fails.
abstract final class InstalledFontEnumerator {
  static List<String>? _cache;

  /// Cached, sorted family keys from the vendored `system_fonts` scan.
  static Future<List<String>> listFamilies() async {
    final cached = _cache;
    if (cached != null) return cached;

    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return _cache = const [];
    }

    try {
      // Directory scan is sync inside the package; hop off the caller microtask.
      await Future<void>.delayed(Duration.zero);
      final list = SystemFonts().getFontList();
      return _cache = List<String>.unmodifiable(list);
    } on Object {
      return _cache = const [];
    }
  }

  /// Test / settings refresh hook.
  static void clearCache() => _cache = null;
}

/// Soft-prioritize monospace-looking names without hiding others.
List<String> sortFamiliesForMonoPicker(Iterable<String> families) {
  final monoLike = <String>[];
  final other = <String>[];
  for (final name in families) {
    if (_looksMonospace(name)) {
      monoLike.add(name);
    } else {
      other.add(name);
    }
  }
  monoLike.sort();
  other.sort();
  return [...monoLike, ...other];
}

bool _looksMonospace(String name) {
  final lower = name.toLowerCase();
  return lower.contains('mono') ||
      lower.contains('consolas') ||
      lower.contains('menlo') ||
      lower.contains('courier') ||
      lower.contains('jetbrains') ||
      lower.contains('fira code') ||
      lower.contains('source code') ||
      lower.contains('hack') ||
      lower.contains('inconsolata') ||
      lower.contains('cascadia');
}
