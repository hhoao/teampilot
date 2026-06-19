import 'dart:convert';

import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../../plugin/cli_plugin_layout.dart';
import '../../../resource/resource_kind.dart';
import '../capabilities/plugin_manifest_paths.dart';
import '../capabilities/plugin_provisioner_capability.dart';
import '../capabilities/resource_capability.dart';
import '../cli_tool_registry.dart';
import '../mcp_writers/opencode_mcp_config_writer.dart';

/// Decomposes plugin bundles into opencode skills/agents/mcp (no plugin registration).
final class OpencodePluginProvisioner implements PluginProvisionerCapability {
  const OpencodePluginProvisioner();

  static const agentSubdir = 'agent';

  @override
  PluginManifestPaths? get manifestPaths => null;

  @override
  Set<PluginComponentKind> get supported => const {
    PluginComponentKind.skills,
    PluginComponentKind.agents,
    PluginComponentKind.mcp,
  };

  @override
  Future<void> provision(PluginProvisionContext ctx) async {
    final poolStat = await ctx.fs.stat(ctx.bundlePoolDir);
    if (!poolStat.isDirectory) return;

    final resource =
        CliToolRegistry.builtIn().capability<ResourceCapability>(ctx.tool);
    if (resource == null) return;

    final skillSubdir = resource.subdirFor(ResourceKind.skill);
    final skillRoot = ctx.fs.pathContext.join(ctx.configDir, skillSubdir);
    final agentRoot = ctx.fs.pathContext.join(ctx.configDir, agentSubdir);
    final mcpSpecs = <McpServerSpec>[];

    for (final entry in await ctx.fs.listDir(ctx.bundlePoolDir)) {
      if (entry.name.startsWith('.')) continue;
      final source = ctx.fs.pathContext.join(ctx.bundlePoolDir, entry.name);
      if (!await CliPluginLayout.isPluginBundleEntry(ctx.fs, source)) continue;
      final root = await CliPluginLayout.resolvePluginRoot(
        ctx.fs,
        source,
        paths: neutralPluginManifestPaths,
      );
      if (root == null) continue;

      await _decomposeSkills(ctx.fs, root, skillRoot);
      await _decomposeAgents(ctx.fs, root, agentRoot);
      mcpSpecs.addAll(await _readBundledMcp(ctx.fs, root));
    }

    if (mcpSpecs.isEmpty) return;
    await const OpencodeMcpConfigWriter().write(
      fs: ctx.fs,
      configDir: ctx.configDir,
      servers: mcpSpecs,
    );
  }

  static Future<void> _decomposeSkills(
    Filesystem fs,
    String pluginRoot,
    String skillRoot,
  ) async {
    final skillsDir = fs.pathContext.join(pluginRoot, 'skills');
    if (!(await fs.stat(skillsDir)).isDirectory) return;

    for (final entry in await fs.listDir(skillsDir)) {
      if (!entry.isDirectory) continue;
      final skillName = entry.name;
      final dest = fs.pathContext.join(skillRoot, skillName);
      if ((await fs.stat(dest)).exists) continue;

      final source = fs.pathContext.join(skillsDir, skillName);
      final skillFile = fs.pathContext.join(source, 'SKILL.md');
      if (!(await fs.stat(skillFile)).isFile) continue;

      await fs.ensureDir(dest);
      await fs.copyTree(source: source, destination: dest);
    }
  }

  static Future<void> _decomposeAgents(
    Filesystem fs,
    String pluginRoot,
    String agentRoot,
  ) async {
    final agentsDir = fs.pathContext.join(pluginRoot, 'agents');
    if (!(await fs.stat(agentsDir)).isDirectory) return;

    await fs.ensureDir(agentRoot);
    for (final entry in await fs.listDir(agentsDir)) {
      if (entry.isDirectory || !entry.name.endsWith('.md')) continue;
      final agentName = fs.pathContext.basenameWithoutExtension(entry.name);
      final dest = fs.pathContext.join(agentRoot, '$agentName.md');
      if ((await fs.stat(dest)).isFile) continue;

      final source = fs.pathContext.join(agentsDir, entry.name);
      final content = await fs.readString(source);
      if (content == null) continue;
      await fs.atomicWrite(dest, content);
    }
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
