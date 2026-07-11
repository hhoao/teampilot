import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/logger.dart';
import 'app_font_resolver.dart';
import 'font_catalog.dart';

/// Loads bundled UI / mono assets required by [fonts].
///
/// - Bundled mono primary (`monoNeedsBundledLoad`): JetBrains / Ubuntu assets
///   from [FontCatalog].
/// - Silent Ubuntu warm: when `Ubuntu Sans Mono` appears in the mono chain
///   (typical for `system` mono fallbacks), load those assets without treating
///   the preference as a bundled primary.
/// - Bundled UI (`uiNeedsBundledLoad`): Noto Sans SC via GoogleFonts local
///   pipeline.
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
    await _loadMonoCatalogEntry(entry);
  }

  if (fonts.uiNeedsBundledLoad) {
    try {
      // Only Regular is awaited before first paint (keeps launch fast). Other
      // weights are warmed during the boot gate in UiInteractiveWarmup.
      await GoogleFonts.pendingFonts([GoogleFonts.notoSansSc()]);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        'Failed to load bundled UI font (Noto Sans SC)',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

Future<void> _loadMonoCatalogEntry(FontCatalogEntry entry) async {
  final family = entry.bundledFamily;
  final paths = entry.assetPaths;
  if (family == null || paths.isEmpty) return;

  if (paths.length == 1) {
    await loadFontAsset(FontLoader(family), paths.single);
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
Future<void> loadFontAsset(FontLoader loader, String assetPath) async {
  try {
    loader.addFont(rootBundle.load(assetPath));
    await loader.load();
  } on Object catch (error, stackTrace) {
    appLogger.w(
      'Failed to load font asset: $assetPath',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
