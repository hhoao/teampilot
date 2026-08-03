import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/logging/logger.dart';
import 'system_fonts.dart';
import 'app_font_resolver.dart';
import 'font_catalog.dart';

/// Families already registered this process — skip re-[FontLoader.load], which
/// can invalidate every [RenderParagraph] and cause multi-second layouts.
final Set<String> _loadedFamilies = <String>{};

/// Loads bundled / installed fonts required by [fonts].
///
/// - Bundled mono primary (`monoNeedsBundledLoad`): JetBrains / Ubuntu assets
///   from [FontCatalog].
/// - Silent Ubuntu warm: when `Ubuntu Sans Mono` appears in the mono chain
///   (typical for `system` mono fallbacks), load those assets without treating
///   the preference as a bundled primary.
/// - Bundled UI (`uiNeedsBundledLoad`): Noto Sans SC assets via [FontLoader]
///   under the catalog family name (not GoogleFonts' `*_regular` key).
/// - Installed faces (`*NeedsInstalledLoad`): [SystemFonts.loadFont] for the
///   resolved family key.
///
/// Asset load failures are logged; family names on [fonts] are left unchanged
/// so Flutter can fall through [ResolvedFonts] fallbacks.
Future<void> loadFontsFor(ResolvedFonts fonts) async {
  final monoEntries = <FontCatalogEntry>{};

  if (fonts.monoNeedsBundledLoad) {
    monoEntries.add(FontCatalog.entry(FontRole.mono, fonts.resolvedMonoId));
  }

  // Silent Ubuntu warm for system (and bundled) mono fallback chains.
  final monoChain = [fonts.monoFamily, ...fonts.monoFallback];
  if (monoChain.contains(AppFontResolver.ubuntuSansMonoFamily)) {
    monoEntries.add(FontCatalog.entry(FontRole.mono, 'ubuntuSansMono'));
  }

  for (final entry in monoEntries) {
    await _loadBundledCatalogEntry(entry);
  }

  if (fonts.uiNeedsBundledLoad) {
    await _loadBundledUi();
  }

  // Color emoji must be FontLoader-registered; fontconfig name alone is not
  // enough on Flutter Linux (and runtime Google Fonts fetch is disabled).
  await _loadColorEmoji(fonts);

  if (fonts.uiNeedsInstalledLoad) {
    await _loadInstalledFamily(fonts.uiFamily);
  }
  if (fonts.monoNeedsInstalledLoad) {
    await _loadInstalledFamily(fonts.monoFamily);
  }
}

Future<void> _loadColorEmoji(ResolvedFonts fonts) async {
  final chain = <String>{
    ...fonts.uiFallback,
    ...fonts.monoFallback,
  };
  final wantsBundled = chain.contains(AppFontResolver.bundledColorEmojiFamily) ||
      chain.contains(AppFontResolver.bundledColorEmojiGoogleFamily);
  if (!wantsBundled) return;
  if (_loadedFamilies.contains(AppFontResolver.bundledColorEmojiFamily) ||
      _loadedFamilies.contains(AppFontResolver.bundledColorEmojiGoogleFamily)) {
    return;
  }

  // Prefer bundled google_fonts asset (Flutter-compatible CBDT). Many distro
  // NotoColorEmoji.ttf builds paint as monochrome under Flutter/Skia.
  try {
    await GoogleFonts.pendingFonts([GoogleFonts.notoColorEmoji()]);
    _loadedFamilies.add(AppFontResolver.bundledColorEmojiFamily);
    _loadedFamilies.add(AppFontResolver.bundledColorEmojiGoogleFamily);
    return;
  } on Object catch (error, stackTrace) {
    appLogger.w(
      'Failed to load bundled color emoji font (Noto Color Emoji)',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    final loaded = await SystemFonts().loadFont(
      AppFontResolver.bundledColorEmojiFamily,
    );
    if (loaded != null) {
      _loadedFamilies.add(AppFontResolver.bundledColorEmojiFamily);
    }
  } on Object catch (error, stackTrace) {
    appLogger.w(
      'Failed to load system color emoji font',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _loadBundledUi() async {
  // Register under catalog `bundledFamily` (`Noto Sans SC`). Do not use
  // GoogleFonts.pendingFonts here — that FontLoader key is
  // `Noto Sans SC_regular`, while [buildAppUiTextTheme] applies
  // `fontFamily: Noto Sans SC`, so Android never hits the bundled face.
  await _loadBundledCatalogEntry(
    FontCatalog.entry(FontRole.ui, 'notoSansSc'),
  );
}

Future<void> _loadInstalledFamily(String family) async {
  if (family.isEmpty || _loadedFamilies.contains(family)) return;
  try {
    final loaded = await SystemFonts().loadFont(family);
    if (loaded == null) {
      appLogger.w('Installed font not found or failed to load: $family');
      return;
    }
    _loadedFamilies.add(family);
  } on Object catch (error, stackTrace) {
    appLogger.w(
      'Failed to load installed font: $family',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _loadBundledCatalogEntry(FontCatalogEntry entry) async {
  final family = entry.bundledFamily;
  final paths = entry.assetPaths;
  if (family == null || paths.isEmpty) return;
  if (_loadedFamilies.contains(family)) return;

  if (paths.length == 1) {
    await loadFontAsset(FontLoader(family), paths.single, family: family);
    return;
  }

  final loader = FontLoader(family);
  var hasFont = false;
  for (final asset in paths) {
    try {
      loader.addFont(rootBundle.load(asset));
      hasFont = true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        'Failed to load font asset: $asset',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  if (!hasFont) return;
  try {
    await loader.load();
    _loadedFamilies.add(family);
  } on Object catch (error, stackTrace) {
    appLogger.w(
      'Failed to register font family: $family',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Loads a single font asset into [loader] and registers the family.
///
/// Shared by terminal / theme font loading. Failures are logged; callers keep
/// the preferred family name so Flutter can use fallbacks.
Future<void> loadFontAsset(
  FontLoader loader,
  String assetPath, {
  String? family,
}) async {
  final key = family;
  if (key != null && _loadedFamilies.contains(key)) return;
  try {
    loader.addFont(rootBundle.load(assetPath));
    await loader.load();
    if (key != null) _loadedFamilies.add(key);
  } on Object catch (error, stackTrace) {
    appLogger.w(
      'Failed to load font asset: $assetPath',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
