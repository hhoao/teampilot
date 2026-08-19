import 'dart:convert';

import '../../../io/filesystem.dart';
import '../../../plugin/cli_plugin_layout.dart';
import '../../../storage/runtime_layout.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../../registry/cli_tool_registry.dart';
import '../provider/opencode_shared_plugin_deps.dart';
import 'provider.dart';
import 'mcp.dart';

/// Materializes plugin bundles for opencode:
/// - decomposes skills/agents/mcp into opencode's on-disk layout
/// - bundles shipping an opencode plugin (`.opencode/{plugin,plugins}/*.{js,ts}`
///   or a root `package.json` `main` entry) are copied into
///   `<configDir>/plugins/<name>/` and registered in `opencode.json` `plugin`
///   so opencode loads them at startup (path specs resolve relative to the
///   config file — no npm install needed).
final class OpencodePluginCapability implements PluginCapability {
  const OpencodePluginCapability();

  @override
  PluginRuntimeOwnership get runtimeOwnership =>
      PluginRuntimeOwnership.teamPilot;

  static const agentSubdir = 'agent';
  static const pluginsSubdirName = 'plugins';
  static const opencodeFlavorDir = '.opencode';
  static const _opencodePluginDirs = ['plugins', 'plugin'];

  @override
  PluginManifestPaths? get manifestPaths => null;

  // Materialized bundles land under `plugins/`; inspection lists them here.
  @override
  List<String> get memberPluginsSubpath => const [pluginsSubdirName];

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

    final skill = CliToolRegistry.builtIn().capability<SkillCapability>(
      ctx.tool,
    );
    if (skill == null) return;

    final skillRoot = ctx.fs.pathContext.join(
      ctx.configDir,
      skill.skillsSubdir,
    );
    final agentRoot = ctx.fs.pathContext.join(ctx.configDir, agentSubdir);
    final pluginEntries = <String>[];

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
      pluginEntries.addAll(
        await _materializeOpencodePlugin(
          ctx.fs,
          ctx.configDir,
          entry.name,
          root,
        ),
      );
    }

    if (ctx.assembledMcpServers.isNotEmpty) {
      await const OpencodeMcpCapability().write(
        fs: ctx.fs,
        configDir: ctx.configDir,
        servers: ctx.assembledMcpServers,
      );
    }
    if (pluginEntries.isNotEmpty) {
      await _mergePluginEntries(ctx.fs, ctx.configDir, pluginEntries);
    }
  }

  @override
  bool get writesAssembledMcp => true;

  @override
  bool get consumesMarketplaces => false;

  @override
  bool get needsSharedPluginDepsBeforeReconcile => true;

  @override
  Future<void> seedSharedPluginDeps({
    required Filesystem homeFs,
    required String homeRoot,
  }) async {
    final homeLayout = RuntimeLayout(teampilotRoot: homeRoot, fs: homeFs);
    await OpencodeSharedPluginDeps(
      layout: homeLayout,
      fs: homeFs,
    ).ensureSharedInstalled();
  }

  @override
  String get pluginsSubdir => pluginsSubdirName;

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  /// Copies the whole bundle into `<configDir>/plugins/<name>/` when it ships
  /// an opencode plugin, returning `plugin` array entries (`./plugins/...`)
  /// for each entry file. The full tree is copied (not just the entry file)
  /// because opencode plugins resolve sibling content relative to
  /// `import.meta.url` / `__dirname` (e.g. superpowers reads `../../skills`).
  static Future<List<String>> _materializeOpencodePlugin(
    Filesystem fs,
    String configDir,
    String poolEntryName,
    String pluginRoot,
  ) async {
    final rels = await _discoverPluginEntryFiles(fs, pluginRoot);
    if (rels.isEmpty) return const [];

    final ctx = fs.pathContext;
    final destRoot = ctx.join(configDir, pluginsSubdirName, poolEntryName);
    // For opencode the bundle pool dir IS `{configDir}/plugins` (the pool
    // reconcile already materialized the full bundle at the pool entry), so
    // the source sits exactly where the plugin would be copied. Linking it
    // onto itself would replace the pool entry with a self-referencing
    // symlink loop and break both the plugin JS and decomposed skills.
    final alreadyInPlace =
        ctx.equals(destRoot, pluginRoot) || ctx.isWithin(destRoot, pluginRoot);
    if (!alreadyInPlace) {
      await CliPluginLayout.linkOrCopyTree(
        fs: fs,
        source: pluginRoot,
        destination: destRoot,
      );
    }
    return [for (final rel in rels) './$pluginsSubdirName/$poolEntryName/$rel'];
  }

  /// Discovers opencode plugin entry files under [pluginRoot], mirroring
  /// opencode's own convention (`{plugin,plugins}/*.{js,ts}` under
  /// `.opencode/`), falling back to a root `package.json` `main` pointing at
  /// a JS/TS source file inside the bundle.
  static Future<List<String>> _discoverPluginEntryFiles(
    Filesystem fs,
    String pluginRoot,
  ) async {
    final ctx = fs.pathContext;
    final out = <String>[];
    final opencodeDir = ctx.join(pluginRoot, opencodeFlavorDir);
    if ((await fs.stat(opencodeDir)).isDirectory) {
      for (final dirName in _opencodePluginDirs) {
        final dir = ctx.join(opencodeDir, dirName);
        if (!(await fs.stat(dir)).isDirectory) continue;
        for (final entry in await fs.listDir(dir)) {
          if (entry.isDirectory) continue;
          if (!_isPluginSourceFile(entry.name)) continue;
          // opencode.json plugin entries are POSIX-relative (the CLI runs on
          // any host), never host-separator paths.
          out.add('$opencodeFlavorDir/$dirName/${entry.name}');
        }
      }
    }
    if (out.isNotEmpty) return out;

    final pkgJson = ctx.join(pluginRoot, 'package.json');
    if (!(await fs.stat(pkgJson)).isFile) return const [];
    final text = await fs.readString(pkgJson);
    if (text == null || text.trim().isEmpty) return const [];
    try {
      final json = (jsonDecode(text) as Map).cast<String, Object?>();
      final main = (json['main'] as String?)?.trim() ?? '';
      if (!_isPluginSourceFile(main)) return const [];
      if ((await fs.stat(ctx.join(pluginRoot, main))).isFile) {
        out.add(main);
      }
    } on Object {
      // Invalid package.json — ignore, decomposition still applies.
    }
    return out;
  }

  static bool _isPluginSourceFile(String name) {
    return name.endsWith('.js') ||
        name.endsWith('.mjs') ||
        name.endsWith('.cjs') ||
        name.endsWith('.ts') ||
        name.endsWith('.tsx');
  }

  /// Merges materialized plugin entries into `opencode.json` `plugin` array.
  static Future<void> _mergePluginEntries(
    Filesystem fs,
    String configDir,
    List<String> entries,
  ) async {
    final configPath = fs.pathContext.join(
      configDir,
      OpencodeProviderCapability.opencodeConfigFileName,
    );
    final stat = await fs.stat(configPath);
    Map<String, Object?> existing;
    if (stat.isFile) {
      final text = await fs.readString(configPath);
      existing = text == null || text.trim().isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>();
    } else {
      existing = <String, Object?>{};
    }

    final merged = mergeOpencodePluginEntries(existing, entries);
    if (identical(merged, existing)) return;

    await fs.ensureDir(fs.pathContext.dirname(configPath));
    await fs.atomicWrite(
      configPath,
      const JsonEncoder.withIndent('  ').convert(merged),
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

      await CliPluginLayout.linkOrCopyTree(
        fs: fs,
        source: source,
        destination: dest,
      );
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
}
