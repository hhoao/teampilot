import 'package:path/path.dart' as p;

import '../../../models/team_config.dart';
import '../../cli/registry/resources/cursor_resource_capability.dart';
import '../../storage/runtime_layout.dart';

/// Workspace+team scoped cursor warm tier shared across mixed-mode roster members.
abstract final class CursorWorkspaceWarmTier {
  CursorWorkspaceWarmTier._();

  static const toolId = 'cursor';
  static const teamsSegment = 'teams';
  static const mcpBaseFileName = 'mcp.base.json';
  static const settingsFileName = 'settings.json';
  static const pluginsDirName = 'plugins';
  static const localPluginsSegment = 'local';
  static const marketplacesSegment = 'marketplaces';
  static const installedPluginsFileName = 'installed_plugins.json';
  static const knownMarketplacesFileName = 'known_marketplaces.json';

  static bool applies({TeamProfile? team, required CliTool cli}) =>
      cli == CliTool.cursor && team?.teamMode == TeamMode.mixed;

  static String sharedRootRelative(String teamId) => p.join(
    'runtime',
    teamsSegment,
    teamId.trim(),
    toolId,
  );

  static String sharedRoot(
    RuntimeLayout layout,
    String workspaceId,
    String teamId,
  ) => layout.workspaceRuntimeToolDir(workspaceId.trim(), teamId.trim(), toolId);

  static String pluginsLocalDir(
    RuntimeLayout layout,
    String workspaceId,
    String teamId,
  ) => p.join(sharedRoot(layout, workspaceId, teamId), pluginsDirName, localPluginsSegment);

  static String pluginsMarketplacesDir(
    RuntimeLayout layout,
    String workspaceId,
    String teamId,
  ) => p.join(
    sharedRoot(layout, workspaceId, teamId),
    pluginsDirName,
    marketplacesSegment,
  );

  static String installedPluginsFile(
    RuntimeLayout layout,
    String workspaceId,
    String teamId,
  ) => p.join(
    sharedRoot(layout, workspaceId, teamId),
    pluginsDirName,
    installedPluginsFileName,
  );

  static String knownMarketplacesFile(
    RuntimeLayout layout,
    String workspaceId,
    String teamId,
  ) => p.join(
    sharedRoot(layout, workspaceId, teamId),
    pluginsDirName,
    knownMarketplacesFileName,
  );

  static String skillsCursorDir(
    RuntimeLayout layout,
    String workspaceId,
    String teamId,
  ) => p.join(
    sharedRoot(layout, workspaceId, teamId),
    CursorResourceCapability.skillsSubdirName,
  );

  static String settingsJson(
    RuntimeLayout layout,
    String workspaceId,
    String teamId,
  ) => p.join(sharedRoot(layout, workspaceId, teamId), settingsFileName);

  static String mcpBase(
    RuntimeLayout layout,
    String workspaceId,
    String teamId,
  ) => p.join(sharedRoot(layout, workspaceId, teamId), mcpBaseFileName);

  /// Relative paths under the workspace dir for [CliSessionManifestShared].
  static CliSessionManifestSharedPaths manifestPaths(String sharedRootRelative) {
    final root = sharedRootRelative.trim();
    return CliSessionManifestSharedPaths(
      root: root,
      pluginsLocalDir: p.join(root, pluginsDirName, localPluginsSegment),
      skillsCursorDir: p.join(root, CursorResourceCapability.skillsSubdirName),
      mcpBase: p.join(root, mcpBaseFileName),
      settingsJson: p.join(root, settingsFileName),
    );
  }

  static CliSessionManifestSharedPaths manifestPathsForTeam(String teamId) =>
      manifestPaths(sharedRootRelative(teamId));
}

/// Warm-tier relative paths recorded in the lifecycle manifest.
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
