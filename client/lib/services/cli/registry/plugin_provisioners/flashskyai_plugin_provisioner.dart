import '../capabilities/plugin_manifest_paths.dart';
import '../capabilities/plugin_provisioner_capability.dart';
import '../../../plugin/claude_flavor_registry_writer.dart';

/// FlashskyAI plugin registration (Claude-compatible wire format).
final class FlashskyaiPluginProvisioner implements PluginProvisionerCapability {
  const FlashskyaiPluginProvisioner();

  @override
  PluginManifestPaths? get manifestPaths => flashskyaiPluginManifestPaths;

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
}
