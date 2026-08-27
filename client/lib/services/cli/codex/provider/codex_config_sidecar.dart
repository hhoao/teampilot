import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

import '../../../io/filesystem.dart';

/// Top-level `config.toml` keys whose string values are paths relative to
/// `CODEX_HOME`. Extend this list when Codex or CC Switch adds new sidecars.
abstract final class CodexConfigSidecarCatalog {
  CodexConfigSidecarCatalog._();

  static const relativePathKeys = <String>[
    'model_catalog_json',
  ];
}

/// One companion file referenced from Codex `config.toml`.
final class CodexConfigSidecarRef {
  const CodexConfigSidecarRef({
    required this.tomlKey,
    required this.relativePath,
  });

  final String tomlKey;
  final String relativePath;
}

/// Raised when a referenced sidecar cannot be materialized into `CODEX_HOME`.
final class CodexConfigSidecarException implements Exception {
  CodexConfigSidecarException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Resolves and materializes `config.toml` companion files for Codex homes.
abstract final class CodexConfigSidecar {
  CodexConfigSidecar._();

  /// Parses [configToml] structurally so quote style and TOML round-trips do
  /// not affect discovery.
  static List<CodexConfigSidecarRef> parseRefs(String configToml) {
    if (configToml.trim().isEmpty) return const [];

    final root = TomlDocument.parse(configToml).toMap();
    final refs = <CodexConfigSidecarRef>[];
    for (final key in CodexConfigSidecarCatalog.relativePathKeys) {
      final relativePath = _coerceRelativePath(root[key]);
      if (relativePath == null) continue;
      refs.add(CodexConfigSidecarRef(tomlKey: key, relativePath: relativePath));
    }
    return refs;
  }

  /// Copies referenced sidecars from live `~/.codex` into a provider catalog
  /// directory when the provider row is saved or imported.
  static Future<void> persistFromLiveCodexHome({
    required Filesystem fs,
    required String providerDir,
    required String configToml,
    required String liveCodexHome,
  }) async {
    final refs = parseRefs(configToml);
    if (refs.isEmpty) return;

    final home = liveCodexHome.trim();
    if (home.isEmpty) return;

    final liveCodexDir = fs.pathContext.join(home, '.codex');
    await _copyRefs(
      fs: fs,
      refs: refs,
      sourceDir: liveCodexDir,
      destDir: providerDir,
      skipExistingDest: true,
      missingSourceIsError: false,
    );
  }

  /// Copies referenced sidecars from the provider catalog into a session
  /// `CODEX_HOME`. Missing required files fail fast so Codex never starts with
  /// a broken `config.toml`.
  static Future<void> materializeIntoCodexHome({
    required Filesystem fs,
    required String providerDir,
    required String codexHome,
    required String configToml,
  }) async {
    final refs = parseRefs(configToml);
    if (refs.isEmpty) return;

    await _copyRefs(
      fs: fs,
      refs: refs,
      sourceDir: providerDir,
      destDir: codexHome,
      skipExistingDest: true,
      missingSourceIsError: true,
    );
  }

  static String? _coerceRelativePath(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || p.isAbsolute(trimmed)) return null;
    return trimmed;
  }

  static Future<void> _copyRefs({
    required Filesystem fs,
    required List<CodexConfigSidecarRef> refs,
    required String sourceDir,
    required String destDir,
    required bool skipExistingDest,
    required bool missingSourceIsError,
  }) async {
    final ctx = fs.pathContext;
    for (final ref in refs) {
      final dest = ctx.normalize(ctx.join(destDir, ref.relativePath));
      if (skipExistingDest && (await fs.stat(dest)).isFile) continue;

      final src = ctx.normalize(ctx.join(sourceDir, ref.relativePath));
      if (!(await fs.stat(src)).isFile) {
        if (missingSourceIsError) {
          throw CodexConfigSidecarException(
            'Codex config.toml references ${ref.tomlKey} = '
            '"${ref.relativePath}" but the file is missing under '
            '$sourceDir',
          );
        }
        continue;
      }

      await fs.ensureDir(ctx.dirname(dest));
      await fs.copyFile(src, dest);
    }
  }
}
