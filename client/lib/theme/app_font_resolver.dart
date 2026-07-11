import 'package:flutter/foundation.dart';

import 'font_catalog.dart';

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

  /// Silent Ubuntu fallback asset family (may appear in mono fallback chains).
  static const String ubuntuSansMonoFamily = 'Ubuntu Sans Mono';

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
      return (
        family: installedKey,
        fallback: fallback,
        needsBundledLoad: false,
        needsInstalledLoad: true,
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

  /// Platform CJK mono fallback chain (primary excluded). Used by bundled mono
  /// and by [AppFonts.monoFamilyFallback] for backward-compatible callers.
  ///
  /// A Simplified-Chinese CJK mono face is listed before the generic
  /// `monospace` alias on purpose: fontconfig often maps `monospace` (even
  /// under `lang=zh`) to *Noto Sans Mono CJK JP*, whose Japanese `locl` forms
  /// misplace Chinese punctuation.
  static List<String> monoCjkFallback(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.macOS => const [
        ubuntuSansMonoFamily,
        'PingFang SC',
        'Heiti SC',
        'monospace',
      ],
      TargetPlatform.windows => const [
        ubuntuSansMonoFamily,
        'Microsoft YaHei',
        'monospace',
      ],
      _ => const [
        ubuntuSansMonoFamily,
        'Noto Sans Mono CJK SC',
        'Noto Sans CJK SC',
        'WenQuanYi Zen Hei Mono',
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
    return switch (platform) {
      TargetPlatform.macOS => (
        family: 'PingFang SC',
        fallback: const [
          '.AppleSystemUIFont',
          'Heiti SC',
          'Helvetica Neue',
          'sans-serif',
        ],
      ),
      TargetPlatform.windows => (
        family: 'Segoe UI',
        fallback: const [
          'Microsoft YaHei',
          'Segoe UI Emoji',
          'sans-serif',
        ],
      ),
      TargetPlatform.android => (
        family: 'sans-serif',
        fallback: const [
          'Noto Sans CJK SC',
          'Droid Sans Fallback',
        ],
      ),
      _ => (
        family: 'Noto Sans',
        fallback: const [
          'Noto Sans CJK SC',
          'WenQuanYi Zen Hei',
          'sans-serif',
        ],
      ),
    };
  }

  static List<String> _systemUiFallback(TargetPlatform platform) =>
      _systemUi(platform).fallback;

  static ({String family, List<String> fallback}) _systemMono(
    TargetPlatform platform,
  ) {
    return switch (platform) {
      TargetPlatform.macOS => (
        family: 'Menlo',
        fallback: const [
          ubuntuSansMonoFamily,
          'PingFang SC',
          'Heiti SC',
          'monospace',
        ],
      ),
      TargetPlatform.windows => (
        family: 'Consolas',
        fallback: const [
          ubuntuSansMonoFamily,
          'Microsoft YaHei',
          'monospace',
        ],
      ),
      TargetPlatform.android => (
        family: 'Noto Sans Mono CJK SC',
        fallback: const [
          ubuntuSansMonoFamily,
          'Noto Sans CJK SC',
          'Droid Sans Mono',
          'monospace',
        ],
      ),
      _ => (
        family: 'Noto Sans Mono CJK SC',
        fallback: const [
          ubuntuSansMonoFamily,
          'Noto Sans CJK SC',
          'WenQuanYi Zen Hei Mono',
          'monospace',
        ],
      ),
    };
  }
}
