import '../../../../models/plugin.dart';
import '../../../io/filesystem.dart';
import '../../../plugin/plugin_bundle_resolver.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../../registry/plugins/grok_plugin_projector.dart';
import '../grok_constants.dart';
import '../grok_toml.dart';

/// Grok plugin materialization.
///
/// Enabled neutral bundles are copied to `<GROK_HOME>/plugins/<directory>/`
/// and projected onto Grok's native layout by [GrokPluginProjector]. Grok
/// auto-trusts plugins under `$GROK_HOME/plugins/` but still requires them in
/// `[plugins].enabled`, which TeamPilot writes into the isolated config.toml.
final class GrokPluginCapability implements PluginCapability {
  const GrokPluginCapability();

  static const pluginsDirName = 'plugins';

  @override
  bool get writesAssembledMcp => false;

  @override
  PluginRuntimeOwnership get runtimeOwnership =>
      PluginRuntimeOwnership.teamPilot;

  @override
  PluginManifestPaths? get manifestPaths => neutralPluginManifestPaths;

  @override
  List<String> get memberPluginsSubpath => const [pluginsDirName];

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
    final path = ctx.fs.pathContext;
    final pluginsRoot = path.join(ctx.configDir, pluginsDirName);
    final resolved = PluginBundleResolver.resolve(
      enabledPluginIds: ctx.enabledPluginIds,
      installedCatalog: ctx.installedCatalog,
    );

    final enabledNames = <String>{};
    for (final plugin in resolved.enabled) {
      final dirName = _bundleDirName(plugin);
      if (!GrokPluginProjector.isSafeDirName(dirName)) continue;
      final targetDir = path.join(pluginsRoot, dirName);
      if (!path.isWithin(pluginsRoot, targetDir)) continue;

      final bundleDir = path.join(ctx.bundlePoolDir, dirName);
      if (!(await ctx.fs.stat(bundleDir)).isDirectory) continue;
      final manifestName = await GrokPluginProjector.project(
        fs: ctx.fs,
        bundleDir: bundleDir,
        targetDir: targetDir,
      );
      enabledNames.add(
        manifestName?.trim().isNotEmpty == true
            ? manifestName!.trim()
            : (plugin.name.trim().isNotEmpty ? plugin.name.trim() : dirName),
      );
    }

    await _pruneStale(ctx.fs, pluginsRoot, {
      for (final plugin in resolved.enabled) _bundleDirName(plugin),
    });
    await mergeGrokTomlSection(
      fs: ctx.fs,
      configPath: path.join(ctx.configDir, GrokConstants.configFileName),
      section: 'plugins',
      values: {'enabled': enabledNames.toList(growable: false)},
    );
  }

  static String _bundleDirName(Plugin plugin) {
    final directory = plugin.directory.trim();
    return directory.isNotEmpty ? directory : plugin.name.trim();
  }

  static Future<void> _pruneStale(
    Filesystem fs,
    String pluginsRoot,
    Set<String> keep,
  ) async {
    if (!(await fs.stat(pluginsRoot)).isDirectory) return;
    for (final entry in await fs.listDir(pluginsRoot)) {
      if (entry.name.startsWith('.')) continue;
      if (keep.contains(entry.name)) continue;
      await fs.removeRecursive(fs.pathContext.join(pluginsRoot, entry.name));
    }
  }

  @override
  bool get consumesMarketplaces => false;

  @override
  bool get needsSharedPluginDepsBeforeReconcile => false;

  @override
  Future<void> seedSharedPluginDeps({
    required Filesystem homeFs,
    required String homeRoot,
  }) async {}

  @override
  String get pluginsSubdir => pluginsDirName;

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;
}
