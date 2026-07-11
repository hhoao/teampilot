import 'package:flutter/foundation.dart';
import 'package:system_fonts/system_fonts.dart';

/// Discovers installed desktop font family names for [TextStyle.fontFamily].
///
/// Prefers fontconfig (`fc-list`) family names that Skia can resolve without
/// [SystemFonts.loadFont]. Falls back to file basenames (those need load).
abstract final class InstalledFontEnumerator {
  static List<String>? _cache;
  static bool? _fromFontconfig;

  /// Whether the last [listFamilies] result uses system-resolvable names.
  static bool get usesSystemFontManager => _fromFontconfig ?? false;

  /// Cached, sorted family names.
  static Future<List<String>> listFamilies() async {
    final cached = _cache;
    if (cached != null) return cached;

    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _fromFontconfig = false;
      return _cache = const [];
    }

    try {
      final fonts = SystemFonts();
      final list = await fonts.listNativeFontFamilies();
      _fromFontconfig = fonts.nativeFamiliesFromFontconfig;
      return _cache = List<String>.unmodifiable(list);
    } on Object {
      _fromFontconfig = false;
      return _cache = const [];
    }
  }

  /// Test / settings refresh hook.
  static void clearCache() {
    _cache = null;
    _fromFontconfig = null;
    try {
      SystemFonts().rescan();
    } on Object {
      // Ignore — package may be unused in tests.
    }
  }
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
