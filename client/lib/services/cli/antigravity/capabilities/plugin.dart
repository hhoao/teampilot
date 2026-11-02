import '../../../io/filesystem.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../../registry/plugins/antigravity_plugin_projector.dart';

/// Antigravity plugin materialization.
///
/// TeamPilot owns the final installation: enabled neutral bundles from the
/// member bundle pool are copied to `<configDir>/plugins/<id>/` and projected
/// onto Antigravity's native `plugin.json` + component layout by
/// [AntigravityPluginProjector].
final class AntigravityPluginCapability implements PluginCapability {
  const AntigravityPluginCapability();

  @override
  bool get writesAssembledMcp => false;

  @override
  PluginRuntimeOwnership get runtimeOwnership =>
      PluginRuntimeOwnership.teamPilot;

  @override
  PluginManifestPaths? get manifestPaths => neutralPluginManifestPaths;

  @override
  List<String> get memberPluginsSubpath => const ['plugins'];

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
    for (final id in ctx.enabledPluginIds) {
      final bundle = ctx.fs.pathContext.join(ctx.bundlePoolDir, id);
      if (!(await ctx.fs.stat(bundle)).isDirectory) continue;
      await AntigravityPluginProjector.project(
        fs: ctx.fs,
        bundleDir: bundle,
        targetDir: ctx.fs.pathContext.join(ctx.configDir, 'plugins', id),
      );
    }
  }

  @override
  bool get consumesMarketplaces => true;

  @override
  bool get needsSharedPluginDepsBeforeReconcile => false;

  @override
  Future<void> seedSharedPluginDeps({
    required Filesystem homeFs,
    required String homeRoot,
  }) async {}

  @override
  String get pluginsSubdir => 'plugins';

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;
}
