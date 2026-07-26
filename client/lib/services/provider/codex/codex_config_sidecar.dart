import 'package:path/path.dart' as p;

import '../../io/filesystem.dart';

/// `config.toml` sidecar files (e.g. CC Switch `model_catalog_json`).
abstract final class CodexConfigSidecar {
  static final _modelCatalogJsonRef = RegExp(
    r'^\s*model_catalog_json\s*=\s*"([^"]+)"',
    multiLine: true,
  );

  static String? modelCatalogJsonRef(String configToml) {
    return _modelCatalogJsonRef.firstMatch(configToml)?.group(1)?.trim();
  }

  /// Copies a referenced sidecar from live `~/.codex` into the provider dir.
  static Future<void> persistFromLiveCodexHome({
    required Filesystem fs,
    required String providerDir,
    required String configToml,
    required String liveCodexHome,
  }) async {
    final ref = modelCatalogJsonRef(configToml);
    if (ref == null || ref.isEmpty || p.isAbsolute(ref)) return;

    final ctx = fs.pathContext;
    final dest = ctx.normalize(ctx.join(providerDir, ref));
    if ((await fs.stat(dest)).isFile) return;

    final home = liveCodexHome.trim();
    if (home.isEmpty) return;

    final src = ctx.join(home, '.codex', ref);
    if (!(await fs.stat(src)).isFile) return;

    await fs.ensureDir(ctx.dirname(dest));
    await fs.copyFile(src, dest);
  }

  /// Copies a referenced sidecar from the provider dir into `CODEX_HOME`.
  static Future<void> copyIntoCodexHome({
    required Filesystem fs,
    required String providerDir,
    required String codexHome,
    required String configToml,
  }) async {
    final ref = modelCatalogJsonRef(configToml);
    if (ref == null || ref.isEmpty || p.isAbsolute(ref)) return;

    final ctx = fs.pathContext;
    final src = ctx.normalize(ctx.join(providerDir, ref));
    if (!(await fs.stat(src)).isFile) return;

    final dest = ctx.normalize(ctx.join(codexHome, ref));
    if ((await fs.stat(dest)).isFile) return;

    await fs.ensureDir(ctx.dirname(dest));
    await fs.copyFile(src, dest);
  }
}
