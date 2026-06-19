import 'package:flutter/foundation.dart';

import '../../../../models/plugin.dart';
import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../storage/runtime_layout.dart';
import '../cli_capability.dart';
import '../cli_tool_registry.dart';
import 'plugin_manifest_paths.dart';

/// Component kinds a plugin bundle may carry.
enum PluginComponentKind {
  skills,
  agents,
  commands,
  hooks,
  mcp,
  rules,
  apps,
}

/// Inputs for [PluginProvisionerCapability.provision].
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
}

/// Owns materialize + native registration for one CLI's plugin format.
abstract interface class PluginProvisionerCapability implements CliCapability {
  /// On-disk manifest layout this CLI reads. `null` ⇒ decomposition only.
  PluginManifestPaths? get manifestPaths;

  /// Components this CLI loads from a bundle.
  Set<PluginComponentKind> get supported;

  Future<void> provision(PluginProvisionContext ctx);
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

PluginManifestPaths? pluginManifestPathsForTool(
  CliTool tool, {
  CliToolRegistry? registry,
}) =>
    (registry ?? CliToolRegistry.builtIn())
        .capability<PluginProvisionerCapability>(tool)
        ?.manifestPaths;

PluginProvisionerCapability? pluginProvisionerForTool(
  CliTool tool, {
  CliToolRegistry? registry,
}) =>
    (registry ?? CliToolRegistry.builtIn())
        .capability<PluginProvisionerCapability>(tool);
