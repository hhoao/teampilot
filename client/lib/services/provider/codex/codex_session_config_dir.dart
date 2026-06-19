import 'package:path/path.dart' as p;

import '../../storage/runtime_layout.dart';

/// Resolves the on-disk config root Codex reads for a session member.
///
/// Codex is launched with `CODEX_HOME` pointing at the session tool dir
/// (`config.toml`, `plugins/cache/…`, `skills/`). Unlike Cursor, there is no
/// nested `home/` segment — mixed and standalone both use the same root.
abstract final class CodexSessionConfigDir {
  CodexSessionConfigDir._();

  static const toolId = 'codex';

  static String resolve(
    RuntimeLayout layout, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) {
    return layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      toolId,
      memberId: memberId,
    );
  }

  static const localMarketplaceName = 'local';

  /// Personal marketplace manifest: `.agents/plugins/marketplace.json`.
  static String localMarketplaceManifestPath(String configDir) {
    return p.join(configDir, '.agents', 'plugins', 'marketplace.json');
  }

  /// Source tree Codex reads from the local marketplace entry (`./plugins/<name>/`).
  static String localPluginSourceRoot(String configDir, String pluginName) {
    return p.join(configDir, 'plugins', pluginName);
  }

  /// Installed copy Codex loads at runtime:
  /// `plugins/cache/local/<name>/<version>/` (`local` when manifest has no version).
  static String localPluginCacheRoot(
    String configDir,
    String pluginName, {
    String version = 'local',
  }) {
    return p.join(
      configDir,
      'plugins',
      'cache',
      localMarketplaceName,
      pluginName,
      version,
    );
  }
}
