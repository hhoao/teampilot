import 'package:flutter/foundation.dart';

import 'font_catalog.dart';
import 'installed_font_enumerator.dart';

/// Resolved UI and mono font families for theme / terminal / editor consumers.
@immutable
final class ResolvedFonts {
  const ResolvedFonts({
    required this.uiFamily,
    required this.uiFallback,
    required this.monoFamily,
    required this.monoFallback,
    required this.uiNeedsBundledLoad,
    required this.monoNeedsBundledLoad,
    required this.uiNeedsInstalledLoad,
    required this.monoNeedsInstalledLoad,
    required this.resolvedUiId,
    required this.resolvedMonoId,
  });

  final String uiFamily;
  final List<String> uiFallback;
  final String monoFamily;
  final List<String> monoFallback;
  final bool uiNeedsBundledLoad;
  final bool monoNeedsBundledLoad;
  final bool uiNeedsInstalledLoad;
  final bool monoNeedsInstalledLoad;
  final String resolvedUiId;
  final String resolvedMonoId;
}

/// Platform font tables and catalog-driven resolution for UI + mono roles.
abstract final class AppFontResolver {
  /// Bundled JetBrains mono family (catalog id `jetbrainsMono`).
  static const String bundledMonoFamily = 'JetBrainsMono NFM';

  static ResolvedFonts resolve({
    required String uiFontId,
    required String monoFontId,
    TargetPlatform? platform,
  }) {
    final resolvedPlatform = platform ?? defaultTargetPlatform;
    final ui = _resolveRole(
      fontId: uiFontId,
      role: FontRole.ui,
      platform: resolvedPlatform,
    );
    final mono = _resolveRole(
      fontId: monoFontId,
      role: FontRole.mono,
      platform: resolvedPlatform,
    );

    return ResolvedFonts(
      uiFamily: ui.family,
      uiFallback: ui.fallback,
      monoFamily: mono.family,
      monoFallback: mono.fallback,
      uiNeedsBundledLoad: ui.needsBundledLoad,
      monoNeedsBundledLoad: mono.needsBundledLoad,
      uiNeedsInstalledLoad: ui.needsInstalledLoad,
      monoNeedsInstalledLoad: mono.needsInstalledLoad,
      resolvedUiId: ui.resolvedId,
      resolvedMonoId: mono.resolvedId,
    );
  }

  static ({
    String family,
    List<String> fallback,
    bool needsBundledLoad,
    bool needsInstalledLoad,
    String resolvedId,
  })
  _resolveRole({
    required String fontId,
    required FontRole role,
    required TargetPlatform platform,
  }) {
    final installedKey = installedFontKey(fontId);
    if (installedKey != null) {
      final fallback = role == FontRole.ui
          ? _systemUiFallback(platform)
          : monoCjkFallback(platform);
      // Fontconfig / system family names resolve via Skia — no FontLoader.
      // File-basename fallbacks still set needsInstalledLoad so loadFontsFor
      // can register the face (see InstalledFontEnumerator.usesSystemFontManager).
      final needsLoad = !InstalledFontEnumerator.usesSystemFontManager;
      return (
        family: installedKey,
        fallback: fallback,
        needsBundledLoad: false,
        needsInstalledLoad: needsLoad,
        resolvedId: installedFontId(installedKey),
      );
    }

    final entry = FontCatalog.entry(role, fontId);
    final resolved = role == FontRole.ui
        ? _resolveUi(entry, platform)
        : _resolveMono(entry, platform);
    return (
      family: resolved.family,
      fallback: resolved.fallback,
      needsBundledLoad: entry.source == FontSourceKind.bundled,
      needsInstalledLoad: false,
      resolvedId: entry.id,
    );
  }

  /// Platform color-emoji faces for [fontFamilyFallback] chains.
  ///
  /// Primary UI/mono faces (Noto Sans SC, JetBrains, …) do not cover emoji.
  /// Linux/Android use the FontLoader family [bundledColorEmojiFamily] (system
  /// basename / Google Fonts), not fontconfig's spaced "Noto Color Emoji".
  static const String bundledColorEmojiFamily = 'NotoColorEmoji';

  /// Google Fonts registers the face as `{family}_regular` via [FontLoader].
  static const String bundledColorEmojiGoogleFamily = 'NotoColorEmoji_regular';

  static List<String> colorEmojiFallback(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const ['Apple Color Emoji'],
      TargetPlatform.windows => const ['Segoe UI Emoji'],
      _ => const [bundledColorEmojiFamily, bundledColorEmojiGoogleFamily],
    };
  }

  /// Platform mono fallback chain (primary excluded). Used by bundled mono,
  /// system mono, and [AppFonts.monoFamilyFallback].
  ///
  /// Latin programmer faces come first (Orca / VS Code style). A Simplified-
  /// Chinese CJK mono face is listed before the generic `monospace` alias:
  /// fontconfig often maps `monospace` (even under `lang=zh`) to
  /// *Noto Sans Mono CJK JP*, whose Japanese `locl` forms misplace Chinese
  /// punctuation — and once JP covers CJK, later SC fallbacks never run.
  /// Color emoji is inserted before `monospace` for the same reason.
  static List<String> monoCjkFallback(TargetPlatform platform) {
    final emoji = colorEmojiFallback(platform);
    return switch (platform) {
      TargetPlatform.macOS => [
        'Monaco',
        'Courier New',
        'Noto Sans Mono CJK SC',
        ...emoji,
        'monospace',
      ],
      TargetPlatform.windows => [
        'Cascadia Mono',
        'Courier New',
        'Courier',
        'Noto Sans Mono CJK SC',
        ...emoji,
        'monospace',
      ],
      TargetPlatform.linux => [
        // Bundled JetBrainsMono NFM covers Latin. Explicit fallbacks are
        // resolved eagerly via fontconfig on every new paragraph (one ~140ms
        // scan per family), and none of the system mono faces are
        // FontLoader-registered — so keep only the registered emoji faces.
        // Missing CJK glyphs fall through to the engine's system font table
        // instead of paying a per-family scan.
        ...emoji,
      ],
      TargetPlatform.android => [
        'Noto Sans Mono CJK SC',
        'Noto Sans CJK SC',
        ...emoji,
        'monospace',
      ],
      _ => [
        'Noto Sans Mono CJK SC',
        'Noto Sans CJK SC',
        'WenQuanYi Zen Hei Mono',
        ...emoji,
        'monospace',
      ],
    };
  }

  static ({String family, List<String> fallback}) _resolveUi(
    FontCatalogEntry entry,
    TargetPlatform platform,
  ) {
    if (entry.source == FontSourceKind.bundled) {
      return (
        family: entry.bundledFamily!,
        fallback: _systemUiFallback(platform),
      );
    }
    return _systemUi(platform);
  }

  static ({String family, List<String> fallback}) _resolveMono(
    FontCatalogEntry entry,
    TargetPlatform platform,
  ) {
    if (entry.source == FontSourceKind.bundled) {
      return (
        family: entry.bundledFamily!,
        fallback: monoCjkFallback(platform),
      );
    }
    return _systemMono(platform);
  }

  static ({String family, List<String> fallback}) _systemUi(
    TargetPlatform platform,
  ) {
    final emoji = colorEmojiFallback(platform);
    return switch (platform) {
      TargetPlatform.macOS => (
        family: 'PingFang SC',
        fallback: [
          '.AppleSystemUIFont',
          'Heiti SC',
          'Helvetica Neue',
          ...emoji,
          'sans-serif',
        ],
      ),
      TargetPlatform.windows => (
        family: 'Segoe UI',
        fallback: ['Microsoft YaHei', ...emoji, 'sans-serif'],
      ),
      TargetPlatform.android => (
        family: 'sans-serif',
        fallback: ['Noto Sans CJK SC', 'Droid Sans Fallback', ...emoji],
      ),
      _ => (
        // An explicit family keeps Skia on the named-font path; an empty
        // family falls to the engine default typeface, which on Linux still
        // scans fontconfig per paragraph (same stall as the original bug).
        // Note: only the bundled Noto Sans SC (default preference) avoids the
        // scan entirely — the System path below always hits fontconfig.
        family: 'Noto Sans',
        fallback: [...emoji],
      ),
    };
  }

  static List<String> _systemUiFallback(TargetPlatform platform) =>
      _systemUi(platform).fallback;

  static ({String family, List<String> fallback}) _systemMono(
    TargetPlatform platform,
  ) {
    // Linux/Android: Latin-first primaries (Orca / PlatformFontDefaults). CJK
    // coverage comes from [monoCjkFallback] so ASCII is not sparsified by a
    // CJK-cell mono face used as the primary. macOS/Windows keep platform
    // natives with local CJK faces that are always installed.
    return switch (platform) {
      TargetPlatform.macOS => (
        family: 'Menlo',
        fallback: [
          'PingFang SC',
          'Heiti SC',
          'Noto Sans Mono CJK SC',
          ...colorEmojiFallback(platform),
          'monospace',
        ],
      ),
      TargetPlatform.windows => (
        family: 'Consolas',
        fallback: [
          'Cascadia Mono',
          'Microsoft YaHei',
          'Noto Sans Mono CJK SC',
          ...colorEmojiFallback(platform),
          'monospace',
        ],
      ),
      TargetPlatform.android => (
        family: 'Droid Sans Mono',
        fallback: [
          for (final face in monoCjkFallback(platform))
            if (face != 'Droid Sans Mono') face,
        ],
      ),
      _ => (
        // Mono must stay monospaced — an empty family falls back to the
        // system's default sans (non-monospace) and breaks terminal alignment.
        // DejaVu Sans Mono IS the fontconfig `monospace` default, so pinning it
        // here follows the system's monospace default rather than a made-up
        // name. Emoji is FontLoader-registered; missing CJK glyphs fall through
        // to the engine's system fallback.
        family: 'DejaVu Sans Mono',
        fallback: [
          for (final face in monoCjkFallback(platform))
            if (face != 'DejaVu Sans Mono') face,
        ],
      ),
    };
  }
}
