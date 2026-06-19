import 'dart:convert';

import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../../plugin/claude_flavor_registry_writer.dart';
import '../../../plugin/cli_plugin_layout.dart';
import '../capabilities/plugin_manifest_paths.dart';
import '../capabilities/plugin_provisioner_capability.dart';
import '../mcp_writers/cursor_mcp_config_writer.dart';

/// Cursor plugin materialization + Claude-flavor registry registration.
final class CursorPluginProvisioner implements PluginProvisionerCapability {
  const CursorPluginProvisioner();

  static const localPluginsSegment = 'local';

  @override
  PluginManifestPaths? get manifestPaths => cursorPluginManifestPaths;

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
    await _writeBundledMcp(ctx, paths);
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
      if ((await ctx.fs.stat(dest)).exists) {
        await ctx.fs.removeRecursive(dest);
      }
      await ctx.fs.copyTree(source: root, destination: dest);
      await CliPluginLayout.projectBundleToFlavor(ctx.fs, dest, paths);
    }
  }

  static Future<void> _writeBundledMcp(
    PluginProvisionContext ctx,
    PluginManifestPaths paths,
  ) async {
    final poolStat = await ctx.fs.stat(ctx.bundlePoolDir);
    if (!poolStat.isDirectory) return;

    final specs = <McpServerSpec>[];
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
      specs.addAll(await _readBundledMcp(ctx.fs, root));
    }
    if (specs.isEmpty) return;

    await const CursorMcpConfigWriter().write(
      fs: ctx.fs,
      configDir: ctx.configDir,
      servers: specs,
    );
  }

  static Future<List<McpServerSpec>> _readBundledMcp(
    Filesystem fs,
    String pluginRoot,
  ) async {
    final mcpPath = fs.pathContext.join(pluginRoot, '.mcp.json');
    if (!(await fs.stat(mcpPath)).isFile) return const [];

    final text = await fs.readString(mcpPath);
    if (text == null || text.trim().isEmpty) return const [];

    try {
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final servers = (root['mcpServers'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      return servers.entries
          .map(
            (e) => McpServerSpec.fromCatalogJson(
              e.key,
              (e.value as Map?)?.cast<String, Object?>() ?? const {},
            ),
          )
          .whereType<McpServerSpec>()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
