import '../../../../models/plugin.dart';
import '../../../io/filesystem.dart';
import '../../../plugin/plugin_bundle_resolver.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../../registry/plugins/antigravity_plugin_projector.dart';

/// Antigravity plugin materialization.
///
/// TeamPilot owns the final installation: enabled neutral bundles from the
/// member bundle pool are copied to `<configDir>/plugins/<directory>/` and
/// projected onto Antigravity's native `plugin.json` + component layout by
/// [AntigravityPluginProjector].
///
/// The pool stores bundles under [Plugin.directory] (which may differ from the
/// plugin id, e.g. `acme/demo` → `demo-bundle`), so ids are resolved through
/// the installed catalog rather than used as path segments directly.
final class AntigravityPluginCapability implements PluginCapability {
  const AntigravityPluginCapability();

  static const pluginsDirName = 'plugins';

  /// Writer-managed pool entries that are never plugin bundles.
  static const managedEntryNames = {'marketplaces'};

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
    PluginComponentKind.hooks,
    PluginComponentKind.mcp,
    PluginComponentKind.rules,
  };

  @override
  Future<void> provision(PluginProvisionContext ctx) async {
    final path = ctx.fs.pathContext;
    final pluginsRoot = path.join(ctx.configDir, pluginsDirName);
    final resolved = PluginBundleResolver.resolve(
      enabledPluginIds: ctx.enabledPluginIds,
      installedCatalog: ctx.installedCatalog,
    );

    // Every enabled id that maps to a safe directory name, projected or not.
    // Used as the prune keep-set so a temporarily missing bundle does not drop
    // a previously projected (still enabled) plugin.
    final enabledNames = <String>{};
    for (final plugin in resolved.enabled) {
      final dirName = _bundleDirName(plugin);
      if (!AntigravityPluginProjector.isSafeDirName(dirName)) continue;
      final targetDir = path.join(pluginsRoot, dirName);
      if (!path.isWithin(pluginsRoot, targetDir)) continue;
      enabledNames.add(dirName);

      final bundleDir = path.join(ctx.bundlePoolDir, dirName);
      if (!(await ctx.fs.stat(bundleDir)).isDirectory) continue;
      await AntigravityPluginProjector.project(
        fs: ctx.fs,
        bundleDir: bundleDir,
        targetDir: targetDir,
      );
    }

    await _pruneStale(ctx.fs, pluginsRoot, enabledNames);
  }

  /// Pool entry name for [plugin]: its install directory, falling back to the
  /// plugin name when the catalog has no directory (mirrors
  /// `PluginBundlePoolService`).
  static String _bundleDirName(Plugin plugin) {
    final directory = plugin.directory.trim();
    return directory.isNotEmpty ? directory : plugin.name.trim();
  }

  /// Removes projected bundles that are no longer enabled. The CONFIG_DIR is
  /// session-scoped, so entries not in [keep] are safe to drop.
  static Future<void> _pruneStale(
    Filesystem fs,
    String pluginsRoot,
    Set<String> keep,
  ) async {
    if (!(await fs.stat(pluginsRoot)).isDirectory) return;
    for (final entry in await fs.listDir(pluginsRoot)) {
      if (entry.name.startsWith('.')) continue;
      if (managedEntryNames.contains(entry.name)) continue;
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
