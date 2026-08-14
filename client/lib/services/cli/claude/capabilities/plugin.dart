import '../../../io/filesystem.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../../registry/plugins/claude_flavor_registry_writer.dart';

/// Claude Code plugin registration (`enabledPlugins`, installed_plugins v2).
final class ClaudePluginCapability implements PluginCapability {
  const ClaudePluginCapability();

  @override
  PluginManifestPaths? get manifestPaths => claudePluginManifestPaths;

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
      paths: manifestPaths!,
      catalog: ctx.installedCatalog,
      memberProvisionJson: ctx.memberProvisionJson,
    );
  }

  @override
  bool get consumesMarketplaces => true;

  @override
  bool get needsSharedPluginDepsBeforeReconcile => false;

  @override
  Future<void> seedSharedPluginDeps({Filesystem? homeFs, String? homeRoot}) async {}

  @override
  String get pluginsSubdir => 'plugins';

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;
}
