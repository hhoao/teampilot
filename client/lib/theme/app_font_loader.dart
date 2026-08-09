import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import '../utils/logging/logger.dart';
import 'system_fonts.dart';
import 'app_font_resolver.dart';
import 'font_catalog.dart';

/// Families already registered this process — skip re-[FontLoader.load], which
/// can invalidate every [RenderParagraph] and cause multi-second layouts.
final Set<String> _loadedFamilies = <String>{};

/// Loads bundled / installed fonts required by [fonts].
///
/// - Bundled mono primary (`monoNeedsBundledLoad`): JetBrains assets.
/// - Bundled UI (`uiNeedsBundledLoad`): Noto Sans SC assets, registered under
///   the catalog family name (not GoogleFonts' `*_regular` key).
/// - Installed faces (`*NeedsInstalledLoad`): [SystemFonts.loadFont].
///
/// Asset load failures are logged; family names on [fonts] are left unchanged
/// so Flutter can fall through [ResolvedFonts] fallbacks.
Future<void> loadFontsFor(ResolvedFonts fonts) async {
  if (fonts.monoNeedsBundledLoad) {
    await _loadBundledCatalogEntry(
      FontCatalog.entry(FontRole.mono, fonts.resolvedMonoId),
    );
  }

  if (fonts.uiNeedsBundledLoad) {
    // Register under catalog `bundledFamily` (`Noto Sans SC`). Do not use
    // GoogleFonts.pendingFonts here — that FontLoader key is
    // `Noto Sans SC_regular`, while [buildAppUiTextTheme] applies
    // `fontFamily: Noto Sans SC`, so Android never hits the bundled face.
    await _loadBundledCatalogEntry(FontCatalog.entry(FontRole.ui, 'notoSansSc'));
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

  // Register the SYSTEM primary faces (e.g. Noto Sans / DejaVu Sans Mono) via
  // fc-match. These are not bundled and otherwise resolve through fontconfig
  // on every paragraph (the original stall). Bundled families are already
  // registered above and are skipped via [_loadedFamilies].
  for (final family in {fonts.uiFamily, fonts.monoFamily}) {
    if (family.isEmpty || _loadedFamilies.contains(family)) continue;
    await _registerFontconfigFamily(family);
  }
}

/// Families that must not be FontLoader-registered from an fc-match (generic
/// aliases, and emoji handled by [_loadColorEmoji]).
const Set<String> _fontLoaderSkipFamilies = {
  'sans-serif',
  'monospace',
  'NotoColorEmoji',
  'NotoColorEmoji_regular',
};

/// Registers a fontconfig-resolved family (e.g. "Noto Sans") into
/// [FontLoader] by resolving the font file via `fc-match`. This makes the
/// System mode's primary faces resolve directly instead of scanning fontconfig
/// per paragraph. Faces at a non-zero collection index (TTC) are skipped —
/// FontLoader has no face-selection API and would bind the wrong (e.g.
/// Japanese) glyphs.
Future<void> _registerFontconfigFamily(String family) async {
  if (family.isEmpty || _loadedFamilies.contains(family)) return;
  if (_fontLoaderSkipFamilies.contains(family)) return;
  try {
    final result = await Process.run(
      'fc-match',
      [family, '--format=%{file}\n%{index}'],
    );
    if (result.exitCode != 0) return;
    final parts = (result.stdout as String? ?? '')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    final path = parts.first;
    final faceIndex = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (path.isEmpty || !File(path).existsSync()) return;
    if (faceIndex != 0) return;
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    _loadedFamilies.add(family);
    appLogger.i(
      '[font-load] registered system family "$family" via FontLoader',
    );
  } on Object catch (error, stackTrace) {
    appLogger.w(
      'Failed to register system font family: $family',
      error: error,
      stackTrace: stackTrace,
    );
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
  final alreadyLoaded =
      _loadedFamilies.contains(AppFontResolver.bundledColorEmojiFamily) ||
      _loadedFamilies.contains(AppFontResolver.bundledColorEmojiGoogleFamily);
  if (alreadyLoaded) return;

  // Prefer bundled google_fonts asset (Flutter-compatible CBDT). Many distro
  // NotoColorEmoji.ttf builds paint as monochrome under Flutter/Skia. Register
  // under BOTH the Google-Fonts key (`NotoColorEmoji_regular`) and the family
  // name used in the fallback chain (`NotoColorEmoji`) — the chain family must
  // resolve directly or every paragraph triggers a fontconfig scan.
  try {
    await GoogleFonts.pendingFonts([GoogleFonts.notoColorEmoji()]);
    _loadedFamilies.add(AppFontResolver.bundledColorEmojiGoogleFamily);
  } on Object catch (error, stackTrace) {
    appLogger.w(
      'Failed to load bundled color emoji font (Noto Color Emoji)',
      error: error,
      stackTrace: stackTrace,
    );
  }
  if (!_loadedFamilies.contains(AppFontResolver.bundledColorEmojiFamily)) {
    // GoogleFonts registers `NotoColorEmoji_regular`, not the chain family
    // name `NotoColorEmoji`. Load the bundled asset under that name too so the
    // fallback chain resolves without fontconfig.
    await _registerFontAssets(
      loader: FontLoader(AppFontResolver.bundledColorEmojiFamily),
      family: AppFontResolver.bundledColorEmojiFamily,
      assets: ['google_fonts/NotoColorEmoji-Regular.ttf'],
    );
  }

  // System NotoColorEmoji.ttf builds often paint monochrome under Skia and,
  // registered under the same family name, would override the bundled CBDT
  // color face. Only fall back to the system face when the bundled one did not
  // register under the chain family name.
  if (!_loadedFamilies.contains(AppFontResolver.bundledColorEmojiFamily)) {
    try {
      final systemLoaded = await SystemFonts().loadFont(
        AppFontResolver.bundledColorEmojiFamily,
      );
      if (systemLoaded != null) {
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
  await _registerFontAssets(
    loader: FontLoader(family),
    family: family,
    assets: paths,
  );
}

/// Adds every [assets] to [loader], loads the family, and records it as
/// registered. Per-asset and registration failures are logged.
Future<void> _registerFontAssets({
  required FontLoader loader,
  required String family,
  required List<String> assets,
}) async {
  var addedAny = false;
  for (final asset in assets) {
    try {
      loader.addFont(rootBundle.load(asset));
      addedAny = true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        'Failed to load font asset: $asset',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  if (!addedAny) return;
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
