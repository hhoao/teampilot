import '../../../io/filesystem.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../../registry/plugins/claude_flavor_registry_writer.dart';

/// CodeBuddy plugin registration (Claude-compatible wire format:
/// `plugins/`, `installed_plugins.json`, `known_marketplaces.json`,
/// `settings.json#enabledPlugins`).
final class CodebuddyPluginCapability implements PluginCapability {
  const CodebuddyPluginCapability();

  static const pluginManifestPaths = PluginManifestPaths(
    manifestDirName: '.codebuddy-plugin',
    fallbackManifestDirName: '.claude-plugin',
  );

  @override
  bool get writesAssembledMcp => false;

  @override
  PluginRuntimeOwnership get runtimeOwnership =>
      PluginRuntimeOwnership.teamPilot;

  @override
  PluginManifestPaths? get manifestPaths =>
      CodebuddyPluginCapability.pluginManifestPaths;

  @override
  List<String> get memberPluginsSubpath => const ['plugins'];

  @override
  Set<PluginComponentKind> get supported => const {
    PluginComponentKind.skills,
    PluginComponentKind.agents,
    PluginComponentKind.commands,
    PluginComponentKind.hooks,
    PluginComponentKind.mcp,
  };

  @override
  Future<void> provision(PluginProvisionContext ctx) async {
    await ClaudeFlavorRegistryWriter(
      fs: ctx.fs,
      teampilotRoot: ctx.teampilotRoot,
    ).write(
      configDir: ctx.configDir,
      memberPluginsDir: ctx.bundlePoolDir,
      tool: ctx.tool,
      enabledIds: ctx.enabledPluginIds,
      paths: manifestPaths ?? pluginManifestPaths,
      catalog: ctx.installedCatalog,
      memberProvisionJson: ctx.memberProvisionJson,
    );
  }

  @override
  bool get consumesMarketplaces => true;

  @override
  bool get needsSharedPluginDepsBeforeReconcile => false;

  @override
  Future<void> seedSharedPluginDeps({
    Filesystem? homeFs,
    String? homeRoot,
  }) async {}

  @override
  String get pluginsSubdir => 'plugins';

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;
}
