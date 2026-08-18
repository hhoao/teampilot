import 'package:flutter/foundation.dart';

import '../../../../models/plugin.dart';
import '../../../../models/mcp_server_spec.dart';
import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../storage/runtime_layout.dart';
import '../cli_capability.dart';
import '../cli_tool_registry.dart';
import 'plugin_manifest_paths.dart';
import 'skill_capability.dart';

/// Component kinds a plugin bundle may carry.
enum PluginComponentKind { skills, agents, commands, hooks, mcp, rules, apps }

/// Inputs for [PluginCapability.provision].
@immutable
class PluginProvisionContext {
  const PluginProvisionContext({
    required this.fs,
    required this.teampilotRoot,
    required this.configDir,
    required this.bundlePoolDir,
    required this.enabledPluginIds,
    required this.installedCatalog,
    required this.layout,
    required this.tool,
    this.memberProvisionJson,
    this.assembledMcpServers = const [],
    this.mcpConfigFileName,
  });

  final Filesystem fs;
  final String teampilotRoot;
  final String configDir;
  final String bundlePoolDir;
  final List<String> enabledPluginIds;
  final List<Plugin> installedCatalog;
  final RuntimeLayout layout;
  final CliTool tool;
  final String? memberProvisionJson;
  final List<McpServerSpec> assembledMcpServers;

  /// When set, overrides the MCP config filename (e.g. `mcp.base.json`).
  final String? mcpConfigFileName;
}

/// PluginHub contract: plugin materialization + marketplace consumption +
/// remote shared dep seeding.
abstract interface class PluginCapability implements CliCapability {
  bool get writesAssembledMcp => false;

  /// On-disk manifest layout this CLI reads. `null` ⇒ decomposition only.
  PluginManifestPaths? get manifestPaths;

  /// Path segments (relative to the CONFIG_DIR) of the directory holding
  /// materialized plugin bundles — e.g. `['plugins']`, or cursor's
  /// `['plugins', 'local']`. Used by member-config inspection to list bundles.
  List<String> get memberPluginsSubpath;

  /// Components this CLI loads from a bundle.
  Set<PluginComponentKind> get supported;

  Future<void> provision(PluginProvisionContext ctx);

  /// Whether this CLI consumes marketplace plugins from CONFIG_DIR.
  ///
  /// Only claude, flashskyai, and cursor consume marketplaces.
  bool get consumesMarketplaces;

  /// Whether this CLI needs shared plugin deps seeded on the remote home
  /// before provider reconciliation.
  bool get needsSharedPluginDepsBeforeReconcile;

  Future<void> seedSharedPluginDeps({
    required Filesystem homeFs,
    required String homeRoot,
  });

  /// Subdirectory (relative to the CONFIG_DIR) where plugin entries live, for
  /// `linkedDirectory` kinds (e.g. 'plugins', or cursor's 'plugins/local').
  String get pluginsSubdir;

  /// How plugins are represented inside the CLI's CONFIG_DIR.
  ResourceRepresentation get pluginsRepresentation;
}

const neutralPluginManifestPaths = PluginManifestPaths(
  manifestDirName: '.plugin',
  fallbackManifestDirName: '.claude-plugin',
);

const codexPluginManifestPaths = PluginManifestPaths(
  manifestDirName: '.codex-plugin',
  fallbackManifestDirName: '.claude-plugin',
);

const cursorPluginManifestPaths = PluginManifestPaths(
  manifestDirName: '.cursor-plugin',
  fallbackManifestDirName: '.claude-plugin',
);

PluginCapability? pluginCapabilityForTool(
  CliTool tool, {
  CliToolRegistry? registry,
}) =>
    (registry ?? CliToolRegistry.builtIn()).capability<PluginCapability>(tool);
