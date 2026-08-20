import '../../../io/filesystem.dart';
import '../../../cli/registry/plugins/claude_flavor_registry_writer.dart';
import '../../../plugin/cli_plugin_layout.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../provider/cursor_plugin_runtime_tree.dart';
import 'mcp.dart';

/// Cursor plugin materialization + Claude-flavor registry registration.
final class CursorPluginCapability implements PluginCapability {
  const CursorPluginCapability();

  @override
  PluginRuntimeOwnership get runtimeOwnership =>
      PluginRuntimeOwnership.teamPilot;

  static const localPluginsSegment = 'local';

  @override
  PluginManifestPaths? get manifestPaths => cursorPluginManifestPaths;

  @override
  List<String> get memberPluginsSubpath => const [
    'plugins',
    localPluginsSegment,
  ];

  @override
  Set<PluginComponentKind> get supported => const {
    PluginComponentKind.rules,
    PluginComponentKind.skills,
    PluginComponentKind.agents,
    PluginComponentKind.commands,
    PluginComponentKind.hooks,
    PluginComponentKind.mcp,
  };

  @override
  Future<void> provision(PluginProvisionContext ctx) async {
    final paths = manifestPaths!;
    final localDir = ctx.fs.pathContext.join(
      ctx.configDir,
      'plugins',
      localPluginsSegment,
    );
    await _materializeToLocal(ctx, localDir, paths);
    if (ctx.assembledMcpServers.isNotEmpty) {
      await const CursorMcpCapability().write(
        fs: ctx.fs,
        configDir: ctx.configDir,
        servers: ctx.assembledMcpServers,
        outputBasename: ctx.mcpConfigFileName,
      );
    }
    await ClaudeFlavorRegistryWriter(
      fs: ctx.fs,
      teampilotRoot: ctx.teampilotRoot,
    ).write(
      configDir: ctx.configDir,
      memberPluginsDir: localDir,
      tool: ctx.tool,
      enabledIds: ctx.enabledPluginIds,
      paths: paths,
      catalog: ctx.installedCatalog,
      memberProvisionJson: ctx.memberProvisionJson,
    );
  }

  @override
  bool get writesAssembledMcp => true;

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
  String get pluginsSubdir => 'plugins/$localPluginsSegment';

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  static Future<void> _materializeToLocal(
    PluginProvisionContext ctx,
    String localDir,
    PluginManifestPaths paths,
  ) async {
    final poolStat = await ctx.fs.stat(ctx.bundlePoolDir);
    if (!poolStat.isDirectory) return;

    await ctx.fs.ensureDir(localDir);
    final fsCtx = ctx.fs.pathContext;
    for (final entry in await ctx.fs.listDir(ctx.bundlePoolDir)) {
      if (entry.name.startsWith('.')) continue;
      final source = fsCtx.join(ctx.bundlePoolDir, entry.name);
      if (!await CliPluginLayout.isPluginBundleEntry(ctx.fs, source)) continue;
      final root = await CliPluginLayout.resolvePluginRoot(
        ctx.fs,
        source,
        paths: paths,
      );
      if (root == null) continue;

      final dirName = await CliPluginLayout.bundleDirName(
        ctx.fs,
        root,
        paths: paths,
      );
      final dest = fsCtx.join(localDir, dirName);
      // Keep a real directory under `plugins/local` so cursor-agent's
      // realpath check accepts the bundle, and only symlink component
      // dirs so a pool `.git` is never listed at the plugin root.
      await CursorPluginRuntimeTree.materialize(
        fs: ctx.fs,
        sourceRoot: root,
        destRoot: dest,
        paths: paths,
      );
      await CliPluginLayout.projectBundleToFlavor(ctx.fs, dest, paths);
    }
  }
}
