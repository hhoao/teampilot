import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class SystemFonts {
  static final SystemFonts _instance = SystemFonts._internal();

  factory SystemFonts() {
    return _instance;
  }

  SystemFonts._internal() {
    _fontDirectories.addAll(_getFontDirectories());
  }

  final List<String> _fontDirectories = [];

  final List<String> _fontPaths = [];
  final Map<String, String> _fontMap = {};
  final List<String> _loadedFonts = [];
  List<String>? _nativeFamilyCache;
  /// True when [listNativeFontFamilies] came from fontconfig (Skia-resolvable
  /// family names). False when falling back to file basenames that need
  /// [loadFont].
  bool nativeFamiliesFromFontconfig = false;

  List<String> _getFontDirectories() {
    if (Platform.isWindows) {
      return [
        '${Platform.environment['windir']}/fonts/',
        '${Platform.environment['USERPROFILE']}/AppData/Local/Microsoft/Windows/Fonts/',
      ];
    }
    if (Platform.isMacOS) {
      return [
        '/Library/Fonts/',
        '/System/Library/Fonts/',
        '${Platform.environment['HOME']}/Library/Fonts/',
      ];
    }
    if (Platform.isLinux) {
      return [
        '/usr/share/fonts/',
        '/usr/local/share/fonts/',
        '${Platform.environment['HOME']}/.local/share/fonts/',
      ];
    }
    return [];
  }

  bool _isFontFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf');
  }

  /// Collects `.ttf` / `.otf` paths under configured directories (recursive).
  List<String> getFontPaths() {
    if (_fontPaths.isEmpty) {
      final found = <String>{};
      for (final path in _fontDirectories) {
        final dir = Directory(path);
        if (!dir.existsSync()) continue;
        try {
          for (final entity in dir.listSync(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            if (!_isFontFile(entity.path)) continue;
            found.add(entity.path);
          }
        } on FileSystemException {
          // Skip unreadable trees (permissions).
        }
      }
      final sorted = found.toList()..sort();
      _fontPaths.addAll(sorted);
    }
    return _fontPaths;
  }

  /// Map of font key → absolute path. Keys are basenames without extension;
  /// on collision the first path in sorted order wins.
  Map<String, String> getFontMap() {
    if (_fontMap.isEmpty) {
      for (final path in getFontPaths()) {
        final key = p.basenameWithoutExtension(path);
        if (key.isEmpty || key.startsWith('.')) continue;
        _fontMap.putIfAbsent(key, () => path);
      }
    }
    return _fontMap;
  }

  /// Sorted unique font keys for [loadFont] (file basenames — may not match
  /// Skia/fontconfig family names).
  List<String> getFontList() {
    final keys = getFontMap().keys.toList()..sort();
    return keys;
  }

  /// Family names suitable for [TextStyle.fontFamily] without [loadFont].
  ///
  /// Prefers `fc-list` (fontconfig) on Linux/macOS when available so Flutter's
  /// engine can resolve faces via the system font manager. Falls back to
  /// [getFontList] basenames (those typically require [loadFont]).
  Future<List<String>> listNativeFontFamilies() async {
    final cached = _nativeFamilyCache;
    if (cached != null) return cached;

    final fromFc = await _fontconfigFamilies();
    if (fromFc.isNotEmpty) {
      nativeFamiliesFromFontconfig = true;
      return _nativeFamilyCache = List<String>.unmodifiable(fromFc);
    }

    nativeFamiliesFromFontconfig = false;
    return _nativeFamilyCache = List<String>.unmodifiable(getFontList());
  }

  Future<List<String>> _fontconfigFamilies() async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      return const [];
    }
    try {
      final result = await Process.run('fc-list', const [':', 'family']);
      if (result.exitCode != 0) return const [];
      final stdout = result.stdout;
      if (stdout is! String || stdout.isEmpty) return const [];

      final names = <String>{};
      for (final line in stdout.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // fc-list may emit "Family A,Alias B,Alias C"
        for (final part in trimmed.split(',')) {
          final name = part.trim();
          if (name.isEmpty || name.startsWith('.')) continue;
          names.add(name);
        }
      }
      final sorted = names.toList()..sort();
      return sorted;
    } on Object {
      return const [];
    }
  }

  /// Loads [fontName] into Flutter's font registry if present on disk.
  Future<String?> loadFont(String fontName) async {
    if (_loadedFonts.contains(fontName)) {
      return fontName;
    }

    final path = getFontMap()[fontName];
    if (path == null) {
      return null;
    }

    try {
      final bytes = await File(path).readAsBytes();
      final loader = FontLoader(fontName)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      _loadedFonts.add(fontName);
      return fontName;
    } on Object {
      return null;
    }
  }

  /// Loads all discovered fonts (expensive — prefer [loadFont] for one face).
  Future<List<String>> loadAllFonts() async {
    final loadedFonts = <String>[];
    for (final font in getFontList()) {
      final name = await loadFont(font);
      if (name != null) loadedFonts.add(name);
    }
    return loadedFonts;
  }

  /// Loads a font from an absolute `.ttf` / `.otf` path.
  Future<String?> loadFontFromPath(String path) async {
    if (!_isFontFile(path)) {
      return null;
    }

    if (!File(path).existsSync()) {
      return null;
    }

    final key = p.basenameWithoutExtension(path);
    _fontMap.putIfAbsent(key, () => path);
    return loadFont(key);
  }

  /// Adds fonts from an extra directory (non-recursive for compatibility).
  void addAdditionalFontDirectory(String path) {
    if (!Directory(path).existsSync()) {
      return;
    }

    for (final e in Directory(path).listSync()) {
      if (e is! File || !_isFontFile(e.path)) continue;
      final key = p.basenameWithoutExtension(e.path);
      if (key.isEmpty || key.startsWith('.')) continue;
      _fontMap.putIfAbsent(key, () => e.path);
    }
  }

  void rescan() {
    _fontMap.clear();
    _fontPaths.clear();
    _nativeFamilyCache = null;
    nativeFamiliesFromFontconfig = false;
  }
}
