import 'package:path/path.dart' as p;

import '../capabilities/skill.dart';

/// Cursor mixed-mode path constants and lifecycle manifest relative paths.
///
/// Team resource files (MCP, plugins, settings) live under each member session
/// runtime tree; [sharedRootRelative] only anchors `init.json`.
abstract final class CursorWorkspaceWarmTier {
  CursorWorkspaceWarmTier._();

  static const toolId = 'cursor';
  static const teamsSegment = 'teams';
  static const settingsFileName = 'settings.json';
  static const pluginsDirName = 'plugins';
  static const localPluginsSegment = 'local';
  static const marketplacesSegment = 'marketplaces';
  static const installedPluginsFileName = 'installed_plugins.json';
  static const knownMarketplacesFileName = 'known_marketplaces.json';

  static String sharedRootRelative(String teamId) =>
      p.posix.join('runtime', teamsSegment, teamId.trim(), toolId);

  /// Relative paths under the workspace dir for [CliSessionManifestShared].
  static CliSessionManifestSharedPaths manifestPaths(
    String sharedRootRelative,
  ) {
    final root = sharedRootRelative.trim();
    return CliSessionManifestSharedPaths(
      root: root,
      pluginsLocalDir: p.posix.join(root, pluginsDirName, localPluginsSegment),
      skillsCursorDir: p.posix.join(
        root,
        CursorSkillCapability.skillsSubdirName,
      ),
      mcpBase: p.posix.join(root, 'mcp.base.json'),
      settingsJson: p.posix.join(root, settingsFileName),
    );
  }

  static CliSessionManifestSharedPaths manifestPathsForTeam(String teamId) =>
      manifestPaths(sharedRootRelative(teamId));
}

/// Lifecycle manifest relative paths (legacy fields; resource dirs are per member).
final class CliSessionManifestSharedPaths {
  const CliSessionManifestSharedPaths({
    required this.root,
    required this.pluginsLocalDir,
    required this.skillsCursorDir,
    required this.mcpBase,
    required this.settingsJson,
  });

  final String root;
  final String pluginsLocalDir;
  final String skillsCursorDir;
  final String mcpBase;
  final String settingsJson;
}
